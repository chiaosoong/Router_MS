# FPGA Verification Plan

## Goal

Build a board-side verification environment for the 3x3 NoC that:

- runs Python-generated packet cases from memory
- injects traffic into `MESH_3x3_TOP`
- checks packet delivery on FPGA
- reports progress and per-packet results over UART
- completes the full run even when some packets fail

## Key Rules

- Routing and allocation depend on `HEAD` flit information.
- Each input packet must produce a report entry.
- Success and failure packets are both reported.
- Packet latency is measured from head injection handshake to tail receive handshake.
- The first implementation stage supports up to 4 concurrent packets.

## Inputs

- `case.mem`: board execution input
- `case_meta.csv`: host-side analysis index
- `run_summary.json`: generation summary and reproducibility metadata

## Outputs

- UART text event stream
- `output/results.csv`
- `output/errors.csv`
- `output/summary.json`
- `output/uart_raw.log`
