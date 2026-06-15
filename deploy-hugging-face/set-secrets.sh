#!/usr/bin/env bash
#
# set-secrets.sh — push a survey's database credentials to a Hugging Face Space
# as SECRETS, reading them from the survey's local .env. Values are never printed,
# so they don't leak into logs or an agent's chat transcript.
#
# Usage:
#   ./set-secrets.sh --space <owner>/<name> [--env <path-to-.env>]
#
#   --space   target Hugging Face Space, e.g. yourname/my-survey   (required)
#   --env     path to the .env file holding the SD_* values        (default: ./.env)
#
# What it does:
#   Reads SD_HOST, SD_PORT, SD_DBNAME, SD_USER, SD_TABLE, SD_PASSWORD from the
#   .env and sets each as a Space Secret (write-only env var) via the
#   huggingface_hub API. The Space restarts and picks them up; sd_db_connect()
#   then reads them from the environment. It REFUSES to push placeholder values.
#
# Prerequisites:
#   - The hf CLI installed and logged in (see README "Setup"). The same Python
#     environment that provides `hf` provides the huggingface_hub library used here.
#   - A .env with your real database credentials (create it with
#     `surveydown::sd_db_config()` or by editing the file).

set -euo pipefail

SPACE=""
ENV_FILE=".env"
while [ $# -gt 0 ]; do
  case "$1" in
    --space) SPACE="${2:-}"; shift 2 ;;
    --env)   ENV_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$SPACE" ] || { echo "Error: --space <owner>/<name> is required." >&2; exit 1; }
case "$SPACE" in */*) ;; *) echo "Error: --space must be <owner>/<name>." >&2; exit 1 ;; esac
[ -f "$ENV_FILE" ] || { echo "Error: env file not found: $ENV_FILE" >&2; exit 1; }

# Find a Python that can import huggingface_hub. The `hf` CLI is often a symlink
# into a pipx/venv, so resolve it to locate the venv's python; then fall back to
# python3 / python and any pipx venv.
PYBIN=""
cands=()
if command -v hf >/dev/null 2>&1; then
  # Resolve symlinks portably (macOS readlink lacks -f); python3 is just for path math.
  real_hf="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v hf)" 2>/dev/null || true)"
  [ -n "$real_hf" ] && cands+=("$(dirname "$real_hf")/python")
fi
cands+=(python3 python)
for g in "$HOME"/.local/pipx/venvs/*/bin/python; do [ -e "$g" ] && cands+=("$g"); done
for p in "${cands[@]}"; do
  if "$p" -c "import huggingface_hub" >/dev/null 2>&1; then PYBIN="$p"; break; fi
done
[ -n "$PYBIN" ] || {
  echo "Error: no Python with huggingface_hub found." >&2
  echo "       Install it: pipx install huggingface_hub  (then re-run)." >&2
  exit 1
}

echo ">>> setting secrets on $SPACE from $ENV_FILE"
"$PYBIN" - "$SPACE" "$ENV_FILE" <<'PY'
import sys
from huggingface_hub import add_space_secret

repo_id, env_file = sys.argv[1], sys.argv[2]
KEYS = ["SD_HOST", "SD_PORT", "SD_DBNAME", "SD_USER", "SD_TABLE", "SD_PASSWORD"]
PLACEHOLDER_HINTS = ("your-", "example", "changeme", "<", "placeholder", "xxxx")

vals = {}
with open(env_file) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip('"').strip("'")

present = [k for k in KEYS if vals.get(k)]
missing = [k for k in KEYS if not vals.get(k)]
if not present:
    sys.exit(f"No SD_* values found in {env_file}.")

# Refuse to push obvious placeholders — prevents wiping real secrets with stubs.
stubs = [k for k in present if any(h in vals[k].lower() for h in PLACEHOLDER_HINTS)]
if stubs:
    sys.exit(
        "Refusing to push: these still look like placeholders -> "
        + ", ".join(stubs)
        + f"\nFill real values in {env_file} (e.g. via surveydown::sd_db_config()) and retry."
    )

for k in present:
    add_space_secret(repo_id=repo_id, key=k, value=vals[k])  # uses cached HF login token
    print(f"  set secret {k}  ✓")
if missing:
    print("  (skipped absent/empty: " + ", ".join(missing) + ")")
print(f"Done. {repo_id} will restart and pick up the secrets.")
PY
