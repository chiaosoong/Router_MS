from __future__ import annotations

import csv
import json
from dataclasses import asdict
from pathlib import Path
from typing import Iterable, Sequence

from case_model import MAX_PKT_FLITS, PacketRecord, RunSummary, ensure_parent

END_MARKER_FIELDS = [
    "FFFF",
    "FFFF",
    "FFFF",
    "FF",
    "FF",
    "F",
    "F",
    "FF",
    "FFFF",
] + ["00000000"] * MAX_PKT_FLITS

CASE_ROM_WORD_HEX_DIGITS = 80


def encode_packet(packet: PacketRecord) -> str:
    fields = [
        f"{packet.case_id:04X}",
        f"{packet.pkt_id:04X}",
        f"{packet.start_slot:04X}",
        f"{packet.src_rid:02X}",
        f"{packet.dst_rid:02X}",
        f"{packet.msg_class:X}",
        f"{packet.vc_id:X}",
        f"{packet.pkt_len:02X}",
        f"{packet.timeout_cycles:04X}",
    ]
    fields.extend(f"{flit:08X}" for flit in packet.padded_flits())
    return " ".join(fields)


def pack_packet_word(packet: PacketRecord) -> int:
    word = 0
    word |= (packet.case_id & 0xFFFF) << 304
    word |= (packet.pkt_id & 0xFFFF) << 288
    word |= (packet.start_slot & 0xFFFF) << 272
    word |= (packet.src_rid & 0xFF) << 264
    word |= (packet.dst_rid & 0xFF) << 256
    word |= (packet.msg_class & 0xF) << 252
    word |= (packet.vc_id & 0xF) << 248
    word |= (packet.pkt_len & 0xFF) << 240
    word |= (packet.timeout_cycles & 0xFFFF) << 224

    for idx, flit in enumerate(packet.padded_flits()):
        word |= (flit & 0xFFFF_FFFF) << (idx * 32)
    return word


def encode_packet_rom(packet: PacketRecord) -> str:
    return f"{pack_packet_word(packet):0{CASE_ROM_WORD_HEX_DIGITS}X}"


def encode_end_marker_rom() -> str:
    word = 0
    word |= 0xFFFF << 304
    word |= 0xFFFF << 288
    return f"{word:0{CASE_ROM_WORD_HEX_DIGITS}X}"


def write_case_mem(path: Path, packets: Sequence[PacketRecord]) -> None:
    ensure_parent(path)
    lines = [encode_packet(packet) for packet in packets]
    lines.append(" ".join(END_MARKER_FIELDS))
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_case_rom(path: Path, packets: Sequence[PacketRecord]) -> None:
    ensure_parent(path)
    lines = [encode_packet_rom(packet) for packet in packets]
    lines.append(encode_end_marker_rom())
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_case_meta(path: Path, packets: Sequence[PacketRecord]) -> None:
    ensure_parent(path)
    fieldnames = [
        "case_id",
        "pkt_id",
        "case_name",
        "start_slot",
        "src_rid",
        "dst_rid",
        "msg_class",
        "class_name",
        "vc_id",
        "pkt_len",
        "body_cnt",
        "timeout_cycles",
        "flits",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for packet in packets:
            writer.writerow(packet.to_meta_row())


def write_run_summary(path: Path, summary: RunSummary) -> None:
    ensure_parent(path)
    path.write_text(json.dumps(asdict(summary), indent=2), encoding="utf-8")
