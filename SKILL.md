---
name: surveydown-skill
description: End-to-end skill for surveydown — the R + Quarto + Shiny survey platform. Covers creating a survey, connecting a database to store responses, and deploying to Hugging Face Spaces and Posit Connect Cloud. Implemented now is Hugging Face deployment, which works on any surveydown survey (made from a template or from scratch); a generator script packages the survey with a shared Dockerfile and pushes it to a Space, creating the Space if needed. Creating a survey, connecting a database, and Posit Connect Cloud deployment are under construction. Use whenever working with surveydown surveys — authoring or hosting.
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
| Deploy to **Posit Connect Cloud** | 🚧 under construction | [`deploy-posit-cloud/`](deploy-posit-cloud/README.md) |

## Core principles (apply across all tasks)

- **Your survey is the source of truth.** A survey is a directory with `app.R` and `survey.qmd` (made from a template or from scratch). Deployment tooling *generates* host-specific artifacts (Dockerfile, packaging) from that directory — it never modifies the survey. Edit the survey, then redeploy.
- **Surveys need a live R/Shiny runtime.** Static hosts (GitHub Pages, Netlify, Quarto Pub) cannot run them. Valid hosts: Hugging Face Spaces (Docker), Posit Connect Cloud, shinyapps.io (retiring), self-hosted Posit Connect.
- **Real data goes to an external database.** `mode: preview` writes to a local `preview_data.csv`, which is fine for demos but lost on ephemeral hosts. For real collection use `mode: database` with external PostgreSQL — see <https://surveydown.org/docs/storing-data>.
- **Always ask about mode and cookies when deploying.** These two `survey.qmd` settings shape every survey, so never assume them: ask the data **mode** (local / preview / database) and whether to **use cookies** (yes / no), then set `mode:` and `use-cookies:` in the survey. If `database` is chosen, set the `SD_*` credentials as host secrets (e.g. Hugging Face Space Secrets), never in a committed file. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) for the full prompts.
- **Never commit or push secrets.** Database credentials live in a git-ignored `.env` locally and as host secrets in production; deployment tooling excludes `.env`/`.Renviron` so they never reach a (public) Space.
- **Authenticate via the keychain, never via chat.** Hugging Face access uses a one-time `hf auth login` (token stored in the OS keychain); `hf`, `git`, and `huggingface_hub` read it automatically. Never ask the user to paste a token into the conversation, put it in a dotfile like `.zshrc`, or run `hf auth token`. If no login exists, ask the user to run `hf auth login` in their own terminal. See [`deploy-hugging-face/`](deploy-hugging-face/README.md) "Setup → Log in with a Write token (safely)".
