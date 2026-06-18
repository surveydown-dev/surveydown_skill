---
name: surveydown-skill
description: End-to-end skill for surveydown — the R + Quarto + Shiny survey platform. Covers creating a survey, connecting a database to store responses, deploying to Hugging Face Spaces, Google Cloud Run, and Posit Connect Cloud, and recording a local video walkthrough of a survey. Implemented now are Hugging Face Spaces, Google Cloud Run, and Posit Connect Cloud deployment (which work on any surveydown survey via a generator script that packages and deploys it), plus a macOS record-video tool that drives a survey in a visible browser and screen-captures the run. Creating a survey and connecting a database are under construction. Use whenever working with surveydown surveys — authoring, hosting, or demoing.
---

# Skill: surveydown-skill

Use this skill for any [surveydown](https://surveydown.org) task — authoring a survey or deploying one to a host. surveydown surveys are R + Quarto + Shiny apps (an `app.R` plus a `survey.qmd`), so they need a host that runs R/Shiny, not a static host.

The skill is organized into one folder per section, each with a `README.md` guide
(and its tooling). Read the section that matches what you're doing:

| Task | Status | Section |
|------|--------|---------|
| Create a new survey | 🚧 under construction | [`create-survey/`](create-survey/README.md) |
| Connect a database to store responses | 🚧 under construction | [`connect-database/`](connect-database/README.md) |
| Deploy to **Hugging Face Spaces** (Docker) | ✅ implemented | [`deploy-hugging-face/`](deploy-hugging-face/README.md) |
| Deploy to **Google Cloud Run** (Docker) | ✅ implemented | [`deploy-google-cloud/`](deploy-google-cloud/README.md) |
| Deploy to **Posit Connect Cloud** (rsconnect) | ✅ implemented | [`deploy-posit-cloud/`](deploy-posit-cloud/README.md) |
| Record a video walkthrough of a survey (local) | ✅ implemented (macOS) | [`record-video/`](record-video/README.md) |

## Authoritative docs: consult `llms.txt` when unsure

The official surveydown documentation site publishes an LLM-friendly index at:

**<https://www.surveydown.org/llms.txt>**

Whenever you are unsure about any documented surveydown feature — usage, syntax,
question types, conditional logic (`sd_show_if` / `sd_skip_if` / `sd_stop_if`),
templates, settings, data storage, or deployment — **fetch this file first.** It is
a plain-markdown index listing every documentation, template, and blog page, each
linking to a clean `.llms.md` version written for machines (no HTML/nav chrome).

Workflow:
1. Fetch `llms.txt` to see the full list of available pages and their URLs.
2. Pick the page(s) relevant to the task and fetch the corresponding `.llms.md`
   link (e.g. `https://www.surveydown.org/docs/conditional-logic.llms.md`).
3. Prefer these pages over guessing — the installed package's roxygen only covers
   function signatures, not how features are meant to be assembled.

This index is regenerated on every site build, so it always reflects the current
docs. Treat it as the source of truth over any memorized detail.

## Deploying? Pick a platform first

There are **three** deployment platforms, and they are the **only** choices:
**Hugging Face Spaces**, **Posit Connect Cloud**, and **Google Cloud Run**.

- **If the user names a platform** (Hugging Face / Posit Connect Cloud / Google
  Cloud Run, however phrased) — go straight to that section. **Do not ask.**
- **If the user only says they want to deploy/host/publish a survey online**
  *without* naming one — **ask which of the three** before doing anything else.
  Offer only these three; do not invent or suggest other hosts (static hosts can't
  run R/Shiny). Keep each description short:
  - **Hugging Face Spaces** — free tier: **3 surveys**.
  - **Posit Connect Cloud** — free tier: **5 surveys**.
  - **Google Cloud Run** — **a bank card is required** (≈ $0 when idle); no limit on
    the number of surveys.

Once the platform is known, follow that section's README — including its
**always-ask** survey settings (mode, cookies) and any platform-specific prompts
(e.g. display title + URL slug for Posit Connect Cloud).

## Deploying several surveys at once (batch)

When the user asks to deploy **multiple** surveys, **batch the questions** — never
walk survey-by-survey asking the same things again and again.

1. **Ask the shared settings once, for the whole batch:** platform (if not named),
   data **mode**, and **cookies**. They apply to every survey in the batch.
2. **Propose the per-survey names in one step.** Each survey still needs its own
   display title and URL slug (and content/service name). Derive a sensible default
   for each from its folder name / `survey.qmd` title, then present them **all
   together as one table** for the user to accept or tweak in a single reply — do
   not prompt one survey at a time.
3. **Check the free-tier cap before starting.** If the batch would exceed the
   platform's limit (Hugging Face ~3 running, Posit Connect Cloud 5 total — count
   what's already deployed), say so and stop for the user's decision rather than
   deploying into a wall.
4. **Deploy all, then report once.** Run the per-survey deploys (in sequence or in
   parallel — your call) and return a **single summary table**: survey → title →
   live URL → status. Surface any per-survey failures there; don't abort the whole
   batch for one bad survey.

## Core principles (apply across all tasks)

- **Your survey is the source of truth.** A survey is a directory with `app.R` and `survey.qmd` (made from a template or from scratch). Deployment tooling *generates* host-specific artifacts (Dockerfile, packaging) from that directory — it never modifies the survey. Edit the survey, then redeploy.
- **Surveys need a live R/Shiny runtime.** Static hosts (GitHub Pages, Netlify, Quarto Pub) cannot run them. Valid hosts: Hugging Face Spaces (Docker), Posit Connect Cloud, shinyapps.io (retiring), self-hosted Posit Connect.
- **Real data goes to an external database.** `mode: preview` writes to a local `preview_data.csv`, which is fine for demos but lost on ephemeral hosts. For real collection use `mode: database` with external PostgreSQL — see <https://surveydown.org/docs/storing-data>.
- **Always ask about mode and cookies when deploying.** These two `survey.qmd` settings shape every survey, so never assume them: ask the data **mode** (local / preview / database) and whether to **use cookies** (yes / no), then set `mode:` and `use-cookies:` in the survey. If `database` is chosen, set the `SD_*` credentials as host secrets (e.g. Hugging Face Space Secrets), never in a committed file. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) for the full prompts.
- **Never commit or push secrets.** Database credentials live in a git-ignored `.env` locally and as host secrets in production; deployment tooling excludes `.env`/`.Renviron` so they never reach a (public) Space.
- **Respect the host's hardware quota; stop, don't grind.** A host caps how many Spaces run at once (Hugging Face free CPU is small, ~3). The tooling detects this from the API (`deploy.sh --wait` exits 3 on a quota pause; `check-quota.sh <owner>` reports running/limit/headroom). When the cap is hit, **stop deploying and report the current/limit to the user** — never retry or poll a build that won't run. For a batch, check quota first and halt at the cap. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) "Hardware quota".
- **Authenticate via the keychain, never via chat.** Hugging Face access uses a one-time `hf auth login` (token stored in the OS keychain); `hf`, `git`, and `huggingface_hub` read it automatically. Never ask the user to paste a token into the conversation, put it in a dotfile like `.zshrc`, or run `hf auth token`. If no login exists, ask the user to run `hf auth login` in their own terminal. Same principle for Google Cloud: rely on a one-time `gcloud auth login` (the active account/project, via `gcloud auth list` / `gcloud config get-value project`); if not logged in, ask the user to run it themselves. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) "Setup → Log in with a Write token (safely)".
