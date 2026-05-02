# case.mem Format

Each line encodes exactly one packet record.

```text
case_id pkt_id start_slot src_rid dst_rid msg_class vc_id pkt_len timeout_cycles flit0 flit1 flit2 flit3 flit4 flit5 flit6
```

## Field Widths

- `case_id`: 4 hex digits
- `pkt_id`: 4 hex digits
- `start_slot`: 4 hex digits
- `src_rid`: 2 hex digits
- `dst_rid`: 2 hex digits
- `msg_class`: 1 hex digit
- `vc_id`: 1 hex digit
- `pkt_len`: 2 hex digits
- `timeout_cycles`: 4 hex digits
- `flit0..flit6`: 8 hex digits each

## Notes

- First stage maximum packet length: 7 flits
- Unused flit slots are padded with `00000000`
- Records are sorted by `case_id`, `start_slot`, `pkt_id`
- Packets sharing the same `start_slot` are launched concurrently
- The file terminates with:

```text
FFFF FFFF FFFF FF FF F F FF FFFF 00000000 00000000 00000000 00000000 00000000 00000000 00000000
```

# case_rom.memh Format

`case_rom.memh` is the board-oriented ROM image for `$readmemh`.

- one packet record per line
- one 320-bit word per record
- one line = 80 hex digits
- same payload information as `case.mem`
- same terminal end marker semantics

## Packed Layout

The packed bit layout matches `fpga_verify_pkg::CASE_MEM_LINE_W` and `unpack_pkt_desc()`:

```text
[319:304] case_id
[303:288] pkt_id
[287:272] start_slot
[271:264] src_rid
[263:256] dst_rid
[255:252] msg_class
[251:248] vc_id
[247:240] pkt_len
[239:224] timeout_cycles
[223:192] flit6
[191:160] flit5
[159:128] flit4
[127:096] flit3
[095:064] flit2
[063:032] flit1
[031:000] flit0
```

## End Marker

The final line marks end-of-table by setting `case_id` and `pkt_id` to `FFFF` and all remaining bits to `0`.
