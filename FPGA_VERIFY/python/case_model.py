from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List

MESH_X = 3
MESH_Y = 3
ROUTER_NUM = MESH_X * MESH_Y
MAX_PKT_FLITS = 7
DEFAULT_TIMEOUT = 300

REQ = 0
RESP = 1

FLIT_HEAD = 0b00
FLIT_BODY = 0b01
FLIT_TAIL = 0b10
FLIT_HEADTAIL = 0b11

VC_PER_CLASS = 2
VC_PER_PORT = 4


def rid_x(rid: int) -> int:
    return rid % MESH_X


def rid_y(rid: int) -> int:
    return rid // MESH_X


def make_flit(src_rid: int, dst_rid: int, flit_type: int, pkt_len: int, seq: int, msg_class: int) -> int:
    value = 0
    value |= (rid_x(dst_rid) & 0xF) << 28
    value |= (rid_y(dst_rid) & 0xF) << 24
    value |= (rid_x(src_rid) & 0xF) << 20
    value |= (rid_y(src_rid) & 0xF) << 16
    value |= (flit_type & 0x3) << 14
    value |= (pkt_len & 0xF) << 10
    value |= (seq & 0x1F) << 5
    value |= msg_class & 0x7
    return value


@dataclass(frozen=True)
class PacketRecord:
    case_id: int
    pkt_id: int
    start_slot: int
    src_rid: int
    dst_rid: int
    msg_class: int
    vc_id: int
    pkt_len: int
    timeout_cycles: int
    flits: List[int]
    case_name: str

    @property
    def body_cnt(self) -> int:
        return max(self.pkt_len - 2, 0)

    @property
    def class_name(self) -> str:
        return "RESP" if self.msg_class == RESP else "REQ"

    @property
    def signature(self) -> tuple[int, int, int, int]:
        return (self.src_rid, self.dst_rid, self.msg_class, self.pkt_len)

    def padded_flits(self) -> List[int]:
        return self.flits + [0] * (MAX_PKT_FLITS - len(self.flits))

    def to_meta_row(self) -> dict:
        row = asdict(self)
        row["class_name"] = self.class_name
        row["body_cnt"] = self.body_cnt
        row["flits"] = " ".join(f"{flit:08X}" for flit in self.flits)
        return row


@dataclass(frozen=True)
class RunSummary:
    seed: int
    total_cases: int
    total_packets: int
    case_a_count: int
    case_b_count: int
    case_c_count: int
    case_d_count: int
    output_dir: str


def build_single_flit_packet(
    *,
    case_id: int,
    pkt_id: int,
    start_slot: int,
    src_rid: int,
    dst_rid: int,
    msg_class: int,
    vc_id: int,
    case_name: str,
    timeout_cycles: int = DEFAULT_TIMEOUT,
) -> PacketRecord:
    flit = make_flit(src_rid, dst_rid, FLIT_HEADTAIL, 1, 0, msg_class)
    return PacketRecord(
        case_id=case_id,
        pkt_id=pkt_id,
        start_slot=start_slot,
        src_rid=src_rid,
        dst_rid=dst_rid,
        msg_class=msg_class,
        vc_id=vc_id,
        pkt_len=1,
        timeout_cycles=timeout_cycles,
        flits=[flit],
        case_name=case_name,
    )


def build_multi_flit_packet(
    *,
    case_id: int,
    pkt_id: int,
    start_slot: int,
    src_rid: int,
    dst_rid: int,
    msg_class: int,
    vc_id: int,
    body_cnt: int,
    case_name: str,
    timeout_cycles: int = DEFAULT_TIMEOUT,
) -> PacketRecord:
    pkt_len = body_cnt + 2
    flits: List[int] = [make_flit(src_rid, dst_rid, FLIT_HEAD, pkt_len, 0, msg_class)]
    for beat in range(body_cnt):
        flits.append(make_flit(src_rid, dst_rid, FLIT_BODY, pkt_len, beat + 1, msg_class))
    flits.append(make_flit(src_rid, dst_rid, FLIT_TAIL, pkt_len, pkt_len - 1, msg_class))
    return PacketRecord(
        case_id=case_id,
        pkt_id=pkt_id,
        start_slot=start_slot,
        src_rid=src_rid,
        dst_rid=dst_rid,
        msg_class=msg_class,
        vc_id=vc_id,
        pkt_len=pkt_len,
        timeout_cycles=timeout_cycles,
        flits=flits,
        case_name=case_name,
    )


def class_to_name(value: int) -> str:
    return "RESP" if value == RESP else "REQ"


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
