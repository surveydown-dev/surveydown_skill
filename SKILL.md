---
name: surveydown
description: End-to-end skill for surveydown — the R + Quarto + Shiny survey platform. Covers creating a survey, connecting a database to store responses, and deploying to Hugging Face Spaces and Posit Connect Cloud. Implemented now is Hugging Face deployment (generating each Space from its GitHub template via a shared Dockerfile and a generator script). Creating a survey, connecting a database, and Posit Connect Cloud deployment are under construction. Use whenever working with surveydown surveys — authoring or hosting.
---

# Skill: surveydown

Use this skill for any [surveydown](https://surveydown.org) task — authoring a survey or deploying one to a host. surveydown surveys are R + Quarto + Shiny apps (an `app.R` plus a `survey.qmd`), so they need a host that runs R/Shiny, not a static host.

The skill is organized into one folder per section, each with a `README.md` guide
(and its tooling). Read the section that matches what you're doing:

| Task | Status | Section |
|------|--------|---------|
| Create a new survey | 🚧 under construction | [`creating-a-survey/`](creating-a-survey/README.md) |
| Connect a database to store responses | 🚧 under construction | [`connecting-a-database/`](connecting-a-database/README.md) |
| Deploy to **Hugging Face Spaces** (Docker) | ✅ implemented | [`hugging-face/`](hugging-face/README.md) |
| Deploy to **Posit Connect Cloud** | 🚧 under construction | [`posit-connect-cloud/`](posit-connect-cloud/README.md) |

## Core principles (apply across all tasks)

- **Templates are the single source of truth.** Each survey template is its own GitHub repo under `surveydown-dev`. Deployment tooling *generates* host-specific artifacts from a template — it never keeps a second editable copy. Edit the template, then redeploy.
- **Surveys need a live R/Shiny runtime.** Static hosts (GitHub Pages, Netlify, Quarto Pub) cannot run them. Valid hosts: Hugging Face Spaces (Docker), Posit Connect Cloud, shinyapps.io (retiring), self-hosted Posit Connect.
- **Real data goes to an external database.** `mode: preview` writes to a local `preview_data.csv`, which is fine for demos but lost on ephemeral hosts. For real collection use `mode: database` with external PostgreSQL — see <https://surveydown.org/docs/storing-data>.

## Naming convention

A template repo `template_<name>` maps to a deploy target `<name>` with underscores turned to dashes — e.g. `template_question_types` → `question-types`. Hugging Face URL: `https://<owner>-<name>.hf.space`.
