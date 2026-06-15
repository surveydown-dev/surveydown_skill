#!/usr/bin/env bash
#
# deploy.sh — build & push surveydown templates to Hugging Face Spaces.
#
# Each Space is generated from its GitHub template (the single source of truth):
#   clone template -> add shared Dockerfile + generated README + packages.txt
#   -> push to the matching HF Space (which auto-rebuilds).
#
# Usage:
#   ./deploy.sh <name> [<name> ...]   Deploy specific templates
#   ./deploy.sh --all                 Deploy everything in templates.txt
#   ./deploy.sh --no-push <name>      Build only; print the assembled folder, don't push
#
# <name> accepts any form: question-types, question_types, or template_question_types
#
# Config (override via env vars):
#   GITHUB_ORG   GitHub org holding the template repos   (default: surveydown-dev)
#   HF_OWNER     Hugging Face user/org owning the Spaces (default: pingfanhu)
#
# Prerequisites:
#   - git, tar
#   - The target HF Space already exists (Docker SDK). Create at huggingface.co/new-space,
#     or with the HF CLI: hf repo create <HF_OWNER>/<space> --repo-type space --space-sdk docker
#   - Git is authenticated to push to huggingface.co (run `hf auth login`, or you'll be
#     prompted for username + a Write token on first push).

set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:-surveydown-dev}"
HF_OWNER="${HF_OWNER:-pingfanhu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/assets"

# R packages that should never go into packages.txt (base/recommended + installed separately)
EXCLUDE_PKGS="base stats utils graphics grDevices methods datasets tools parallel compiler splines stats4 grid tcltk surveydown shiny"

PUSH=true
ALL=false
TARGETS=()

for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=false ;;
    --all)     ALL=true ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*)        echo "Unknown option: $arg" >&2; exit 1 ;;
    *)         TARGETS+=("$arg") ;;
  esac
done

if [ "$ALL" = true ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] && TARGETS+=("$line")
  done < "$SCRIPT_DIR/templates.txt"
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "Nothing to do. Pass template name(s) or --all (see --help)." >&2
  exit 1
fi

title_case() { echo "$1" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1'; }

deploy_one() {
  local raw="$1"
  local name="${raw#template_}"   # strip optional template_ prefix
  name="${name//-/_}"             # normalize to underscore form
  local template="template_${name}"
  local space="${name//_/-}"      # HF space name uses dashes
  local title; title="$(title_case "$name")"

  echo ">>> ${template}  ->  ${HF_OWNER}/${space}"
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # 1. Clone the template (tracked source only)
  if ! git clone --quiet --depth 1 "https://github.com/${GITHUB_ORG}/${template}.git" "$tmp/src"; then
    echo "    ! could not clone https://github.com/${GITHUB_ORG}/${template}.git" >&2
    return 1
  fi

  # 2. Assemble the Space content from tracked files, minus dev/meta files
  mkdir "$tmp/space"
  ( cd "$tmp/src" && git archive HEAD ) | tar -x -C "$tmp/space"
  rm -f  "$tmp/space/README.md" "$tmp/space"/*.Rproj "$tmp/space/.gitignore" "$tmp/space/.gitattributes"
  rm -rf "$tmp/space/_survey" "$tmp/space/rsconnect" "$tmp/space/.posit"
  rm -f  "$tmp/space/manifest.json" "$tmp/space/preview_data.csv"

  # 3. Shared build files
  cp "$ASSETS/Dockerfile"    "$tmp/space/Dockerfile"
  cp "$ASSETS/dockerignore"  "$tmp/space/.dockerignore"

  # 4. packages.txt — extra R packages from the template's library()/require() calls
  : > "$tmp/space/packages.txt"
  grep -rhoE '(library|require)\(([^),]+)\)' "$tmp/src/app.R" "$tmp/src/survey.qmd" 2>/dev/null \
    | sed -E "s/.*\(['\"]?([A-Za-z0-9._]+)['\"]?\)/\1/" \
    | sort -u \
    | while IFS= read -r p; do
        [ -z "$p" ] && continue
        case " $EXCLUDE_PKGS " in *" $p "*) continue ;; esac
        echo "$p" >> "$tmp/space/packages.txt"
      done
  echo "    packages.txt: $(paste -sd' ' "$tmp/space/packages.txt" 2>/dev/null || echo '(none)')"

  # 5. README with HF frontmatter
  sed -e "s/{{TITLE}}/${title}/g" \
      -e "s|{{TEMPLATE_REPO}}|${GITHUB_ORG}/${template}|g" \
      "$ASSETS/space-readme.template.md" > "$tmp/space/README.md"

  if [ "$PUSH" != true ]; then
    cp -R "$tmp/space" "/tmp/hf_build_${space}"
    echo "    built (no push): /tmp/hf_build_${space}"
    return 0
  fi

  # 6. Push to the HF Space repo (replace contents, keep its git history)
  if ! git clone --quiet "https://huggingface.co/spaces/${HF_OWNER}/${space}" "$tmp/hf"; then
    echo "    ! could not clone the Space. Create it first:" >&2
    echo "      hf repo create ${HF_OWNER}/${space} --repo-type space --space-sdk docker" >&2
    return 1
  fi
  ( cd "$tmp/hf" && git ls-files -z | xargs -0 git rm -q --ignore-unmatch >/dev/null 2>&1 || true )
  cp -R "$tmp/space/." "$tmp/hf/"
  (
    cd "$tmp/hf"
    git add -A
    if git diff --cached --quiet; then
      echo "    no changes — Space already up to date"
    else
      git commit -q -m "Deploy from ${GITHUB_ORG}/${template}"
      git push -q
      echo "    pushed -> https://${HF_OWNER}-${space}.hf.space  (building...)"
    fi
  )
}

rc=0
for t in "${TARGETS[@]}"; do
  deploy_one "$t" || rc=1
done
exit "$rc"
