---
title: Surveydown {{TITLE}}
emoji: 📋
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
license: mit
---

# Surveydown — {{TITLE}}

A [surveydown](https://surveydown.org) survey template, hosted on Hugging Face
Spaces with the Docker SDK.

> **Generated — do not edit here.** This Space is built from
> [`{{TEMPLATE_REPO}}`](https://github.com/{{TEMPLATE_REPO}}) by the
> [`hugging_face_deployment`](https://github.com/surveydown-dev/hugging_face_deployment)
> tooling. Edit the template, then redeploy.

The container installs R, the Quarto CLI, and surveydown (development v1.3.0),
then renders and serves the survey on port 7860.

Runs in `mode: preview`, so responses go to a local `preview_data.csv` — and
Hugging Face Space disks are **ephemeral**, so that file is lost on restart. For
real data collection, switch to `mode: database` with an external PostgreSQL
database (see <https://surveydown.org/docs/storing-data>).
