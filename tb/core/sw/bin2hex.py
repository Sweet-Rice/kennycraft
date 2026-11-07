"""Turn a raw binary section into a $readmemh image of 32-bit words.

    bin2hex.py <in.bin> <out.hex> <words> [byte_offset]

byte_offset is where the binary starts inside the memory (dmem data starts
at 0x100). Words are little-endian; the image is zero-padded to <words>.
"""

import sys
from pathlib import Path


def main():
    src, dst, words = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
    offset = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0
    data = bytes(offset) + Path(src).read_bytes()
    if len(data) > 4 * words:
        sys.exit(f"bin2hex: {src} needs {len(data)} bytes, memory holds {4 * words}")
    data += bytes(4 * words - len(data))
    with open(dst, "w", encoding="ascii", newline="\n") as out:
        for i in range(0, len(data), 4):
            out.write(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n")


if __name__ == "__main__":
    main()
