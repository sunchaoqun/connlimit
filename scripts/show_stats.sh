#!/usr/bin/env bash
# Display aggregated counters from the xdp_stats map in a table.

set -euo pipefail

MAP_NAME="${1:-xdp_stats}"
# LABELS_DEFAULT="ST_TOTAL,ST_PASS,ST_DROP,ST_TIMEOUT_CLEAN,ST_PASS_SYN,ST_PASS_ACK,ST_PASS_FIN_RST,ST_PASS_OTHER,ST_DROP_SYN,ST_DROP_ACK,ST_DROP_OTHER"
LABELS_DEFAULT="ST_TOTAL,ST_PASS,ST_DROP,ST_TIMEOUT_CLEAN,ST_PASS_SYN,ST_PASS_ACK,ST_PASS_FIN_RST,ST_DROP_SYN,ST_DROP_ACK"

usage() {
    cat <<EOF
Usage: $(basename "$0") [map_name]

Display per-counter statistics collected via stats_inc() from the BPF map.
Defaults to map name 'xdp_stats'.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if ! command -v bpftool >/dev/null 2>&1; then
    echo "Error: bpftool is required but not found in PATH." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required but not found in PATH." >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        BPFT_CMD_PREFIX="sudo"
    else
        echo "Error: please run as root or install sudo to elevate privileges." >&2
        exit 1
    fi
else
    BPFT_CMD_PREFIX=""
fi

export MAP_NAME LABELS_DEFAULT BPFT_CMD_PREFIX

python3 <<'PY'
import json
import os
import shlex
import subprocess
import sys

map_name = os.environ["MAP_NAME"]
labels = [label.strip() for label in os.environ["LABELS_DEFAULT"].split(",") if label.strip()]
cmd_prefix = os.environ.get("BPFT_CMD_PREFIX", "").strip()
cmd_prefix = shlex.split(cmd_prefix) if cmd_prefix else []

def run_bpftool(*args):
    cmd = cmd_prefix + ["bpftool"] + list(args)
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(f"Command {' '.join(cmd)} failed:\n{exc.stderr}\n")
        sys.exit(1)
    return result.stdout

def parse_u64(byte_list):
    return int.from_bytes(bytes(int(b, 16) for b in byte_list), byteorder="little")

maps_json = run_bpftool("-j", "map", "show")
maps = json.loads(maps_json)

target_map = next((m for m in maps if m.get("name") == map_name), None)
if not target_map:
    print(f"Map '{map_name}' not found. Is the program loaded?")
    sys.exit(1)

map_id = str(target_map["id"])
dump_json = run_bpftool("-j", "map", "dump", "id", map_id)
entries = json.loads(dump_json)

rows = []
for entry in entries:
    key_bytes = entry.get("key", [])
    if not key_bytes:
        continue
    index = parse_u64(key_bytes)
    total = 0
    for cpu_bucket in entry.get("values", []):
        value_bytes = cpu_bucket.get("value", [])
        total += parse_u64(value_bytes)
    label = labels[index] if index < len(labels) else f"IDX_{index}"
    rows.append((index, label, total))

if not rows:
    print(f"No data available in map '{map_name}'.")
    sys.exit(0)

rows.sort(key=lambda r: r[0])
string_rows = [(str(idx), label, str(total)) for idx, label, total in rows]

header = ("Idx", "Label", "Count")
widths = [
    max(len(header[0]), max(len(row[0]) for row in string_rows)),
    max(len(header[1]), max(len(row[1]) for row in string_rows)),
    max(len(header[2]), max(len(row[2]) for row in string_rows)),
]

def fmt(row, alignments):
    parts = []
    for value, width, align in zip(row, widths, alignments):
        if align == "left":
            parts.append(value.ljust(width))
        else:
            parts.append(value.rjust(width))
    return "  ".join(parts)

print(fmt(header, ("left", "left", "right")))
print(fmt(("-" * widths[0], "-" * widths[1], "-" * widths[2]), ("left", "left", "right")))
for row in string_rows:
    print(fmt(row, ("left", "left", "right")))
PY

