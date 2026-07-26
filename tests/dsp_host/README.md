# DSP host tests

S2-01 covers the public Core API and instance state. S2-02 adds host-stub
coverage for shared platform initialization, Timer2, W5300 memory/network
readback, failure short-circuiting, and reset timing source evidence. S2-03
adds the generic IoDevice boundary, Fake IoDevice Core linking, and independent
W5300 channel coverage. S2-03A adds the internal const Config and algorithm
adapter contract, static two-instance binding, routing/isolation, and invalid
configuration boundary coverage. S2-04 adds bounded W5300 HAL command/size
access and per-channel Socket command progression. S2-05 delays public send
progress until the corresponding W5300 `SEND_OK` event. S2-06 adds the
per-Channel bounded close transaction, Erratum 1 workaround, software deadline,
fault gate, and PlatformInit generation recovery.

## S2-04 W5300 evidence and call budget

Official references: WIZnet **W5300 Datasheet v1.3.4**, **W5300 Errata Sheet
v1.2.3**, and the official **ioLibrary_Driver W5300** implementation. The
datasheet sequences used here are:

- OPEN: clear this socket's pending interrupt indication, write `Sn_MR`, TCP
  options, `Sn_PORTR`, then issue `OPEN`; observe `SOCK_INIT` on a later Run.
- LISTEN: require one `Sn_SSR == SOCK_INIT` read, clear this socket's interrupt
  indication, then issue `LISTEN`; observe `SOCK_LISTEN` later.
- SEND: read `Sn_TX_FSR`, clear stale `SEND_OK|TIMEOUT`, write TX FIFO, write
  `Sn_TX_WRSR` high then low, then issue `SEND`. The Socket return is only the
  submitted chunk; the Channel saves it and initially returns zero.
- RECV: read `Sn_RX_RSR`, read RX FIFO, then issue `RECV`.
- DISCON: issue `DISCON`, then observe `SOCK_CLOSED` later.
- CLOSE: S2-06 owns the full sequence at Channel level; Socket exposes only
  bounded issue, poll, and completion primitives.
- `Sn_IR` is write-one-to-clear. `Sn_CR` is written once and its automatic
  clear is queried by one read on a later operation call. For OPEN, LISTEN,
  DISCON, and CLOSE this only advances the private command phase; a still later
  call must confirm the target `Sn_SSR` before clearing the pending command.

Each Socket owns `pending_command` plus `command_phase`. Issue enters
`WAIT_CR_CLEAR`; one call changes it to `WAIT_TARGET_STATE` without reading
`Sn_SSR`; subsequent calls read `Sn_SSR` once until OPEN reaches `SOCK_INIT`,
LISTEN reaches `SOCK_LISTEN` (or a later connected state), or DISCON/CLOSE
reaches `SOCK_CLOSED`. SEND and RECV end their S2-04 command-register pending
when `Sn_CR` clears. This does not treat SEND as `SEND_OK`; network-send
completion remains S2-05.

The prior code waited for `Sn_CR`, stable FSR/RSR values, TX drain, and
`SEND_OK`; close also delayed, opened UDP, performed a synchronous dummy send,
and changed common SIPR/SUBR. Those Run-reachable waits and the obsolete
`socket_send_to` path are removed. The official synchronous driver is used
only for register ordering and completion conditions.

The stable-size retry count below is a project bound, not a W5300 requirement:
`C2837X_W5300_STABLE_READ_ATTEMPTS = 3u`. Each attempt compares two complete
high-then-low snapshots, so TX_FSR or RX_RSR uses at most twelve 16-bit reads
and never returns an unconfirmed value.

| Run-reachable operation | Maximum work in one call |
| --- | --- |
| command issue | one `Sn_CR` write |
| pending WAIT_CR_CLEAR | one `Sn_CR` read |
| pending WAIT_TARGET_STATE | one `Sn_SSR` read |
| connection state | one `Sn_SSR` read; first ESTABLISHED may add one `Sn_IR` write |
| OPEN issue | nine writes: `Sn_IR`, `IR(n)`, MR, four TCP options, port, command |
| LISTEN issue | one status read plus three writes: `Sn_IR`, `IR(n)`, command |
| SEND issue | status + at most 12 size reads; one `Sn_IR` write, `ceil(chunk/2)` FIFO writes, two WRSR writes, one command write |
| RECV issue | status + at most 12 size reads; `ceil(chunk/2)` FIFO reads and one command write |
| CLOSE primitive | at most three writes; DISCON uses one command write |

Call chain: `C2837xBlock_Run` -> configured `IoDevice` operation -> private
`C2837xW5300Channel` -> its embedded `C2837xW5300Socket` -> W5300 HAL -> socket
register/FIFO access. Each embedded Socket owns its own `pending_command` and
`command_phase`; no global current socket, command, registry, or dynamic
allocation is used.
PlatformInit reset assert/settle delays are excluded from this Run budget and
remain unchanged.

