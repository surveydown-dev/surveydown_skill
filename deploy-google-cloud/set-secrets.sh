#!/usr/bin/env bash
#
# set-secrets.sh — store a survey's database credentials in Google Secret Manager,
# reading them from the survey's local .env. Values are never printed, so they
# don't leak into logs or a chat transcript. deploy.sh calls this automatically
# for database-mode surveys, then references the secrets with --set-secrets.
#
# Usage:
#   ./set-secrets.sh [--project <id>] [--env <path-to-.env>]
#
#   --project  GCP project id        (default: active gcloud project)
#   --env      path to the .env file (default: ./.env)
#
# Creates/updates Secret Manager secrets named SD_HOST, SD_PORT, SD_DBNAME,
# SD_USER, SD_TABLE, SD_PASSWORD from the .env. Refuses obvious placeholders.
# The Cloud Run service reads them as environment variables; sd_db_connect()
# picks them up.

set -euo pipefail

PROJECT=""
ENV_FILE=".env"
RUNTIME_SA=""   # service account that must READ the secrets (default: compute SA)
while [ $# -gt 0 ]; do
  case "$1" in
    --project)     PROJECT="${2:-}"; shift 2 ;;
    --env)         ENV_FILE="${2:-}"; shift 2 ;;
    --runtime-sa)  RUNTIME_SA="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v gcloud >/dev/null 2>&1 || { echo "Error: gcloud CLI not found." >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "Error: env file not found: $ENV_FILE" >&2; exit 1; }
[ -n "$PROJECT" ] || PROJECT="$(gcloud config get-value project 2>/dev/null)"
[ -n "$PROJECT" ] && [ "$PROJECT" != "(unset)" ] || { echo "Error: no project. Pass --project or set gcloud config." >&2; exit 1; }

KEYS="SD_HOST SD_PORT SD_DBNAME SD_USER SD_TABLE SD_PASSWORD"
PLACEHOLDER_RE='your-|example|changeme|placeholder|<|xxxx'

# Read one SD_* value from the .env (trimmed, unquoted). Bash 3.2-compatible
# (macOS default) — no associative arrays.
get_env_val() {
  local line v
  line="$(grep -E "^[[:space:]]*$1=" "$2" 2>/dev/null | head -1)"
  [ -n "$line" ] || return 0
  v="${line#*=}"
  v="${v%$'\r'}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"   # trim
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"               # unquote
  printf '%s' "$v"
}

present=""; missing=""; stubs=""
for k in $KEYS; do
  v="$(get_env_val "$k" "$ENV_FILE")"
  if [ -n "$v" ]; then
    present="$present $k"
    if printf '%s' "$v" | grep -qiE "$PLACEHOLDER_RE"; then stubs="$stubs $k"; fi
  else
    missing="$missing $k"
  fi
done
[ -n "$present" ] || { echo "No SD_* values found in $ENV_FILE." >&2; exit 1; }
if [ -n "$stubs" ]; then
  echo "Refusing to store: these still look like placeholders ->$stubs" >&2
  echo "Fill real values in $ENV_FILE (e.g. via surveydown::sd_db_config()) and retry." >&2
  exit 1
fi

gcloud services enable secretmanager.googleapis.com --project "$PROJECT" >/dev/null 2>&1 || true
echo ">>> storing secrets in Secret Manager (project $PROJECT) from $ENV_FILE"
for k in $present; do
  v="$(get_env_val "$k" "$ENV_FILE")"
  if gcloud secrets describe "$k" --project "$PROJECT" >/dev/null 2>&1; then
    printf '%s' "$v" | gcloud secrets versions add "$k" --project "$PROJECT" --data-file=- >/dev/null
  else
    printf '%s' "$v" | gcloud secrets create "$k" --project "$PROJECT" --replication-policy=automatic --data-file=- >/dev/null
  fi
  echo "  set secret $k  ✓"
done
if [ -n "$missing" ]; then echo "  (skipped absent/empty:$missing)"; fi

# Grant the Cloud Run runtime service account read access to each secret.
# gcloud run deploy --set-secrets does NOT auto-grant this, so the revision would
# fail with "Permission denied on secret ... secretmanager.secretAccessor".
# Default runtime SA is the Compute Engine default SA (<projnum>-compute@...).
if [ -z "$RUNTIME_SA" ]; then
  pnum="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' 2>/dev/null)"
  [ -n "$pnum" ] && RUNTIME_SA="${pnum}-compute@developer.gserviceaccount.com"
fi
if [ -n "$RUNTIME_SA" ]; then
  for k in $present; do
    gcloud secrets add-iam-policy-binding "$k" --project "$PROJECT" \
      --member="serviceAccount:${RUNTIME_SA}" \
      --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true
  done
  echo "  granted secretAccessor to $RUNTIME_SA"
fi
echo "Done. Reference them with --set-secrets=SD_HOST=SD_HOST:latest,... (deploy.sh does this)."
