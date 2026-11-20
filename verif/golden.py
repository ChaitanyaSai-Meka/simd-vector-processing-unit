#!/usr/bin/env python3
"""
golden.py — Python golden reference model for the SIMD VPU.
Computes expected outputs for every ALU opcode and every benchmark.
Generates hex files for testbench use.

Owner: Rakshita (Role 4, Verification)
Usage:
    python3 golden.py --op VADD --lanes 4 --n 8      # single-op demo
    python3 golden.py --bench B1 --lanes 4 --n 64    # generate B1 hex files
    python3 golden.py --all                           # generate all bench hex files
"""

import argparse
import random
import os

# ── constants ────────────────────────────────────────────────────────────────
MASK32 = 0xFFFFFFFF
SIGN32 = 0x80000000


def to_signed32(x):
    x = x & MASK32
    return x - (1 << 32) if x >= SIGN32 else x


# ── ALU operations (all 32-bit wraparound) ───────────────────────────────────
def vadd(a, b):   return (a + b) & MASK32
def vsub(a, b):   return (a - b) & MASK32
def vand(a, b):   return (a & b) & MASK32
def vor(a, b):    return (a | b) & MASK32
def vxor(a, b):   return (a ^ b) & MASK32
def vslt(a, b):   return 1 if to_signed32(a) < to_signed32(b) else 0
def veq(a, b):    return 1 if a == b else 0
def vsll(a, b):   return (a << (b & 0x1F)) & MASK32
def vsrl(a, b):   return (a >> (b & 0x1F)) & MASK32
def vmul(a, b):   return (a * b) & MASK32  # stretch goal

ALU_OPS = {
    'VADD': vadd, 'VSUB': vsub, 'VAND': vand, 'VOR': vor, 'VXOR': vxor,
    'VSLT': vslt, 'VEQ': veq,  'VSLL': vsll, 'VSRL': vsrl, 'VMUL': vmul,
}


def apply_op_vector(op_fn, A, B):
    """Apply op_fn lane-wise to lists A and B."""
    return [op_fn(a, b) for a, b in zip(A, B)]


# ── edge-case vectors ─────────────────────────────────────────────────────────
EDGE_VALUES = [
    0x00000000,   # 0
    0x00000001,   # 1
    0xFFFFFFFF,   # -1 (signed)
    0x7FFFFFFF,   # INT32_MAX
    0x80000000,   # INT32_MIN
    0x00000002,   # small positive
    0xFFFFFFFE,   # -2 (signed)
]


def edge_case_pairs():
    """Return (a, b) pairs exercising every interesting edge case."""
    pairs = []
    for v in EDGE_VALUES:
        pairs.append((v, 0x00000001))
        pairs.append((0x00000001, v))
        pairs.append((v, v))
    # overflow wraparound
    pairs.append((0xFFFFFFFF, 0x00000001))  # VADD wraps to 0
    pairs.append((0x00000000, 0x00000001))  # VSUB wraps to 0xFFFFFFFF
    # shifts
    for shift in [0, 1, 15, 31]:
        pairs.append((0x00000001, shift))
        pairs.append((0x80000000, shift))
    return pairs


# ── hex file helpers ──────────────────────────────────────────────────────────
def write_hex(filename, data, lanes, dw=32):
    """Write list of 32-bit words as a Verilog $readmemh-compatible hex file.
    For vectors: data is a list of lane groups. Each group is written as one
    hex value with lane 0 in the least significant bits (rightmost digits).
    At one lane, both singleton groups and flat lists of words are accepted.
    """
    os.makedirs(os.path.dirname(filename) or '.', exist_ok=True)
    with open(filename, 'w') as f:
        if lanes == 1:
            for word in data:
                if isinstance(word, (list, tuple)):
                    word, = word
                f.write(f'{word & MASK32:08x}\n')
        else:
            # data is list of lane-groups: each group = list of LANES words
            for group in data:
                # Write as one wide hex value: lane[LANES-1] MSW ... lane[0] LSW
                wide = 0
                for i, lane_val in enumerate(group):
                    wide |= (lane_val & MASK32) << (i * dw)
                hex_digits = lanes * dw // 4
                f.write(f'{wide:0{hex_digits}x}\n')


