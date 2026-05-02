from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path
from typing import List, Sequence, Tuple

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from case_encoder import write_case_mem, write_case_meta, write_case_rom, write_run_summary
from case_model import (
    DEFAULT_TIMEOUT,
    REQ,
    RESP,
    ROUTER_NUM,
    VC_PER_CLASS,
    VC_PER_PORT,
    PacketRecord,
    RunSummary,
    build_multi_flit_packet,
    build_single_flit_packet,
)

CASE_A_REPEAT = 500
CASE_B_REPEAT = 500
CASE_C_REPEAT = 1000
CASE_D_REPEAT = 1000


def choose_vc(rng: random.Random, msg_class: int) -> int:
    if msg_class == REQ:
        return rng.randrange(0, VC_PER_CLASS)
    return rng.randrange(VC_PER_CLASS, VC_PER_PORT)


def gen_random_pair(rng: random.Random) -> Tuple[int, int]:
    src = rng.randrange(0, ROUTER_NUM)
    dst = rng.randrange(0, ROUTER_NUM)
    while dst == src:
        dst = rng.randrange(0, ROUTER_NUM)
    return src, dst


def gen_case_a_packets(rng: random.Random, base_case_id: int, base_pkt_id: int) -> List[PacketRecord]:
    packets: List[PacketRecord] = []
    for idx in range(CASE_A_REPEAT):
        src, dst = gen_random_pair(rng)
        msg_class = REQ
        vc_id = choose_vc(rng, msg_class)
        packets.append(
            build_single_flit_packet(
                case_id=base_case_id + idx,
                pkt_id=base_pkt_id + idx,
                start_slot=0,
                src_rid=src,
                dst_rid=dst,
                msg_class=msg_class,
                vc_id=vc_id,
                case_name="CASE-A",
            )
        )
    return packets


def gen_case_b_packets(rng: random.Random, base_case_id: int, base_pkt_id: int) -> List[PacketRecord]:
    packets: List[PacketRecord] = []
    next_pkt_id = base_pkt_id
    for idx in range(CASE_B_REPEAT):
        case_id = base_case_id + idx
        src0, dst0 = gen_random_pair(rng)
        src1, dst1 = gen_random_pair(rng)
        while src1 == src0:
            src1, dst1 = gen_random_pair(rng)
        packets.extend(
            [
                build_single_flit_packet(
                    case_id=case_id,
                    pkt_id=next_pkt_id,
                    start_slot=0,
                    src_rid=src0,
                    dst_rid=dst0,
                    msg_class=REQ,
                    vc_id=choose_vc(rng, REQ),
                    case_name="CASE-B",
                ),
                build_single_flit_packet(
                    case_id=case_id,
                    pkt_id=next_pkt_id + 1,
                    start_slot=0,
                    src_rid=src1,
                    dst_rid=dst1,
                    msg_class=REQ,
                    vc_id=choose_vc(rng, REQ),
                    case_name="CASE-B",
                ),
            ]
        )
        next_pkt_id += 2
    return packets


def gen_case_c_packets(rng: random.Random, base_case_id: int, base_pkt_id: int) -> List[PacketRecord]:
    packets: List[PacketRecord] = []
    for idx in range(CASE_C_REPEAT):
        src, dst = gen_random_pair(rng)
        msg_class = rng.choice([REQ, RESP])
        body_cnt = rng.randrange(0, 6)
        packets.append(
            build_multi_flit_packet(
                case_id=base_case_id + idx,
                pkt_id=base_pkt_id + idx,
                start_slot=0,
                src_rid=src,
                dst_rid=dst,
                msg_class=msg_class,
                vc_id=choose_vc(rng, msg_class),
                body_cnt=body_cnt,
                case_name="CASE-C",
            )
        )
    return packets


def signatures_are_unique(packets: Sequence[PacketRecord]) -> bool:
    signatures = [packet.signature for packet in packets]
    return len(signatures) == len(set(signatures))


