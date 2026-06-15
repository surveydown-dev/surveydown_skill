---
name: surveydown
description: End-to-end skill for surveydown — the R + Quarto + Shiny survey platform. Covers building/creating surveys and deploying them to hosts. Implemented now: deploying the survey templates to Hugging Face Spaces (Docker SDK) from their GitHub repos via a shared Dockerfile and a generator script. Planned: creating a survey from scratch, and deploying to Posit Connect Cloud. Use whenever working with surveydown surveys — authoring or hosting.
---

# Skill: surveydown

Use this skill for any [surveydown](https://surveydown.org) task — authoring a survey or deploying one to a host. surveydown surveys are R + Quarto + Shiny apps (an `app.R` plus a `survey.qmd`), so they need a host that runs R/Shiny, not a static host.

The skill is organized by task. Read the doc that matches what you're doing:

| Task | Status | Read |
|------|--------|------|
| Deploy survey templates to **Hugging Face Spaces** (Docker) | ✅ implemented | [`resources/hugging-face-deployment.md`](resources/hugging-face-deployment.md) |
| Create a new survey from scratch | 🔜 planned | — |
| Deploy to **Posit Connect Cloud** | 🔜 planned | — |

Each implemented task keeps its tooling in a sibling directory (e.g. the Hugging Face tooling lives in [`hugging-face/`](hugging-face/)).

## Core principles (apply across all tasks)

- **Templates are the single source of truth.** Each survey template is its own GitHub repo under `surveydown-dev`. Deployment tooling *generates* host-specific artifacts from a template — it never keeps a second editable copy. Edit the template, then redeploy.
- **Surveys need a live R/Shiny runtime.** Static hosts (GitHub Pages, Netlify, Quarto Pub) cannot run them. Valid hosts: Hugging Face Spaces (Docker), Posit Connect Cloud, shinyapps.io (retiring), self-hosted Posit Connect.
- **Real data goes to an external database.** `mode: preview` writes to a local `preview_data.csv`, which is fine for demos but lost on ephemeral hosts. For real collection use `mode: database` with external PostgreSQL — see <https://surveydown.org/docs/storing-data>.

## Naming convention

A template repo `template_<name>` maps to a deploy target `<name>` with underscores turned to dashes — e.g. `template_question_types` → `question-types`. Hugging Face URL: `https://<owner>-<name>.hf.space`.
