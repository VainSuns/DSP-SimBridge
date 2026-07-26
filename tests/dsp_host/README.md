# DSP host tests

S2-01 covers the public Core API and instance state. S2-02 adds host-stub
coverage for shared platform initialization, Timer2, W5300 memory/network
readback, failure short-circuiting, and reset timing source evidence. S2-03
adds the generic IoDevice boundary, Fake IoDevice Core linking, and independent
W5300 channel coverage. S2-03A adds the internal const Config and algorithm
adapter contract, static two-instance binding, routing/isolation, and invalid
configuration boundary coverage. S2-04 adds bounded W5300 HAL command/size
access and per-channel Socket command progression.

## S2-04 W5300 evidence and call budget

Official references: WIZnet **W5300 Datasheet v1.3.4**, **W5300 Errata Sheet
v1.2.3**, and the official **ioLibrary_Driver W5300** implementation. The
datasheet sequences used here are:

- OPEN: clear this socket's pending interrupt indication, write `Sn_MR`, TCP
  options, `Sn_PORTR`, then issue `OPEN`; observe `SOCK_INIT` on a later Run.
- LISTEN: require one `Sn_SSR == SOCK_INIT` read, clear this socket's interrupt
  indication, then issue `LISTEN`; observe `SOCK_LISTEN` later.
- SEND: read `Sn_TX_FSR`, write TX FIFO, write `Sn_TX_WRSR` high then low, then
  issue `SEND`. S2-04 does not wait for or report `SEND_OK` completion.
- RECV: read `Sn_RX_RSR`, read RX FIFO, then issue `RECV`.
- DISCON: issue `DISCON`, then observe `SOCK_CLOSED` later.
- CLOSE: clear `Sn_IR`, clear only this socket's common `IR(n)` bit, issue
  `CLOSE`, then observe `SOCK_CLOSED` later. The Erratum 1 dummy-send sequence
  is intentionally deferred to S2-06.
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
| SEND issue | status + interrupt + at most 12 size reads; `ceil(chunk/2)` FIFO writes, two WRSR writes, one command write |
| RECV issue | status + at most 12 size reads; `ceil(chunk/2)` FIFO reads and one command write |
| CLOSE issue | one status read and at most three writes; DISCON uses one status read and one command write |

Call chain: `C2837xBlock_Run` -> configured `IoDevice` operation -> private
`C2837xW5300Channel` -> its embedded `C2837xW5300Socket` -> W5300 HAL -> socket
register/FIFO access. Each embedded Socket owns its own `pending_command` and
`command_phase`; no global current socket, command, registry, or dynamic
allocation is used.
PlatformInit reset assert/settle delays are excluded from this Run budget and
remain unchanged.

Run with:

```matlab
run_all_tests('dsp_host')
```
