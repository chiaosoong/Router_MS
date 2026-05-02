from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path
from typing import TextIO

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from export_results import write_case_results_csv, write_errors_csv, write_results_csv, write_summary_json
from report_parser import parse_line

try:
    import serial  # type: ignore
except ImportError:  # pragma: no cover
    serial = None


def render_progress(fields: dict) -> str:
    return (
        f"C{fields['case_done']}/{fields['case_total']} "
        f"P{fields['pkt_done']}/{fields['pkt_total']} "
        f"OK={fields['pass_count']} NG={fields['fail_count']}"
    )


def process_stream(handle: TextIO, raw_log: TextIO, output_dir: Path, start_time: str) -> None:
    results: list[dict] = []
    case_results: list[dict] = []
    result_index: dict[tuple[int, int], dict] = {}
    inject_cycles: dict[tuple[int, int], int] = {}
    state = {
        "case_total": 0,
        "pkt_total": 0,
        "pass_count": 0,
        "fail_count": 0,
    }

    while True:
        raw = handle.readline()
        if raw == "":
            break

        raw_log.write(raw)
        raw_log.flush()

        event = parse_line(raw)
        if event is None:
            continue

        if event.kind == "CASE_START":
            print(f"CASE START case={event.fields['case_id']} total_pkt={event.fields['case_pkt_total']}")
        elif event.kind == "PKT_INJ":
            key = (event.fields["case_id"], event.fields["pkt_id"])
            inject_cycles[key] = event.fields["inject_cycle"]
            if key in result_index:
                row = result_index[key]
                row["inject_cycle"] = event.fields["inject_cycle"]
                if row.get("latency") is not None:
                    row["finish_cycle"] = row["inject_cycle"] + row["latency"]
            print(
                f"PKT INJ  case={event.fields['case_id']} pkt={event.fields['pkt_id']} "
                f"src={event.fields['src_rid']} dst={event.fields['dst_rid']} "
                f"class={event.fields['msg_class']} vc={event.fields['vc_id']} "
                f"len={event.fields['pkt_len']} inj={event.fields['inject_cycle']}"
            )
        elif event.kind == "PROGRESS":
            state.update(event.fields)
            print(render_progress(event.fields), end="\r", flush=True)
        elif event.kind in {"PKT_DONE", "PKT_FAIL"}:
            key = (event.fields["case_id"], event.fields["pkt_id"])
            inject_cycle = inject_cycles.get(key)
            latency = event.fields["latency"]
            finish_cycle = None if (inject_cycle is None or latency is None) else (inject_cycle + latency)
            row = {
                **event.fields,
                "inject_cycle": inject_cycle,
                "finish_cycle": finish_cycle,
            }
            results.append(row)
            result_index[key] = row
            print()
            if event.kind == "PKT_DONE":
                print(
                    f"PKT PASS case={row['case_id']} pkt={row['pkt_id']} "
                    f"src={row['src_rid']} dst={row['dst_rid']} class={row['msg_class']} "
                    f"vc={row['vc_id']} len={row['pkt_len']} "
                    f"inj={row['inject_cycle']} lat={row['latency']} fin={row['finish_cycle']}"
                )
            else:
                print(
                    f"PKT FAIL case={row['case_id']} pkt={row['pkt_id']} "
                    f"src={row['src_rid']} dst={row['dst_rid']} class={row['msg_class']} "
                    f"vc={row['vc_id']} len={row['pkt_len']} err={row['error_code']} "
                    f"inj={row['inject_cycle']} lat={row['latency'] if row['latency'] is not None else '--'} "
                    f"fin={row['finish_cycle'] if row['finish_cycle'] is not None else '--'}"
                )
            if state["pkt_total"]:
                print(render_progress(state), end="\r", flush=True)
        elif event.kind == "CASE_DONE":
            avg_latency = 0.0
            if event.fields["case_pass"] != 0:
                avg_latency = event.fields["latency_sum"] / event.fields["case_pass"]
            case_results.append(
                {
                    "case_id": event.fields["case_id"],
                    "pkt_done": event.fields["case_done"],
                    "case_pass": event.fields["case_pass"],
                    "case_fail": event.fields["case_fail"],
                    "latency_sum": event.fields["latency_sum"],
                    "latency_min": event.fields["latency_min"],
                    "latency_max": event.fields["latency_max"],
                    "latency_avg": avg_latency,
                }
            )
            print()
            print(
                f"CASE DONE case={event.fields['case_id']} done={event.fields['case_done']} "
                f"pass={event.fields['case_pass']} fail={event.fields['case_fail']} "
                f"sum_lat={event.fields['latency_sum']} min_lat={event.fields['latency_min']} "
                f"max_lat={event.fields['latency_max']} avg_lat={avg_latency:.2f}"
            )
            if state["pkt_total"]:
                print(render_progress(state), end="\r", flush=True)
        elif event.kind == "ALL_DONE":
            observed_total = event.fields["pkt_total"]
            observed_pass = event.fields["pass_count"]
            observed_fail = event.fields["fail_count"]
            accuracy = 0.0 if observed_total == 0 else (observed_pass / observed_total)
            print()
            print(
                f"ALL DONE case={event.fields['case_total']} pkt={observed_total} "
                f"pass={observed_pass} fail={observed_fail} acc={accuracy * 100.0:.2f}%"
            )
            summary = {
                "total_cases": event.fields["case_total"],
                "total_packets": observed_total,
                "pass_packets": observed_pass,
                "fail_packets": observed_fail,
                "accuracy": accuracy,
                "start_time": start_time,
                "end_time": dt.datetime.now().isoformat(),
            }
            write_results_csv(output_dir / "results.csv", results)
            write_case_results_csv(output_dir / "case_results.csv", case_results)
            write_errors_csv(output_dir / "errors.csv", results)
            write_summary_json(output_dir / "summary.json", summary)
            return

    summary = {
        "total_cases": state["case_total"],
        "total_packets": len(results),
        "pass_packets": sum(1 for row in results if row.get("status") == "PASS"),
        "fail_packets": sum(1 for row in results if row.get("status") != "PASS"),
        "accuracy": 0.0,
        "start_time": start_time,
        "end_time": dt.datetime.now().isoformat(),
        "incomplete": True,
    }
    if summary["total_packets"]:
        summary["accuracy"] = summary["pass_packets"] / summary["total_packets"]
    write_results_csv(output_dir / "results.csv", results)
    write_case_results_csv(output_dir / "case_results.csv", case_results)
    write_errors_csv(output_dir / "errors.csv", results)
    write_summary_json(output_dir / "summary.json", summary)


