#!/bin/sh
# chip_check.sh <elf> — fail if the chip build uses anything the core doesn't have.
set -e
ELF=$1
DIS=$(mktemp)
llvm-objdump -d --no-show-raw-insn "$ELF" > "$DIS"
bad=0
if grep -E '\s(div|divu|rem|remu)\s' "$DIS" >/dev/null; then echo "FAIL: divide instructions"; bad=1; fi
if grep -E '^\s+[0-9a-f]+:\s+f[a-z.]+\s' "$DIS" >/dev/null; then echo "FAIL: float instructions"; bad=1; fi
if grep -E '<__(div|mod|udiv|umod|mul|ash|lsh|float|fix|add|sub)' "$DIS" >/dev/null; then echo "FAIL: libgcc calls"; bad=1; fi
if grep -E '\s(ecall|csrr|csrw)' "$DIS" >/dev/null; then echo "FAIL: ecall/csr"; bad=1; fi
llvm-size -A "$ELF" 2>/dev/null | grep -E '^\.(text|rodata|data|bss)' || true
rm -f "$DIS"
[ $bad -eq 0 ] && echo "chip check OK: $ELF (rv32i_zmmul, no div/float/libcalls)"
exit $bad
