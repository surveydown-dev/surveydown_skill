#!/usr/bin/env bash
#
# check-quota.sh — report Hugging Face Space hardware-quota usage for an account,
# so you can tell BEFORE deploying whether you'll hit the cap (instead of waiting
# on a build that ends up quota-paused).
#
# Hugging Face does not document the free CPU-Basic concurrent-Space limit in
# prose, but it exposes the real numbers in each Space's runtime JSON
# (runtime.errorMessage, e.g. "Quota exceeded ... current=3, limit=3"). This
# reads them via the API using the active hf login.
#
# Usage:
#   ./check-quota.sh <owner>        # e.g. ./check-quota.sh surveydown
#   ./check-quota.sh                # defaults to the active account (hf auth whoami)
#
# Prints: how many of the account's Spaces are RUNNING vs PAUSED, and the hardware
# limit if it can be read from any quota-paused Space. Exit code 3 if already at/
# over the limit, else 0.

set -euo pipefail

OWNER="${1:-}"

# Find a Python that can import huggingface_hub (same logic as set-secrets.sh).
PYBIN=""
cands=()
if command -v hf >/dev/null 2>&1; then
  real_hf="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v hf)" 2>/dev/null || true)"
  [ -n "$real_hf" ] && cands+=("$(dirname "$real_hf")/python")
fi
cands+=(python3 python)
for g in "$HOME"/.local/pipx/venvs/*/bin/python; do [ -e "$g" ] && cands+=("$g"); done
for p in "${cands[@]}"; do
  if "$p" -c "import huggingface_hub" >/dev/null 2>&1; then PYBIN="$p"; break; fi
done
[ -n "$PYBIN" ] || { echo "Error: no Python with huggingface_hub found (pipx install huggingface_hub)." >&2; exit 1; }

"$PYBIN" - "$OWNER" <<'PY'
import sys, re
from huggingface_hub import HfApi

api = HfApi()
owner = sys.argv[1] or api.whoami().get("name")
if not owner:
    sys.exit("Could not determine the account. Pass <owner> or run: hf auth login")

running, paused, other, limit = 0, 0, 0, None
for s in api.list_spaces(author=owner):
    try:
        rt = api.get_space_runtime(s.id)
    except Exception:
        other += 1
        continue
    stage = (rt.stage or "").upper()
    if stage == "RUNNING":
        running += 1
    elif stage == "PAUSED":
        paused += 1
    else:
        other += 1
    msg = (getattr(rt, "raw", None) or {}).get("errorMessage", "") or ""
    m = re.search(r"limit=(\d+)", msg)
    if m:
        limit = int(m.group(1))

print(f"account:  {owner}")
print(f"running:  {running}")
print(f"paused:   {paused}")
print(f"other:    {other}  (building / sleeping / errored)")
if limit is not None:
    print(f"limit:    {limit}  (concurrent CPU-basic Spaces, read from a quota message)")
    free = limit - running
    print(f"headroom: {free}  (Spaces you can still start before hitting the cap)")
    sys.exit(3 if free <= 0 else 0)
else:
    print("limit:    unknown (no quota-paused Space to read it from — you may not")
    print("          have hit the cap yet; deploy one with --wait to discover it).")
PY
