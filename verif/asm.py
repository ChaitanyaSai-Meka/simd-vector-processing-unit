#!/usr/bin/env python3
"""Assemble the base SIMD VPU ISA into 32-bit instruction memory hex."""

import argparse
from pathlib import Path
import re


VECTOR_OPS = {
    "VADD": 0x00,
    "VSUB": 0x01,
    "VAND": 0x02,
    "VOR": 0x03,
    "VXOR": 0x04,
    "VSLT": 0x05,
    "VEQ": 0x06,
    "VSLL": 0x07,
    "VSRL": 0x08,
}
OPCODES = {
    **VECTOR_OPS,
    "VLD": 0x10,
    "VST": 0x11,
    "SADDI": 0x20,
    "SLI": 0x21,
    "BNE": 0x22,
    "HALT": 0x3F,
}
LABEL = re.compile(r"[A-Z_][A-Z0-9_]*")
MEMORY_OPERAND = re.compile(r"([^()]+)\(\s*([^()]+)\)")


def register(token, kind):
    if not re.fullmatch(kind + r"[0-7]", token):
        raise ValueError(f"expected a {kind.lower()}0..{kind.lower()}7 register, got {token!r}")
    return int(token[1])


def immediate(token, constants):
    if token in constants:
        return constants[token]
    try:
        base = 10 if re.fullmatch(r"[+-]?[0-9]+", token) else 0
        return int(token, base)
    except ValueError:
        raise ValueError(f"expected an integer or built-in constant, got {token!r}") from None


def encode(mnemonic, operands, pc, labels, constants):
    opcode_name, suffix, operand_form = mnemonic.partition(".")
    if opcode_name not in OPCODES:
        raise ValueError(f"unknown instruction {mnemonic!r}")
    vector_alu = opcode_name in VECTOR_OPS
    scalar_form = bool(suffix)
    if scalar_form and (not vector_alu or operand_form != "S"):
        raise ValueError("the .S suffix is valid on vector ALU instructions only")

    if vector_alu or opcode_name in ("SADDI", "BNE"):
        operand_count = 3
    elif opcode_name == "HALT":
        operand_count = 0
    else:
        operand_count = 2
    if len(operands) != operand_count:
        raise ValueError(f"{mnemonic} requires {operand_count} operand(s)")

    field_25_23 = field_22_20 = field_19_17 = imm = 0
    if vector_alu:
        vd, vs1, src2 = operands
        field_25_23 = register(vd, "V")
        field_22_20 = register(vs1, "V")
        field_19_17 = register(src2, "R" if scalar_form else "V")
    elif opcode_name in ("VLD", "VST"):
        vector_reg, address = operands
        match = MEMORY_OPERAND.fullmatch(address)
        if not match:
            raise ValueError(f"expected offset(rs1), got {address!r}")
        offset, base = match.groups()
        field_25_23 = register(vector_reg, "V")
        field_22_20 = register(base.strip(), "R")
        imm = immediate(offset.strip(), constants)
    elif opcode_name == "SADDI":
        rd, rs1, value = operands
        field_25_23 = register(rd, "R")
        field_22_20 = register(rs1, "R")
        imm = immediate(value, constants)
    elif opcode_name == "SLI":
        rd, value = operands
        field_25_23 = register(rd, "R")
        imm = immediate(value, constants)
    elif opcode_name == "BNE":
        rs1, rs2, target = operands
        field_22_20 = register(rs1, "R")
        field_19_17 = register(rs2, "R")
        if target in labels:
            imm = labels[target] - pc
        elif LABEL.fullmatch(target) and target not in constants:
            raise ValueError(f"undefined branch label {target!r}")
        else:
            imm = immediate(target, constants)

    if not -32768 <= imm <= 32767:
        raise ValueError(f"value {imm} does not fit a signed 16-bit field")
    return (
        (OPCODES[opcode_name] << 26)
        | (field_25_23 << 23)
        | (field_22_20 << 20)
        | (field_19_17 << 17)
        | (int(scalar_form) << 16)
        | (imm & 0xFFFF)
    )


def assemble(source, lanes=4, n=64):
    """Return one instruction word per source instruction."""
    if lanes not in (1, 2, 4, 8):
        raise ValueError("lanes must be 1, 2, 4 or 8")
    if n <= 0 or n % lanes:
        raise ValueError("the element count must be positive and divisible by LANES")
    groups = n // lanes
    constants = {"LANES": lanes, "N": n, "GROUPS": groups,
                 "B_BASE": groups, "C_BASE": 2 * groups}

    labels = {}
    statements = []
    for line_number, line in enumerate(source.splitlines(), 1):
        statement = re.split(r"[#;]", line, maxsplit=1)[0].strip().upper()
        if ":" in statement:
            name, statement = (part.strip() for part in statement.split(":", 1))
            if not LABEL.fullmatch(name):
                raise ValueError(f"line {line_number}: invalid label {name!r}")
            if name in constants or name in labels:
                raise ValueError(f"line {line_number}: duplicate or reserved label {name!r}")
            labels[name] = len(statements)
        if statement:
            statements.append((line_number, statement))

    if not statements:
        raise ValueError("no instructions")

    words = []
    for pc, (line_number, statement) in enumerate(statements):
        mnemonic, *operand_text = statement.split(maxsplit=1)
        operands = [part.strip() for part in operand_text[0].split(",")] if operand_text else []
        try:
            words.append(encode(mnemonic, operands, pc, labels, constants))
        except ValueError as exc:
            raise ValueError(f"line {line_number}: {exc}") from None
    return words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="input assembly file")
    parser.add_argument("-o", "--output", type=Path, help="output hex file (default: source with .hex suffix)")
    parser.add_argument("--lanes", type=int, choices=(1, 2, 4, 8), default=4)
    parser.add_argument("--n", type=int, default=64, help="element count for benchmark constants")
    args = parser.parse_args()

    output = args.output or args.source.with_suffix(".hex")
    if output.resolve() == args.source.resolve():
        parser.error("the output must differ from the source file")
    try:
        words = assemble(args.source.read_text(encoding="utf-8"), args.lanes, args.n)
    except (OSError, ValueError) as exc:
        parser.error(f"{args.source}: {exc}")
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    except OSError as exc:
        parser.error(f"{output}: {exc}")


if __name__ == "__main__":
    main()
