from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Iterable, Sequence


RESULT_FIELDS = [
    "case_id",
    "pkt_id",
    "src_rid",
    "dst_rid",
    "msg_class",
    "vc_id",
    "pkt_len",
    "inject_cycle",
    "finish_cycle",
    "latency",
    "status",
    "error_code",
]

CASE_RESULT_FIELDS = [
    "case_id",
    "pkt_done",
    "case_pass",
    "case_fail",
    "latency_sum",
    "latency_min",
    "latency_max",
    "latency_avg",
]


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_results_csv(path: Path, rows: Sequence[dict]) -> None:
    ensure_dir(path.parent)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=RESULT_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_errors_csv(path: Path, rows: Sequence[dict]) -> None:
    ensure_dir(path.parent)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=RESULT_FIELDS)
        writer.writeheader()
        for row in rows:
            if row.get("status") != "PASS":
                writer.writerow(row)


def write_case_results_csv(path: Path, rows: Sequence[dict]) -> None:
    ensure_dir(path.parent)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CASE_RESULT_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_summary_json(path: Path, summary: dict) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