def read_hex_flat(filename):
    """Read hex file (one 32-bit word per line) into a list of ints."""
    with open(filename) as f:
        return [int(line.strip(), 16) for line in f if line.strip()]


# ── benchmark data generation ─────────────────────────────────────────────────
def group_count(lanes, n):
    if lanes not in (1, 2, 4, 8):
        raise ValueError("lanes must be 1, 2, 4 or 8")
    if n <= 0 or n % lanes:
        raise ValueError("the element count must be positive and divisible by LANES")
    return n // lanes


def random_groups(rng, count, lanes):
    return [[rng.randint(0, MASK32) for _ in range(lanes)] for _ in range(count)]


def write_benchmark_images(name, lanes, n, outdir, a, second, expected):
    """Store A, the second region, and zero-filled C in one DMEM image."""
    blank = [[0] * lanes for _ in a]
    prefix = os.path.join(outdir, name.lower())
    write_hex(f'{prefix}_A_L{lanes}.hex', a, lanes)
    if second is not None:
        write_hex(f'{prefix}_B_L{lanes}.hex', second, lanes)
    write_hex(f'{prefix}_dmem_L{lanes}.hex', a + (blank if second is None else second) + blank, lanes)
    write_hex(f'{prefix}_C_expected_L{lanes}.hex', expected, lanes)
    print(f'{name} L={lanes} N={n}: wrote memory image and reference hex')


def gen_b1(lanes, n, seed=42, outdir='verif/data'):
    """C[i] = A[i] + B[i] with 32-bit wraparound."""
    count = group_count(lanes, n)
    rng = random.Random(seed)
    a = random_groups(rng, count, lanes)
    b = random_groups(rng, count, lanes)
    c = [apply_op_vector(vadd, av, bv) for av, bv in zip(a, b)]
    write_benchmark_images('B1', lanes, n, outdir, a, b, c)
    return a, b, c


def clamp_signed(a, threshold):
    """Return the smaller signed 32-bit operand as a 32-bit word."""
    if to_signed32(a) < to_signed32(threshold):
        return a & MASK32
    return threshold & MASK32


