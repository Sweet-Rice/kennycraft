"""Generate the RV32I UART hello-world program used by this core."""

from pathlib import Path


MESSAGE = "Hello, world!\r\n"

RESET_VECTOR = 0x8000_0000
IMEM_WORDS = 4096
OUTPUT_PATH = Path(__file__).with_name("program.mem")


def _check_reg(reg):
    if not isinstance(reg, int) or not 0 <= reg < 32:
        raise ValueError(f"register must be an integer from 0 through 31, got {reg!r}")


def _check_signed(value, bits, name):
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    if not isinstance(value, int) or not minimum <= value <= maximum:
        raise ValueError(f"{name} must fit in a signed {bits}-bit field, got {value!r}")


def _encode_u(rd, imm20, opcode):
    _check_reg(rd)
    if not isinstance(imm20, int) or not 0 <= imm20 <= 0xF_FFFF:
        raise ValueError(f"U-type immediate must be an unsigned 20-bit value, got {imm20!r}")
    return (imm20 << 12) | (rd << 7) | opcode


def _encode_i(rd, rs1, imm, funct3, opcode):
    _check_reg(rd)
    _check_reg(rs1)
    _check_signed(imm, 12, "I-type immediate")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def _encode_s(rs1, rs2, imm, funct3):
    _check_reg(rs1)
    _check_reg(rs2)
    _check_signed(imm, 12, "S-type immediate")
    encoded = imm & 0xFFF
    return (
        ((encoded >> 5) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | ((encoded & 0x1F) << 7)
        | 0b0100011
    )


def _encode_b(rs1, rs2, offset, funct3):
    _check_reg(rs1)
    _check_reg(rs2)
    _check_signed(offset, 13, "B-type offset")
    if offset & 1:
        raise ValueError(f"B-type offset must be 2-byte aligned, got {offset}")

    encoded = offset & 0x1FFF
    return (
        (((encoded >> 12) & 0x1) << 31)
        | (((encoded >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((encoded >> 1) & 0xF) << 8)
        | (((encoded >> 11) & 0x1) << 7)
        | 0b1100011
    )


def _encode_j(rd, offset):
    _check_reg(rd)
    _check_signed(offset, 21, "J-type offset")
    if offset & 1:
        raise ValueError(f"J-type offset must be 2-byte aligned, got {offset}")

    encoded = offset & 0x1F_FFFF
    return (
        (((encoded >> 20) & 0x1) << 31)
        | (((encoded >> 1) & 0x3FF) << 21)
        | (((encoded >> 11) & 0x1) << 20)
        | (((encoded >> 12) & 0xFF) << 12)
        | (rd << 7)
        | 0b1101111
    )


def lui(rd, imm20):
    return _encode_u(rd, imm20, 0b0110111)


def addi(rd, rs1, imm):
    return _encode_i(rd, rs1, imm, 0b000, 0b0010011)


def lw(rd, offset, rs1):
    return _encode_i(rd, rs1, offset, 0b010, 0b0000011)


def sb(rs2, offset, rs1):
    return _encode_s(rs1, rs2, offset, 0b000)


def bne(rs1, rs2, offset):
    return _encode_b(rs1, rs2, offset, 0b001)


def beq(rs1, rs2, offset):
    return _encode_b(rs1, rs2, offset, 0b000)


def jal(rd, offset):
    return _encode_j(rd, offset)


def self_test():
    """Check every reference encoding before touching the output file."""
    assert lui(6, 0x10000) == 0x10000337
    assert lui(4, 0x10000) == 0x10000237
    assert addi(7, 0, 72) == 0x04800393
    assert addi(1, 0, 5) == 0x00500093
    assert lw(3, 0, 1) == 0x0000A183
    assert sb(7, 0, 6) == 0x00730023
    assert sb(5, 0, 4) == 0x00520023
    assert bne(1, 2, 8) == 0x00209463
    assert beq(1, 2, 12) == 0x00208663
    assert jal(0, 0) == 0x0000006F


def assemble(message):
    """Return (address, encoded word, mnemonic) tuples for the program."""
    program = []

    def emit(word, mnemonic):
        address = RESET_VECTOR + 4 * len(program)
        program.append((address, word, mnemonic))

    emit(lui(6, 0x10000), "lui  x6, 0x10000")
    start_address = RESET_VECTOR + 4

    for index, char in enumerate(message):
        value = ord(char)
        if value > 0xFF:
            raise ValueError(
                f"MESSAGE character {index} ({char!r}) is not an 8-bit UART byte"
            )

        emit(addi(7, 0, value), f"addi x7, x0, {value:<3}  # {ascii(char)}")

        poll_address = RESET_VECTOR + 4 * len(program)
        emit(lw(8, 4, 6), "lw   x8, 4(x6)")

        branch_address = RESET_VECTOR + 4 * len(program)
        branch_offset = poll_address - branch_address
        emit(
            bne(8, 0, branch_offset),
            f"bne  x8, x0, {branch_offset}    # -> 0x{poll_address:08x}",
        )
        emit(sb(7, 0, 6), "sb   x7, 0(x6)")

    jump_address = RESET_VECTOR + 4 * len(program)
    jump_offset = start_address - jump_address
    emit(jal(0, jump_offset), f"jal  x0, {jump_offset}  # -> 0x{start_address:08x}")

    expected_words = 2 + 4 * len(message)
    assert len(program) == expected_words
    if len(program) > IMEM_WORDS:
        raise ValueError(
            f"program needs {len(program)} words, but instruction memory holds {IMEM_WORDS}"
        )
    return program


def write_mem(program):
    with OUTPUT_PATH.open("w", encoding="ascii", newline="\n") as output:
        for _, word, _ in program:
            output.write(f"{word:08x}\n")


def print_listing(program):
    print("address     word      mnemonic")
    for address, word, mnemonic in program:
        print(f"0x{address:08x}  {word:08x}  {mnemonic}")


def main():
    self_test()
    program = assemble(MESSAGE)
    write_mem(program)
    print(f"Wrote {len(program)} words to {OUTPUT_PATH}")
    print_listing(program)


if __name__ == "__main__":
    main()
