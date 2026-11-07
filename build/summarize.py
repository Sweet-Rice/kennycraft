"""Write summary.json for the fpga-tools MCP build contract.

Usage: summarize.py <FPGA_BUILD_OUT> <ila true|false>
Reads timing.rpt, check_timing.rpt, utilization.rpt and build.log from the
build output directory.
"""
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
timing = (out / "timing.rpt").read_text()
wns = {}
for group, clock, value in re.findall(
    r"^(?:[ \t]*(Path Group:[^\n]*)\n)?[ \t]*From Clock:[^\n]*\n[ \t]*To Clock:[ \t]*(\S+)[ \t]*\n"
    r"(?:[ \t]*\n)*Setup[ \t]*:[^\n]*Worst Slack[ \t]*([-+]?\d+(?:\.\d+)?)ns",
    timing,
    re.MULTILINE,
):
    if not group:
        wns[clock] = min(wns.get(clock, float("inf")), float(value))

utilization = {}
report = (out / "utilization.rpt").read_text()
for key, label in (("lut", "Slice LUTs"), ("ff", "Slice Registers"),
                   ("bram36", "Block RAM Tile"), ("dsp", "DSPs")):
    match = re.search(rf"^\|\s*{re.escape(label)}\*?\s*\|\s*([\d.]+)\s*\|", report, re.MULTILINE)
    if match:
        utilization[key] = float(match[1])

log = (out / "build.log").read_text()
checks = (out / "check_timing.rpt").read_text()
summary = dict(
    wns=wns,
    utilization=utilization,
    ila=sys.argv[2] == "true",
    bitstream="top.bit",
    critical_warnings=len(re.findall(r"^\s*CRITICAL WARNING:\s*\[", log, re.MULTILINE)),
    unconstrained_clocks=int(re.search(r"checking no_clock \((\d+)\)", checks)[1]),
    inferred_latches=len(re.findall(r"\[Synth 8-327\]\s*inferring latch", log)),
)
(out / "summary.json").write_text(json.dumps(summary))
