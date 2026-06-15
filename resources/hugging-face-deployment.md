# Deploying surveydown templates to Hugging Face Spaces

Deploy the surveydown survey templates to **Hugging Face Spaces** (Docker SDK).
Tooling lives in [`../hugging-face/`](../hugging-face/).

Each template is its own GitHub repo and remains the **single source of truth**.
The tooling does not duplicate surveys — it *generates* each Space from its
template at deploy time, so you only ever edit the template.

## Why Hugging Face

surveydown surveys are live R/Shiny apps, so they need a host that runs R — not a
static host. Hugging Face Spaces (Docker SDK) runs R Shiny, has no per-account app
limit on the free tier (unlike Posit Connect Cloud's 5), and serves each app on a
clean standalone URL with no HF chrome: `https://<owner>-<space>.hf.space`.

Trade-offs to know:
- One Space = one container = one R process (no horizontal scaling). Fine for
  demos and modest N; not for thousands of simultaneous users.
- Free Spaces sleep after inactivity and wake on next visit (cold start).
- Container disk is ephemeral → never rely on `preview_data.csv` for real data;
  use `mode: database` + external PostgreSQL.

## How the generator works

For each template, `hugging-face/deploy.sh`:

1. Clones the template from `github.com/<GITHUB_ORG>/template_<name>` (tracked files only).
2. Assembles the Space content: the template's `app.R`, `survey.qmd`, and any
   `images/`, `data/`, etc., **plus** the shared `assets/Dockerfile`, a generated
   `README.md` (with Hugging Face frontmatter), and a generated `packages.txt`.
3. Pushes that content to the matching Hugging Face Space, which auto-rebuilds.

`_survey/` is **not** shipped — the container renders the survey at startup
(Quarto is in the image). This keeps the Space repos free of binary files, which
Hugging Face rejects in plain git.

### One shared Dockerfile

`hugging-face/assets/Dockerfile` is identical for every Space. Per-template R
packages are supplied via a generated `packages.txt` (derived from each template's
`library()`/`require()` calls), so there is exactly one Dockerfile to maintain.
surveydown installs from GitHub (dev v1.3.0; CRAN only has 1.0.1). The Quarto CLI
is pinned to a direct download URL (the GitHub API gets rate-limited / 403 on
build servers).

## Prerequisites

- `git` and `tar`.
- Each target Space must already exist on Hugging Face (Docker SDK). Create one at
  <https://huggingface.co/new-space>, or with the HF CLI:
  ```bash
  hf repo create <HF_OWNER>/<space> --repo-type space --space-sdk docker
  ```
- Git must be able to push to `huggingface.co`. Run `hf auth login`, or you'll be
  prompted for your username and a **Write** token on the first push.

## Usage

```bash
cd hugging-face

# Build only (no push) — inspect the assembled Space folder under /tmp
./deploy.sh --no-push question-types

# Deploy one or more templates (any name form works:
#   question-types, question_types, or template_question_types)
./deploy.sh question-types
./deploy.sh question_types template_default

# Deploy everything listed in templates.txt
./deploy.sh --all
```

Override the GitHub org or Hugging Face owner via env vars:

```bash
GITHUB_ORG=surveydown-dev HF_OWNER=surveydown ./deploy.sh --all
```

## Files (under `hugging-face/`)

| File | Purpose |
|------|---------|
| `deploy.sh` | Build + push generator |
| `templates.txt` | Template repos to deploy with `--all` |
| `assets/Dockerfile` | Shared Dockerfile used by every Space |
| `assets/dockerignore` | Copied into each Space as `.dockerignore` |
| `assets/space-readme.template.md` | README template (HF frontmatter) for each Space |

## Adding a template

Add its repo name (`template_<name>`) to `hugging-face/templates.txt`, create the
Space, and run `./deploy.sh <name>`. No other changes needed.