## S2-05 SEND completion evidence and call budget

Each Channel has one pending segment: `send_state == SEND_PENDING` means its
FIFO data, WRSR, and one SEND command were submitted, while `pending_octets`
is the even positive chunk that has not yet been reported to the Core. The
Socket owns only command-register progression. The Channel owns SEND result
handling and returns that saved chunk exactly once, only after `SEND_OK` with
no `TIMEOUT` and a status of `SOCK_ESTABLISHED` or `SOCK_CLOSE_WAIT`.

Before each real segment submission, the Socket writes only
`Sn_IR_SENDOK | Sn_IR_TIMEOUT` to that Socket's write-one-to-clear `Sn_IR`.
During pending polling, changed data/count arguments are ignored. `TIMEOUT`
has priority over invalid status, which has priority over `SEND_OK`; failure
clears only Channel send bookkeeping and leaves an unconfirmed Socket command
for the close path. S2-06 clears this bookkeeping on close entry and never
reports dummy-send progress through the normal SEND path.

| SEND stage | Maximum work in one call |
| --- | --- |
| new segment preparation | fixed state checks plus at most 12 TX_FSR register reads |
| stale event clear | one current-Socket `Sn_IR` write |
| FIFO submit | `ceil(chunk/2)` FIFO word writes |
| WRSR | two register writes |
| SEND issue | one `Sn_CR` write |
| WAIT_CR_CLEAR | one `Sn_CR` read |
| WAIT_SEND_RESULT | one `Sn_SSR` read plus one `Sn_IR` read |
| SEND_OK completion | at most one current-Socket `Sn_IR` clear write |
| TIMEOUT failure | at most one current-Socket `Sn_IR` clear write |

There are no internal wait loops. `w5300_send_completion_test.c` covers stale
event clearing, delayed progress, repeated polling, changed arguments,
TIMEOUT/status priority, `4 + 4 + 2` segmented progress, conflicting commands,
Channel initialization isolation, and independent Socket 1/Socket 6 results.
The MATLAB companion also statically verifies that the Core's zero-send branch
returns before offset or completion-action updates.

Run with:

```matlab
run_all_tests('dsp_host')
```

## S2-06 close/Erratum evidence and call budget

The Channel state machine takes over any current-Socket command, then checks
`(Sn_MR & 0x0f) == TCP && Sn_TX_FSR != socket.tx_mem_size`. The direct path
issues CLOSE. The workaround path clears this Socket's events, writes UDP mode
and local port 5000, issues OPEN, confirms `SOCK_UDP`, waits for one TX octet,
then targets `0.0.0.1:5000`, writes one zero FIFO word with `Sn_TX_WRSR = 1`,
and issues SEND. Observed `SEND_OK`, hardware `TIMEOUT`, or both advance to the
same CLOSE path. DONE requires a later `SOCK_CLOSED` observation.

The whole transaction uses unsigned
`time_us() - close_start_us >= close_timeout_us`; no stage refreshes the start.
The sample uses `SAMPLE_TRANSFER_TIMEOUT_US` for both the Core transfer timeout
and Channel close timeout. A deadline faults only that Channel. Its API entries
then reject with no W5300 access until a successful PlatformInit generation is
observed.

| close stage | Maximum work in one call |
| --- | --- |
| first entry | one Timer2 read and private-state save; an idle Socket may add one `Sn_SSR` read for idempotence |
| existing command WAIT_CR | one `Sn_CR` read |
| Erratum check | one `Sn_MR` read plus at most 12 TX_FSR register reads |
| UDP OPEN issue | `Sn_IR`, current `IR(n)`, MR, port, and one `Sn_CR` write |
| UDP OPEN WAIT_CR | one `Sn_CR` read |
| UDP OPEN WAIT_STATE | one `Sn_SSR` read |
| dummy TX space | at most 12 TX_FSR register reads |
| dummy SEND issue | two DIPR, one DPORTR, one `Sn_IR`, one FIFO word, two WRSR, and one `Sn_CR` write |
| dummy WAIT_CR | one `Sn_CR` read |
| dummy WAIT_RESULT | one `Sn_SSR`, one `Sn_IR`, and at most one `Sn_IR` clear write |
| CLOSE issue | `Sn_IR`, current `IR(n)`, and one `Sn_CR` write |
| CLOSE WAIT_CR | one `Sn_CR` read |
| CLOSE WAIT_STATE | one `Sn_SSR` read |
| deadline check | one Timer2 read |

There are no internal waiting loops and no Run-reachable fixed delays.
`w5300_close_erratum_test.c` covers direct/workaround order, one-octet odd FIFO
handling, SEND_OK/TIMEOUT/both, every no-response wait at 99 us BUSY and 100 us
ERROR, Timer2 wrap, fault gates with zero register accesses, generation recovery,
network-register protection, idempotence, command takeover, and Socket isolation.
