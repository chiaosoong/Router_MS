from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class ReportEvent:
    kind: str
    fields: dict
    raw: str


def _as_int(token: str) -> int:
    return int(token, 16)


def _as_msg_class(token: str) -> str:
    value = _as_int(token)
    if value == 0:
        return "REQ"
    if value == 1:
        return "RESP"
    return f"CLS_{value:X}"


def _as_error(token: str) -> str:
    if token == "PASS":
        return "PASS"

    value = _as_int(token)
    error_names = {
        0: "PASS",
        1: "TIMEOUT",
        2: "DST_MISMATCH",
        3: "SRC_MISMATCH",
        4: "TYPE_MISMATCH",
        5: "LEN_MISMATCH",
        6: "CLASS_MISMATCH",
        7: "SEQ_MISMATCH",
        8: "UNEXPECTED_FLIT",
        9: "DUPLICATE_TAIL",
        10: "INTERNAL_OVERFLOW",
    }
    return error_names.get(value, f"ERR_{value:X}")


def parse_line(line: str) -> Optional[ReportEvent]:
    text = line.strip()
    if not text:
        return None

    parts = text.split(",")
    kind = parts[0]
    fields: dict = {}

    if kind == "CASE_START":
        fields = {"case_id": _as_int(parts[1]), "case_pkt_total": _as_int(parts[2])}
    elif kind == "PKT_INJ":
        fields = {
            "case_id": _as_int(parts[1]),
            "pkt_id": _as_int(parts[2]),
            "src_rid": _as_int(parts[3]),
            "dst_rid": _as_int(parts[4]),
            "msg_class": _as_msg_class(parts[5]),
            "vc_id": _as_int(parts[6]),
            "pkt_len": _as_int(parts[7]),
            "inject_cycle": _as_int(parts[8]),
        }
    elif kind == "PKT_DONE":
        fields = {
            "case_id": _as_int(parts[1]),
            "pkt_id": _as_int(parts[2]),
            "src_rid": _as_int(parts[3]),
            "dst_rid": _as_int(parts[4]),
            "msg_class": _as_msg_class(parts[5]),
            "vc_id": _as_int(parts[6]),
            "pkt_len": _as_int(parts[7]),
            "status": parts[8],
            "latency": _as_int(parts[9]),
            "error_code": "PASS",
        }
    elif kind == "PKT_FAIL":
        latency = None if parts[10] == "--" else _as_int(parts[10])
        fields = {
            "case_id": _as_int(parts[1]),
            "pkt_id": _as_int(parts[2]),
            "src_rid": _as_int(parts[3]),
            "dst_rid": _as_int(parts[4]),
            "msg_class": _as_msg_class(parts[5]),
            "vc_id": _as_int(parts[6]),
            "pkt_len": _as_int(parts[7]),
            "status": parts[8],
            "error_code": _as_error(parts[9]),
            "latency": latency,
        }
    elif kind == "CASE_DONE":
        fields = {
            "case_id": _as_int(parts[1]),
            "case_done": _as_int(parts[2]),
            "case_pass": _as_int(parts[3]),
            "case_fail": _as_int(parts[4]),
            "latency_sum": _as_int(parts[5]) if len(parts) > 5 else 0,
            "latency_min": _as_int(parts[6]) if len(parts) > 6 else 0,
            "latency_max": _as_int(parts[7]) if len(parts) > 7 else 0,
        }
    elif kind == "PROGRESS":
        fields = {
            "case_done": _as_int(parts[1]),
            "case_total": _as_int(parts[2]),
            "pkt_done": _as_int(parts[3]),
            "pkt_total": _as_int(parts[4]),
            "pass_count": _as_int(parts[5]),
            "fail_count": _as_int(parts[6]),
        }
    elif kind == "ALL_DONE":
        fields = {
            "case_total": _as_int(parts[1]),
            "pkt_total": _as_int(parts[2]),
            "pass_count": _as_int(parts[3]),
            "fail_count": _as_int(parts[4]),
            "accuracy_permille": _as_int(parts[5]),
        }
    else:
        fields = {"tokens": parts[1:]}

    return ReportEvent(kind=kind, fields=fields, raw=text)
