# surveydown-skill

A skill for working with [surveydown](https://surveydown.org) surveys — authoring
and deploying them.

👉 **Start with [`SKILL.md`](SKILL.md)**, which
routes to the right task doc.

## What it covers

| Task | Status |
|------|--------|
| Create a new survey | 🚧 under construction |
| Connect a database to store responses | 🚧 under construction |
| Deploy to Hugging Face Spaces | ✅ available |
| Deploy to Posit Connect Cloud | 🚧 under construction |

Each section lives in its own folder with a `README.md` guide and its tooling.
The Hugging Face deployment is fully implemented — see
[`hugging-face/`](hugging-face/README.md). The other section folders
([`creating-a-survey/`](creating-a-survey/README.md),
[`connecting-a-database/`](connecting-a-database/README.md),
[`posit-connect-cloud/`](posit-connect-cloud/README.md)) are stubbed and being
filled in.

## Install (Claude Code)

```bash
npx skills add surveydown-dev/surveydown-skill -a claude-code -g -y
```

This installs the `surveydown` skill globally to `~/.claude/skills/`. Start a new
Claude Code session and it's available. ([`npx skills`](https://github.com/vercel-labs/skills)
is the open agent-skills installer.)

## Update

```bash
npx skills add surveydown-dev/surveydown-skill -a claude-code -g -y
```

Re-running `add` pulls the latest version.

## Uninstall (Claude Code)

```bash
npx skills remove surveydown-dev/surveydown-skill -g
```
