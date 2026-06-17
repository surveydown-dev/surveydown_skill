---
name: surveydown-skill
description: End-to-end skill for surveydown — the R + Quarto + Shiny survey platform. Covers creating a survey, connecting a database to store responses, and deploying to Hugging Face Spaces, Google Cloud Run, and Posit Connect Cloud. Implemented now are Hugging Face Spaces, Google Cloud Run, and Posit Connect Cloud deployment, which work on any surveydown survey (made from a template or from scratch) via a generator script that packages the survey and deploys it. Creating a survey and connecting a database are under construction. Use whenever working with surveydown surveys — authoring or hosting.
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

## Deploying? Pick a platform first

There are **three** deployment platforms, and they are the **only** choices:
**Hugging Face Spaces**, **Posit Connect Cloud**, and **Google Cloud Run**.

- **If the user names a platform** (Hugging Face / Posit Connect Cloud / Google
  Cloud Run, however phrased) — go straight to that section. **Do not ask.**
- **If the user only says they want to deploy/host/publish a survey online**
  *without* naming one — **ask which of the three** before doing anything else.
  Offer only these three; do not invent or suggest other hosts (static hosts can't
  run R/Shiny). Lead with each free tier's main limit so the user can choose:
  - **Hugging Face Spaces** — free tier runs about **3 surveys at once**. No bank
    card needed.
  - **Posit Connect Cloud** — free tier allows **5 surveys** total. No bank card
    needed.
  - **Google Cloud Run** — **no limit** on how many, but you must **link a bank
    card** to the Google account (stays ≈ $0 for low-traffic surveys).

Once the platform is known, follow that section's README — including its
**always-ask** survey settings (mode, cookies) and any platform-specific prompts
(e.g. display title + URL slug for Posit Connect Cloud).

## Core principles (apply across all tasks)

- **Your survey is the source of truth.** A survey is a directory with `app.R` and `survey.qmd` (made from a template or from scratch). Deployment tooling *generates* host-specific artifacts (Dockerfile, packaging) from that directory — it never modifies the survey. Edit the survey, then redeploy.
- **Surveys need a live R/Shiny runtime.** Static hosts (GitHub Pages, Netlify, Quarto Pub) cannot run them. Valid hosts: Hugging Face Spaces (Docker), Posit Connect Cloud, shinyapps.io (retiring), self-hosted Posit Connect.
- **Real data goes to an external database.** `mode: preview` writes to a local `preview_data.csv`, which is fine for demos but lost on ephemeral hosts. For real collection use `mode: database` with external PostgreSQL — see <https://surveydown.org/docs/storing-data>.
- **Always ask about mode and cookies when deploying.** These two `survey.qmd` settings shape every survey, so never assume them: ask the data **mode** (local / preview / database) and whether to **use cookies** (yes / no), then set `mode:` and `use-cookies:` in the survey. If `database` is chosen, set the `SD_*` credentials as host secrets (e.g. Hugging Face Space Secrets), never in a committed file. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) for the full prompts.
- **Never commit or push secrets.** Database credentials live in a git-ignored `.env` locally and as host secrets in production; deployment tooling excludes `.env`/`.Renviron` so they never reach a (public) Space.
- **Respect the host's hardware quota; stop, don't grind.** A host caps how many Spaces run at once (Hugging Face free CPU is small, ~3). The tooling detects this from the API (`deploy.sh --wait` exits 3 on a quota pause; `check-quota.sh <owner>` reports running/limit/headroom). When the cap is hit, **stop deploying and report the current/limit to the user** — never retry or poll a build that won't run. For a batch, check quota first and halt at the cap. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) "Hardware quota".
- **Authenticate via the keychain, never via chat.** Hugging Face access uses a one-time `hf auth login` (token stored in the OS keychain); `hf`, `git`, and `huggingface_hub` read it automatically. Never ask the user to paste a token into the conversation, put it in a dotfile like `.zshrc`, or run `hf auth token`. If no login exists, ask the user to run `hf auth login` in their own terminal. Same principle for Google Cloud: rely on a one-time `gcloud auth login` (the active account/project, via `gcloud auth list` / `gcloud config get-value project`); if not logged in, ask the user to run it themselves. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) "Setup → Log in with a Write token (safely)".
