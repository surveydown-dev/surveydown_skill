#!/usr/bin/env bash
#
# deploy.sh — deploy a surveydown survey to Posit Connect Cloud (R/Shiny), and
# set its display title and custom URL — all from scripts, no web UI.
#
# Works on ANY surveydown survey (a directory with app.R + survey.qmd). Your
# survey directory is the source of truth; this only bundles its runtime files
# and publishes them via rsconnect. Each survey is one Connect Cloud "content"
# item and serves at  https://<account>-<slug>.share.connect.posit.cloud
#
# Usage:
#   ./deploy.sh --title "Display Title" --slug <url-slug> [--dir <survey-dir>]
#   ./deploy.sh --title "Template - Default" --slug default --dir ./template_default
#
#   --title       display title shown on the content (any text, spaces ok)  (required)
#   --slug        custom-URL name; the host becomes <account>-<slug>.share.
#                 connect.posit.cloud (lowercase letters/digits/hyphens)     (required)
#   --dir         path to the survey directory                       (default: .)
#   --name        rsconnect content name / stable id                 (default: --slug)
#   --account     connect.posit.cloud account              (default: your only one)
#   --no-vanity   deploy but skip the custom URL (keep the default GUID URL)
#   --no-secrets  skip the automatic database-secret push (see below)
#   --no-verify   skip the post-deploy live-URL HTTP check
#
# What it does:
#   bundles the survey's runtime files (NOT .env/.git) -> rsconnect::deployApp()
#   to connect.posit.cloud (rsconnect captures R deps from your local library)
#   -> sets the display title + public access via the Connect Cloud REST API
#   -> sets the custom URL (vanity) -> verifies the live URL. In `mode: database`
#   with a real .env beside the survey, the SD_* credentials are shipped as
#   content secrets (deployApp envVars), unless --no-secrets. The account prefix
#   in the URL is fixed by Connect Cloud; only the part after it (--slug) is yours.
#
# Prerequisites:
#   - R with rsconnect >= 1.6.0  (install.packages("rsconnect")). rsconnect also
#     needs every R package the survey uses installed locally (you run the survey
#     locally, so they are) — it snapshots them into the deploy.
#   - A one-time Connect Cloud login, done in YOUR R console so the browser opens:
#       rsconnect::connectCloudUser()
#     The token is cached where rsconnect looks; this script reuses it. Never
#     paste a token into chat or a dotfile. Free plan = 5 applications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="connect.posit.cloud"

DIR="."
TITLE=""
SLUG=""
NAME=""
ACCOUNT=""
VANITY=true
SECRETS=true
VERIFY=true
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        DIR="${2:-}"; shift 2 ;;
    --title)      TITLE="${2:-}"; shift 2 ;;
    --slug)       SLUG="${2:-}"; shift 2 ;;
    --name)       NAME="${2:-}"; shift 2 ;;
    --account)    ACCOUNT="${2:-}"; shift 2 ;;
    --no-vanity)  VANITY=false; shift ;;
    --no-secrets) SECRETS=false; shift ;;
    --no-verify)  VERIFY=false; shift ;;
    -h|--help)    sed -n '2,52p' "$0"; exit 0 ;;
    *)            echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v Rscript >/dev/null 2>&1 || { echo "Error: Rscript not found. Install R." >&2; exit 1; }
[ -n "$TITLE" ] || { echo "Error: --title \"Display Title\" is required (see --help)." >&2; exit 1; }
DIR="$(cd "$DIR" 2>/dev/null && pwd)" || { echo "Error: survey directory not found." >&2; exit 1; }
[ -f "$DIR/app.R" ]      || { echo "Error: no app.R in $DIR — not a surveydown survey?" >&2; exit 1; }
[ -f "$DIR/survey.qmd" ] || { echo "Error: no survey.qmd in $DIR." >&2; exit 1; }

# Defaults: name <- slug <- a URL-safe slug derived from the folder name.
slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
[ -n "$SLUG" ] || SLUG="$(slugify "$(basename "$DIR")")"
[ -n "$NAME" ] || NAME="$SLUG"
echo "$SLUG" | grep -qE '^[a-z0-9][a-z0-9-]*$' || { echo "Error: --slug must be lowercase letters/digits/hyphens." >&2; exit 1; }

# rsconnect present and recent enough for Connect Cloud (>= 1.6.0; latest is best).
ver="$(Rscript -e 'cat(tryCatch(as.character(packageVersion("rsconnect")), error=function(e) "0"))' 2>/dev/null || echo 0)"
if [ "$ver" = "0" ]; then
  echo "Error: the R package 'rsconnect' is not installed." >&2
  echo "       Install the latest:  Rscript -e 'install.packages(\"rsconnect\")'" >&2
  exit 1
fi
if [ "$(printf '%s\n1.6.0\n' "$ver" | sort -V | head -1)" != "1.6.0" ]; then
  echo "Error: rsconnect $ver predates Posit Connect Cloud support (needs >= 1.6.0; older only targets shinyapps.io)." >&2
  echo "       Upgrade to the latest:  Rscript -e 'install.packages(\"rsconnect\")'" >&2
  exit 1
fi

# Resolve the connect.posit.cloud account. (read loop, not mapfile — macOS bash 3.2)
ACCTS=()
while IFS= read -r _line; do [ -n "$_line" ] && ACCTS+=("$_line"); done < <(
  Rscript -e 'a<-rsconnect::accounts(); a<-a[a$server=="connect.posit.cloud",]; if(nrow(a)) cat(a$name, sep="\n")' 2>/dev/null
)
if [ "${#ACCTS[@]}" -eq 0 ]; then
  echo "Error: no Connect Cloud account is registered." >&2
  echo "       In your R console run once:  rsconnect::connectCloudUser()" >&2
  echo "       (a browser opens to authorize; the token is then cached for this script)." >&2
  exit 1
fi
if [ -z "$ACCOUNT" ]; then
  if [ "${#ACCTS[@]}" -eq 1 ]; then
    ACCOUNT="${ACCTS[0]}"
  else
    echo "Error: multiple Connect Cloud accounts found: ${ACCTS[*]}" >&2
    echo "       Pass --account <name> to choose one." >&2
    exit 1
  fi
else
  printf '%s\n' "${ACCTS[@]}" | grep -qx "$ACCOUNT" || { echo "Error: account '$ACCOUNT' is not a registered Connect Cloud account (have: ${ACCTS[*]})." >&2; exit 1; }
fi

# Read the survey's data mode (drives the database-secret push).
MODE="$(grep -E '^[[:space:]]*mode:[[:space:]]*' "$DIR/survey.qmd" 2>/dev/null \
  | head -1 | sed -E 's/.*mode:[[:space:]]*//; s/[[:space:]]*#.*//; s/["'"'"']//g; s/[[:space:]]*$//')"
MODE="${MODE:-preview}"

echo ">>> $DIR  ->  $SERVER / $ACCOUNT   (title: \"$TITLE\", slug: $SLUG, mode: $MODE)"

SD_PC_DIR="$DIR" SD_PC_ACCOUNT="$ACCOUNT" SD_PC_NAME="$NAME" SD_PC_TITLE="$TITLE" \
SD_PC_SLUG="$([ "$VANITY" = true ] && echo "$SLUG" || echo "")" SD_PC_MODE="$MODE" \
SD_PC_SECRETS="$SECRETS" SD_PC_VANITY="$VANITY" SD_PC_VERIFY="$VERIFY" \
  Rscript "$SCRIPT_DIR/deploy.R"