def gen_b2(lanes, n, threshold=0x00001000, seed=42, outdir='verif/data'):
    """C[i] = min_signed(A[i], T) with directed inputs around T."""
    count = group_count(lanes, n)
    rng = random.Random(seed + 1)
    a = random_groups(rng, count, lanes)
    boundary = (0x80000000, MASK32, threshold - 1, threshold, threshold + 1, 0x7fffffff)
    for index, value in enumerate(boundary[:n]):
        a[index // lanes][index % lanes] = value & MASK32
    c = [[clamp_signed(word, threshold) for word in group] for group in a]
    write_benchmark_images('B2', lanes, n, outdir, a, None, c)
    threshold_groups = [[threshold] * lanes for _ in range(count)]
    write_hex(os.path.join(outdir, f'b2_T_L{lanes}.hex'), threshold_groups, lanes)
    return a, c


def gen_b3(lanes, n, mask=0xFFFF0000, seed=42, outdir='verif/data'):
    """C[i] = (A[i] & M) ^ (B[i] << 2) with 32-bit wraparound."""
    count = group_count(lanes, n)
    rng = random.Random(seed + 2)
    a = random_groups(rng, count, lanes)
    b = random_groups(rng, count, lanes)
    c = [[((lhs & mask) ^ (rhs << 2)) & MASK32 for lhs, rhs in zip(av, bv)]
         for av, bv in zip(a, b)]
    write_benchmark_images('B3', lanes, n, outdir, a, b, c)
    return a, b, c


# ── self-test for golden model ────────────────────────────────────────────────
def self_test():
    """Quick sanity checks on the golden model itself."""
    print('=== golden.py self-test ===')
    errors = 0

    def chk(got, exp, label):
        nonlocal errors
        if got != exp:
            print(f'  FAIL {label}: got {got:#010x} expected {exp:#010x}')
            errors += 1

    # VADD
    chk(vadd(0xFFFFFFFF, 1), 0x00000000, 'VADD overflow')
    chk(vadd(1, 2), 3, 'VADD basic')

    # VSUB
    chk(vsub(0, 1), 0xFFFFFFFF, 'VSUB underflow')
    chk(vsub(5, 3), 2, 'VSUB basic')

    # VAND / VOR / VXOR
    chk(vand(0xFF00FF00, 0x0F0F0F0F), 0x0F000F00, 'VAND')
    chk(vor(0xF0F0F0F0, 0x0F0F0F0F), 0xFFFFFFFF, 'VOR')
    chk(vxor(0xAAAAAAAA, 0x55555555), 0xFFFFFFFF, 'VXOR')

    # VSLT (signed)
    chk(vslt(0x80000000, 0x00000001), 1, 'VSLT -inf < 1')
    chk(vslt(0x00000001, 0x80000000), 0, 'VSLT 1 < -inf')
    chk(vslt(5, 5), 0, 'VSLT equal')
    chk(vslt(0xFFFFFFFF, 0x00000001), 1, 'VSLT -1 < 1')

    # VEQ
    chk(veq(42, 42), 1, 'VEQ equal')
    chk(veq(42, 43), 0, 'VEQ not equal')

    # VSLL / VSRL
    chk(vsll(1, 0), 1, 'VSLL by 0')
    chk(vsll(1, 31), 0x80000000, 'VSLL by 31')
    chk(vsrl(0x80000000, 31), 1, 'VSRL by 31')
    chk(vsrl(0xFFFFFFFF, 0), 0xFFFFFFFF, 'VSRL by 0')

    # Edge: shift uses only low 5 bits of b
    chk(vsll(1, 32), 1, 'VSLL by 32 (mod 32 = 0)')

    # B2 reference exercises signed values and equality at the threshold.
    chk(clamp_signed(0x80000000, 4096), 0x80000000, 'B2 negative input')
    chk(clamp_signed(4095, 4096), 4095, 'B2 below threshold')
    chk(clamp_signed(4096, 4096), 4096, 'B2 at threshold')
    chk(clamp_signed(4097, 4096), 4096, 'B2 above threshold')

    if errors == 0:
        print('PASS  golden.py self-test: all checks passed')
    else:
        print(f'FAIL  golden.py self-test: {errors} errors')
    return errors == 0


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description='SIMD VPU golden reference model')
    parser.add_argument('--op', choices=list(ALU_OPS.keys()), help='Single ALU op demo')
    parser.add_argument('--bench', choices=['B1', 'B2', 'B3', 'all'], help='Benchmark to generate')
    parser.add_argument('--all', action='store_true', help='Generate all benchmarks at all lane counts')
    parser.add_argument('--lanes', type=int, default=4, choices=[1, 2, 4, 8])
    parser.add_argument('--n', type=int, default=64, help='Number of elements')
    parser.add_argument('--self-test', action='store_true', help='Run golden model self-test')
    parser.add_argument('--outdir', default='verif/data', help='Output directory for hex files')
    args = parser.parse_args()

    if args.self_test:
        ok = self_test()
        raise SystemExit(0 if ok else 1)

    generators = {'B1': gen_b1, 'B2': gen_b2, 'B3': gen_b3}
    if args.all or args.bench == 'all':
        lane_counts = (1, 2, 4, 8)
        benchmarks = generators.values()
    elif args.bench:
        lane_counts = (args.lanes,)
        benchmarks = (generators[args.bench],)
    else:
        lane_counts = ()
        benchmarks = ()

    try:
        for lanes in lane_counts:
            group_count(lanes, args.n)
        for lanes in lane_counts:
            for generate in benchmarks:
                generate(lanes, args.n, outdir=args.outdir)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if args.all or args.bench == 'all':
        return

    if args.op:
        op_fn = ALU_OPS[args.op]
        rng = random.Random(0)
        A = [rng.randint(0, MASK32) for _ in range(args.lanes)]
        B = [rng.randint(0, MASK32) for _ in range(args.lanes)]
        C = apply_op_vector(op_fn, A, B)
        print(f'{args.op} demo, LANES={args.lanes}:')
        for i in range(args.lanes):
            print(f'  lane {i}: {A[i]:08x} op {B[i]:08x} = {C[i]:08x}')


if __name__ == '__main__':
    main()
