# UART Text Protocol

The FPGA verification platform emits one event per line.

## Event Types

### CASE_START

```text
CASE_START,<case_id>,<case_pkt_total>
```

### PKT_INJ

```text
PKT_INJ,<case_id>,<pkt_id>,<src>,<dst>,<class>,<vc>,<len>,<inject_cycle>
```

### PKT_DONE

```text
PKT_DONE,<case_id>,<pkt_id>,<src>,<dst>,<class>,<vc>,<len>,PASS,<latency>
```

### PKT_FAIL

```text
PKT_FAIL,<case_id>,<pkt_id>,<src>,<dst>,<class>,<vc>,<len>,FAIL,<error_code>,<latency_or_na>
```

### CASE_DONE

```text
CASE_DONE,<case_id>,<case_done>,<case_pass>,<case_fail>
```

### PROGRESS

```text
PROGRESS,<case_done>,<case_total>,<pkt_done>,<pkt_total>,<pass>,<fail>
```

### ALL_DONE

```text
ALL_DONE,<case_total>,<pkt_total>,<pass>,<fail>,<accuracy_permille>
```

## Host Behavior

- `PROGRESS` is used to refresh a single-line status view
- `PKT_DONE` and `PKT_FAIL` are printed as detailed records
- All UART lines are saved into `output/uart_raw.log`
