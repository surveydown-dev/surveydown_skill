#!/usr/bin/env bash
#
# deploy.sh — deploy a surveydown survey to a Hugging Face Space (Docker SDK).
#
# Works on ANY surveydown survey (a directory with app.R + survey.qmd) — a survey
# you made from a template or from scratch. Your survey directory is the source of
# truth; this only generates the Hugging Face packaging and pushes it to a Space.
#
# Usage:
#   ./deploy.sh --space <owner>/<name> [--dir <survey-dir>] [--title "Display Title"] [--wait]
#   ./deploy.sh --space <owner>/<name> --no-push     # build only, don't push
#
#   --space       target Hugging Face Space, e.g. yourname/my-survey   (required)
#   --dir         path to the survey directory                         (default: .)
#   --title       display title shown on the Space card (any text, spaces ok)
#                 (default: derived from the Space name, e.g. "My Survey")
#                 This is only the display name; the URL slug never changes.
#   --wait        after pushing, poll until the Space is RUNNING and report the
#                 live URL + HTTP status (deploy and verify in one command)
#   --no-push     assemble the Space folder and print its path; skip the push
#   --no-secrets  skip the automatic database-secret sync (see below)
#
# What it does:
#   copy the survey's runtime files -> add the shared Dockerfile + a generated
#   README (HF frontmatter) + packages.txt (from the survey's library() calls)
#   -> push to the Space, which auto-rebuilds. If the Space doesn't exist yet and
#   the `hf` CLI is available, it is created (Docker SDK) automatically.
#   If the survey is in `mode: database` and a real .env sits next to it, the
#   SD_* credentials are pushed to the Space as Secrets (via set-secrets.sh),
#   unless --no-secrets is given. Placeholder .env values are refused, not pushed.
#
# Prerequisites:
#   - git, and rsync (or it falls back to cp).
#   - The `hf` CLI, logged in (so the Space can be auto-created and the push is
#     authenticated). One-time setup:
#       pipx install huggingface_hub      # or: brew install huggingface-cli
#       hf auth login --token <WRITE_TOKEN> --add-to-git-credential
#     (Use the --token form in non-interactive/embedded shells, where the
#     interactive prompt cannot read a hidden token. Get a Write token at
#     https://huggingface.co/settings/tokens .)
#   - Without the `hf` CLI you must create the Space yourself first
#     (huggingface.co/new-space, Docker SDK) and git will prompt for your
#     username + a Write token on the first push.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/assets"

# R packages never written to packages.txt (base/recommended + installed separately)
EXCLUDE_PKGS="base stats utils graphics grDevices methods datasets tools parallel compiler splines stats4 grid tcltk surveydown shiny"

SPACE=""
DIR="."
TITLE=""
PUSH=true
WAIT=false
SECRETS=true
while [ $# -gt 0 ]; do
  case "$1" in
    --space)      SPACE="${2:-}"; shift 2 ;;
    --dir)        DIR="${2:-}"; shift 2 ;;
    --title)      TITLE="${2:-}"; shift 2 ;;
    --wait)       WAIT=true; shift ;;
    --no-push)    PUSH=false; shift ;;
    --no-secrets) SECRETS=false; shift ;;
    -h|--help)    sed -n '2,43p' "$0"; exit 0 ;;
    *)            echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$SPACE" ] || { echo "Error: --space <owner>/<name> is required (see --help)." >&2; exit 1; }
case "$SPACE" in */*) ;; *) echo "Error: --space must be <owner>/<name>." >&2; exit 1 ;; esac
DIR="$(cd "$DIR" 2>/dev/null && pwd)" || { echo "Error: survey directory not found." >&2; exit 1; }
[ -f "$DIR/app.R" ]      || { echo "Error: no app.R in $DIR — not a surveydown survey?" >&2; exit 1; }
[ -f "$DIR/survey.qmd" ] || { echo "Error: no survey.qmd in $DIR." >&2; exit 1; }

owner="${SPACE%%/*}"; name="${SPACE##*/}"
# Display title: use --title if given, else Title-Case the Space name.
if [ -n "$TITLE" ]; then
  title="$TITLE"
else
  title="$(echo "$name" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1')"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/space"

echo ">>> $DIR  ->  $owner/$name"

# 1. Copy the survey's files, excluding build artifacts, dev/meta junk, and
#    SECRETS. .env / .Renviron hold database credentials and must NEVER be pushed
#    to a (public) Space — set those as Space Secrets in the Hugging Face UI
#    instead; sd_db_connect() reads them from the environment.
EXCLUDES=(.git .gitignore .gitattributes .env .Renviron _survey survey_files survey.html preview_data.csv rsconnect manifest.json .posit .Rproj.user .Ruserdata .DS_Store)
if command -v rsync >/dev/null 2>&1; then
  rsync_args=()
  for e in "${EXCLUDES[@]}"; do rsync_args+=(--exclude="$e"); done
  rsync_args+=(--exclude='*.Rproj')
  rsync -a "${rsync_args[@]}" "$DIR"/ "$tmp/space"/
