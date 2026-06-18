# Protocol Test Vectors

## Overview

This document provides byte-level test vectors for verifying the C2837xBlock V2.3 protocol implementation.

All values are in hexadecimal. Wire format is little-endian.

## Frame Format

```
+--------+--------+------------------+
| type   | length | payload          |
| uint16 | uint16 | length wire bytes|
| 2 bytes| 2 bytes| variable         |
+--------+--------+------------------+
```

## Test Vectors

### 1. SIM_START (type=0x0001)

**Payload:**
- protocol_version = 0x0001
- config_hash = 0x12345678

**Wire bytes:**
```
01 00 06 00 01 00 78 56 34 12
```

Breakdown:
- `01 00` — type = 0x0001 (little-endian)
- `06 00` — length = 6 (little-endian)
- `01 00` — protocol_version = 0x0001
- `78 56 34 12` — config_hash = 0x12345678 (little-endian)

### 2. RESPONSE(0) — SIM_START success (type=0x0005)

**Payload:**
- error_code = 0x0000

**Wire bytes:**
```
05 00 02 00 00 00
```

Breakdown:
- `05 00` — type = 0x0005
- `02 00` — length = 2
- `00 00` — error_code = 0

### 3. INPUT_DATA (type=0x0002) — step_index=0, a=100, b=200, c=300

**Payload:**
- step_index = 0x00000000
- a = 0x0064 (100 decimal)
- b = 0x00C8 (200 decimal)
- c = 0x012C (300 decimal)

**Wire bytes:**
```
02 00 0A 00 00 00 00 00 64 00 C8 00 2C 01
```

Breakdown:
- `02 00` — type = 0x0002
- `0A 00` — length = 10
- `00 00 00 00` — step_index = 0
- `64 00` — a = 100
- `C8 00` — b = 200
- `2C 01` — c = 300

### 4. OUTPUT_DATA (type=0x0003) — step_index=0, sum=600

**Payload:**
- step_index = 0x00000000
- sum = 0x0258 (600 decimal)

**Wire bytes:**
```
03 00 06 00 00 00 00 00 58 02
```

Breakdown:
- `03 00` — type = 0x0003
- `06 00` — length = 6
- `00 00 00 00` — step_index = 0
- `58 02` — sum = 600

### 5. SIM_STOP (type=0x0004)

**Payload:** none (length = 0)

**Wire bytes:**
```
04 00 00 00
```

### 6. RESPONSE(2) — length error (type=0x0005)

**Wire bytes:**
```
05 00 02 00 02 00
```

### 7. RESPONSE(6) — protocol version mismatch (type=0x0005)

**Wire bytes:**
```
05 00 02 00 06 00
```

### 8. RESPONSE(7) — step_index mismatch (type=0x0005)

**Wire bytes:**
```
05 00 02 00 07 00
```

## W5300 FIFO Byte Mapping

When `c2837x_w5300_fifo_swap == 0` (default for direct EMIF mode):

| FIFO word | Byte 0 (low) | Byte 1 (high) |
|-----------|---------------|----------------|
| word[0]   | wire[0]       | wire[1]        |
| word[1]   | wire[2]       | wire[3]        |
| word[N]   | wire[2N]      | wire[2N+1]     |

Example: wire bytes `01 02 03 04` → FIFO word[0] = 0x0201, word[1] = 0x0403

When `c2837x_w5300_fifo_swap == 1` (byte-swapped bus):

| FIFO word | Byte 0 (low) | Byte 1 (high) |
|-----------|---------------|----------------|
| word[0]   | wire[1]       | wire[0]        |
| word[1]   | wire[3]       | wire[2]        |

Example: wire bytes `01 02 03 04` → FIFO word[0] = 0x0102, word[1] = 0x0304

## DSP Word Buffer Mapping

DSP `uint16_t` word buffer stores payload words in the same order as wire bytes:

- `word[0]` low byte = wire byte 0, high byte = wire byte 1
- `word[1]` low byte = wire byte 2, high byte = wire byte 3

This is consistent with little-endian wire format.
