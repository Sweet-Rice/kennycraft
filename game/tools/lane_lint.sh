#!/bin/sh
# lane_lint.sh <elf> — the per-lane kernel functions must have no data-dependent branches,
# or the divergent-branch detector halts the core. vtrace_ref may have exactly one branch:
# its BALLOT loop exit, which is uniform by construction.
ELF=$1
bad=0
for f in qrcp ray_setup kc_shade_pixel vtrace_ref shade_px; do
    llvm-nm "$ELF" | grep -q " $f\$" || continue
    n=$(llvm-objdump -d --no-show-raw-insn --disassemble-symbols=$f "$ELF" \
        | grep -cE '\s(beq|bne|blt|bge|bltu|bgeu|beqz|bnez|bltz|bgez|blez|bgtz|j)\s')
    allowed=0; [ "$f" = vtrace_ref ] && allowed=1
    if [ "$n" -ne "$allowed" ]; then echo "FAIL: $f has $n branches (allowed $allowed)"; bad=1; fi
done
[ $bad -eq 0 ] && echo "lane lint OK: kernel is branch-free per lane"
exit $bad