def gen_case_d_packets(rng: random.Random, base_case_id: int, base_pkt_id: int) -> List[PacketRecord]:
    packets: List[PacketRecord] = []
    next_pkt_id = base_pkt_id
    for idx in range(CASE_D_REPEAT):
        case_id = base_case_id + idx
        while True:
            src0, dst0 = gen_random_pair(rng)
            src1, dst1 = gen_random_pair(rng)
            src2, dst2 = gen_random_pair(rng)
            if len({src0, src1, src2}) != 3:
                continue
            body0 = rng.randrange(0, 6)
            body1 = rng.randrange(0, 6)
            body2 = rng.randrange(0, 6)
            cls0 = rng.choice([REQ, RESP])
            cls1 = rng.choice([REQ, RESP])
            cls2 = rng.choice([REQ, RESP])
            case_packets = [
                build_multi_flit_packet(
                    case_id=case_id,
                    pkt_id=next_pkt_id,
                    start_slot=0,
                    src_rid=src0,
                    dst_rid=dst0,
                    msg_class=cls0,
                    vc_id=choose_vc(rng, cls0),
                    body_cnt=body0,
                    case_name="CASE-D",
                ),
                build_multi_flit_packet(
                    case_id=case_id,
                    pkt_id=next_pkt_id + 1,
                    start_slot=0,
                    src_rid=src1,
                    dst_rid=dst1,
                    msg_class=cls1,
                    vc_id=choose_vc(rng, cls1),
                    body_cnt=body1,
                    case_name="CASE-D",
                ),
                build_multi_flit_packet(
                    case_id=case_id,
                    pkt_id=next_pkt_id + 2,
                    start_slot=0,
                    src_rid=src2,
                    dst_rid=dst2,
                    msg_class=cls2,
                    vc_id=choose_vc(rng, cls2),
                    body_cnt=body2,
                    case_name="CASE-D",
                ),
            ]
            if signatures_are_unique(case_packets):
                packets.extend(case_packets)
                next_pkt_id += 3
                break
    return packets


def build_packet_set(seed: int) -> tuple[List[PacketRecord], RunSummary]:
    rng = random.Random(seed)
    packets: List[PacketRecord] = []

    case_a_packets = gen_case_a_packets(rng, base_case_id=0, base_pkt_id=0x0000)
    packets.extend(case_a_packets)

    case_b_packets = gen_case_b_packets(rng, base_case_id=CASE_A_REPEAT, base_pkt_id=0x0100)
    packets.extend(case_b_packets)

    case_c_packets = gen_case_c_packets(rng, base_case_id=CASE_A_REPEAT + CASE_B_REPEAT, base_pkt_id=0x0200)
    packets.extend(case_c_packets)

    case_d_packets = gen_case_d_packets(
        rng,
        base_case_id=CASE_A_REPEAT + CASE_B_REPEAT + CASE_C_REPEAT,
        base_pkt_id=0x0300,
    )
    packets.extend(case_d_packets)

    packets.sort(key=lambda packet: (packet.case_id, packet.start_slot, packet.pkt_id))
    summary = RunSummary(
        seed=seed,
        total_cases=CASE_A_REPEAT + CASE_B_REPEAT + CASE_C_REPEAT + CASE_D_REPEAT,
        total_packets=len(packets),
        case_a_count=len(case_a_packets),
        case_b_count=len(case_b_packets),
        case_c_count=len(case_c_packets),
        case_d_count=len(case_d_packets),
        output_dir="",
    )
    return packets, summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate FPGA verification packet cases.")
    parser.add_argument("--seed", type=int, default=12345, help="Deterministic random seed.")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=THIS_DIR.parent / "mem",
        help="Directory that receives case.mem/case_rom.memh and metadata files.",
    )
    args = parser.parse_args()

    packets, summary = build_packet_set(args.seed)
    output_dir = args.output_dir.resolve()
    summary = RunSummary(**{**summary.__dict__, "output_dir": str(output_dir)})

    write_case_mem(output_dir / "case.mem", packets)
    write_case_rom(output_dir / "case_rom.memh", packets)
    write_case_meta(output_dir / "case_meta.csv", packets)
    write_run_summary(output_dir / "run_summary.json", summary)

    print(f"Generated {summary.total_packets} packets across {summary.total_cases} cases.")
    print(f"Output directory: {output_dir}")


if __name__ == "__main__":
    main()