else
  cp -R "$DIR"/. "$tmp/space"/
  ( cd "$tmp/space" && rm -rf "${EXCLUDES[@]}" ./*.Rproj 2>/dev/null || true )
fi

# 2. Shared build files
cp "$ASSETS/Dockerfile"   "$tmp/space/Dockerfile"
cp "$ASSETS/dockerignore" "$tmp/space/.dockerignore"

# 3. packages.txt — extra R packages from the survey's library()/require() calls
: > "$tmp/space/packages.txt"
grep -rhoE '(library|require)\(([^),]+)\)' "$DIR/app.R" "$DIR/survey.qmd" 2>/dev/null \
  | sed -E "s/.*\(['\"]?([A-Za-z0-9._]+)['\"]?\)/\1/" \
  | sort -u \
  | while IFS= read -r p; do
      [ -z "$p" ] && continue
      case " $EXCLUDE_PKGS " in *" $p "*) continue ;; esac
      echo "$p" >> "$tmp/space/packages.txt"
    done
echo "    packages.txt: $(paste -sd' ' "$tmp/space/packages.txt" 2>/dev/null || true)"

# 4. README with Hugging Face frontmatter (bash replace — safe for any title chars)
template="$(cat "$ASSETS/space-readme.template.md")"
printf '%s\n' "${template//\{\{TITLE\}\}/$title}" > "$tmp/space/README.md"

# 5. Build-only mode
if [ "$PUSH" != true ]; then
  out="/tmp/hf_build_${name}"
  rm -rf "$out"; cp -R "$tmp/space" "$out"
  echo "    built (no push): $out"
  exit 0
fi

# 6. Push to the Space (replace contents, keep its git history).
#    If the clone fails, the Space probably doesn't exist yet — create it with
#    the hf CLI (Docker SDK) and retry once.
space_url="https://huggingface.co/spaces/${owner}/${name}"
if ! git clone --quiet "$space_url" "$tmp/hf" 2>/dev/null; then
  if command -v hf >/dev/null 2>&1; then
    echo "    Space not found — creating ${owner}/${name} (Docker SDK)..."
    if ! hf repos create "${owner}/${name}" --repo-type space --space-sdk docker >/dev/null 2>&1; then
      echo "    ! could not create the Space. Are you logged in? Run: hf auth login" >&2
      exit 1
    fi
    git clone --quiet "$space_url" "$tmp/hf"
  else
    echo "    ! could not clone the Space, and the hf CLI isn't installed to create it." >&2
    echo "      Install it (pipx install huggingface_hub) and log in, or create the" >&2
    echo "      Space manually at huggingface.co/new-space (Docker SDK), then retry." >&2
    exit 1
  fi
fi
( cd "$tmp/hf" && git ls-files -z | xargs -0 git rm -q --ignore-unmatch >/dev/null 2>&1 || true )
cp -R "$tmp/space/." "$tmp/hf/"
(
  cd "$tmp/hf"
  git add -A
  if git diff --cached --quiet; then
    echo "    no changes — Space already up to date"
  else
    git commit -q -m "Deploy surveydown survey"
    git push -q
    echo "    pushed -> https://${owner}-${name}.hf.space  (building...)"
  fi
)

# 6b. Database mode: sync the survey's DB credentials to the Space as Secrets.
#     Runs only when the survey is in `mode: database` and a real .env sits next
#     to it. set-secrets.sh refuses placeholders and never prints values. A
#     failure here (e.g. placeholders) is a warning, not a fatal deploy error.
if [ "$SECRETS" = true ]; then
  # Read the survey mode from survey.qmd's survey-settings (default: database).
  mode_val="$(grep -E '^[[:space:]]*mode:[[:space:]]*' "$DIR/survey.qmd" 2>/dev/null \
    | head -1 | sed -E 's/.*mode:[[:space:]]*//; s/[[:space:]]*#.*//; s/["'"'"']//g; s/[[:space:]]*$//')"
  mode_val="${mode_val:-database}"
  if [ "$mode_val" = database ]; then
    if [ -f "$DIR/.env" ]; then
      echo "    database mode — syncing DB secrets from $DIR/.env ..."
      if ! "$SCRIPT_DIR/set-secrets.sh" --space "$SPACE" --env "$DIR/.env"; then
        echo "    ! secrets not synced (see above). The Space will show 'DATABASE" >&2
        echo "      NOT CONNECTED' until real credentials are set." >&2
      fi
    else
      echo "    database mode but no .env in $DIR — set Space Secrets manually or" >&2
      echo "      add a .env, then re-run (or run set-secrets.sh)." >&2
    fi
  fi
fi

# 7. Optionally wait until the Space is RUNNING, then verify the URL.
if [ "$WAIT" = true ]; then
  api="https://huggingface.co/api/spaces/${owner}/${name}"
  app_url="https://${owner}-${name}.hf.space"
  echo "    waiting for the Space to build (this is usually a few minutes)..."
  stage=""
  for _ in $(seq 1 60); do   # up to ~20 min (60 * 20s)
    # Grab the runtime stage from the Space API without a JSON dependency.
    stage="$(curl -fsSL "$api" 2>/dev/null | grep -o '"stage":"[^"]*"' | head -1 | cut -d'"' -f4)"
    echo "      [$(date +%H:%M:%S)] stage=${stage:-unknown}"
    case "$stage" in
      RUNNING) break ;;
      *RUNTIME_ERROR*|*BUILD_ERROR*|CONFIG_ERROR)
        echo "    ! Space ended in '$stage'. Check the build logs:" >&2
        echo "      ${space_url}?logs=build" >&2
        exit 1 ;;
    esac
    sleep 20
  done
  if [ "$stage" = RUNNING ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 30 "$app_url" 2>/dev/null || true)"
    echo "    RUNNING -> $app_url  (HTTP ${code:-?})"
  else
    echo "    ! still not RUNNING after the wait window; last stage='${stage:-unknown}'." >&2
    echo "      Check progress at ${space_url}" >&2
    exit 1
  fi
fi