def main() -> None:
    parser = argparse.ArgumentParser(description="Monitor FPGA UART verification output.")
    parser.add_argument("--port", help="Serial port, for example COM3.")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate.")
    parser.add_argument("--input-log", type=Path, help="Replay UART lines from a saved text log.")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=THIS_DIR.parent / "output",
        help="Directory for logs and parsed results.",
    )
    args = parser.parse_args()

    if args.port is None and args.input_log is None:
        raise SystemExit("Provide either --port for live UART or --input-log for replay.")

    if args.port is not None and args.input_log is not None:
        raise SystemExit("Use either --port or --input-log, not both.")

    if args.port is not None and serial is None:
        raise SystemExit("pyserial is required. Install it with: pip install pyserial")

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    raw_log = (output_dir / "uart_raw.log").open("a", encoding="utf-8")
    start_time = dt.datetime.now().isoformat()

    try:
        if args.input_log is not None:
            with args.input_log.open("r", encoding="utf-8") as replay_handle:
                process_stream(replay_handle, raw_log, output_dir, start_time)
        else:
            with serial.Serial(args.port, args.baud, timeout=1.0) as link:
                class SerialTextIO:
                    def __init__(self, inner_link) -> None:
                        self.inner_link = inner_link

                    def readline(self) -> str:
                        return self.inner_link.readline().decode("utf-8", errors="replace")

                process_stream(SerialTextIO(link), raw_log, output_dir, start_time)
    finally:
        raw_log.close()


if __name__ == "__main__":
    main()
