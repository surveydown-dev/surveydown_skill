# Deploy a surveydown survey to Posit Connect Cloud

Deploy **any** surveydown survey — one you made from a template or wrote from
scratch — to **Posit Connect Cloud**, and set its display title and custom URL,
**entirely from scripts** (no web UI). The generator (`deploy.sh` + `deploy.R`)
lives in this folder.

Your survey directory is the source of truth. The tooling only bundles its
runtime files and publishes them with `rsconnect` — it never modifies your
survey. Connect Cloud runs the live R/Shiny app and serves it at
`https://<account>-<slug>.share.connect.posit.cloud`.

## Agent workflow (follow this when deploying for a user)

When you (the assistant) deploy a survey to Connect Cloud on a user's behalf,
settle the following with the user **before** running `deploy.sh` — do not assume
any of them.

### A. Survey configuration — ALWAYS ASK BOTH

Mode and cookies are critical settings for every survey, so **always ask both
questions**, then edit the `survey-settings:` block in the survey's `survey.qmd`
to match the answers. (This edits the survey itself — an authoring step done with
the user's consent — and is separate from `deploy.sh`, which never touches the
survey.)

1. **Mode** — ask which data mode to use:
   - **local** — responses saved to a local `local_data.csv`; no database. On a
     hosted runtime this is ephemeral (lost on restart), like preview.
   - **preview** — responses saved to a local `preview_data.csv`; for
     testing/previewing. Any database connection is ignored. Fine for a demo.
   - **database** — responses stored in an external PostgreSQL database. The only
     **durable** option (Connect Cloud's container disk is ephemeral, so
     local/preview CSVs are wiped on restart).

   Set `mode: <choice>` in `survey.qmd`. **If the user chooses `database`**, the
   `SD_*` credentials must reach the running app:
   1. **Locally:** run `surveydown::sd_db_config()` (or hand-edit a `.env`) to
      create a `.env` holding `SD_HOST`, `SD_PORT`, `SD_DBNAME`, `SD_USER`,
      `SD_TABLE`, `SD_PASSWORD`. The `.env` is git-ignored and is **never**
      bundled into the deploy.
   2. **On Connect Cloud:** `deploy.sh` ships those values as **content secrets**
      automatically (via `deployApp(envVars=)`), reading them from the survey's
      `.env`, refusing obvious placeholders, and never printing them. Re-running
      the deploy re-syncs them. Pass `--no-secrets` to skip. (You can also set
      them by hand under the content's **Settings → Variables**.)

      As the assistant, rely on the automatic path — never ask the user to paste
      credentials into the conversation.

2. **Cookies** — ask "Do you want to use cookies?" with **yes** / **no**:
   - **yes** (`use-cookies: true`) — a per-browser cookie lets each participant
     resume where they left off on reload.
   - **no** (`use-cookies: false`) — no resume; reloading starts fresh.

   Set `use-cookies: <true|false>` in `survey.qmd`.

### B. Deployment target — ALWAYS ASK BOTH

3. **Display title** — ask what title to show on the content (the name in the
   Connect Cloud dashboard and content header). Any text, spaces allowed, e.g.
   `Template - Default`. Offer a sensible suggestion (drawn from the survey's
   `survey.qmd` title / folder name) and let the user accept or change it. Pass it
   via `--title "..."`. Display-only; it does **not** affect the URL.

4. **URL slug** — ask for the custom-URL name (the editable part of the address).
   The live host is **`<account>-<slug>.share.connect.posit.cloud`**. The
   `<account>-` prefix is **fixed by Connect Cloud** (your account name); only the
   `<slug>` after it is yours to choose. It must be URL-safe (lowercase letters,
   digits, hyphens), e.g. `default` → `https://<account>-default.share.connect.
   posit.cloud`. Pass it via `--slug ...`. Propose a slug from the survey/folder
   name and let the user confirm.

## Why Posit Connect Cloud

surveydown surveys are live R/Shiny apps, so they need a host that runs R — not a
static host. Connect Cloud is Posit's managed home for R/Shiny (and the
recommended successor to the retiring shinyapps.io), publishes straight from
`rsconnect`, and serves each app on a clean standalone URL.

Trade-offs to know:
- **Free plan = 5 applications.** Shiny apps (surveydown surveys) count toward
  this; only static *documents* are unlimited. Redeploying an existing survey
  updates it in place and does **not** consume a new slot — only a new content
  *name* does. Plan which 5 surveys live here.
- Container disk is ephemeral → never rely on `preview_data.csv` for real data;
  use `mode: database` + external PostgreSQL.
- The URL prefix is your account name and cannot be removed on the shared domain;
  only the slug after `<account>-` is customizable (custom domains you own are a
  paid feature).

## Prerequisites

- **R with `rsconnect` >= 1.6.0** (`install.packages("rsconnect")`). Connect Cloud
  support landed in 1.6.0; older versions only target shinyapps.io. `rsconnect`
  also needs every R package the survey uses **installed locally** — you run the
  survey locally, so they are — because it snapshots them into the deploy (no
  Dockerfile, no `packages.txt`).
- A surveydown survey directory containing `app.R` and `survey.qmd`.
- A one-time Connect Cloud login (below).

## Setup (one time)

### Log in to Connect Cloud (browser handshake)

In **your own R console** (so a browser can open), run once:

```r
rsconnect::connectCloudUser()
```

A browser opens to `login.posit.cloud`; authorize it (pick your account if
prompted). The OAuth token is cached where `rsconnect` looks, and `deploy.sh`
reuses it — you never pass a token again, and it is never printed or written to a
file you edit. This is the Connect Cloud equivalent of `hf auth login` /
`gcloud auth login`.

- **Why your R console, not this script:** the handshake is interactive
  (browser-based); it cannot be driven from a non-interactive shell or from chat.
- **Multiple accounts:** `rsconnect::accounts()` lists them; pass `--account
  <name>` to pick. With a single Connect Cloud account, `deploy.sh` uses it
  automatically.
- **Non-interactive / CI (optional):** generate a client ID + secret at
  `login.posit.cloud/identity/credentials` and register it once with
  `rsconnect::connectCloudClientCredentials(clientId, clientSecret, accountName)`
  for headless deploys (no browser).

## Usage

Run from your survey directory (or pass `--dir`):

```bash
# deploy + set title + set custom URL + verify, in one command:
/path/to/deploy-posit-cloud/deploy.sh \
  --title "Template - Default" --slug default --dir ./template_default

# from inside the survey folder, slug/name default to the folder name:
/path/to/deploy-posit-cloud/deploy.sh --title "My Survey"

# keep the default GUID URL (skip the custom URL):
/path/to/deploy-posit-cloud/deploy.sh --title "My Survey" --slug my-survey --no-vanity

# database-mode survey: also ships the .env's SD_* values as content secrets
# (use --no-secrets to skip)
```

(When the skill is installed, the script is at
`~/.claude/skills/surveydown-skill/deploy-posit-cloud/deploy.sh`.)

### Display title vs. URL slug

A content item has two independent names:

- **Display title** (`--title`) — the heading in the Connect Cloud dashboard.
  Any text. Changing it never changes the URL.
- **URL slug** (`--slug`) — the editable part of the address. The host is
  `<account>-<slug>.share.connect.posit.cloud`; the `<account>-` prefix is fixed.

Both are applied via the Connect Cloud REST API after the publish, so they stick
on every redeploy (set them with the flags, not by hand in the UI, or the next
deploy reasserts the flag values).

## How the generator works

`deploy.sh` validates inputs, checks `rsconnect`, resolves the Connect Cloud
account, reads the survey's `mode` from `survey.qmd`, then hands off to
`deploy.R`, which:

1. Builds an explicit file allow-list (every file under the survey dir minus build
   artifacts, dev junk, and **secrets** — `.env`/`.Renviron` are never bundled;
   `rsconnect` does not honour `.gitignore`, so the list is explicit).
2. In `mode: database`, loads `SD_*` from the survey's `.env` and passes them as
   `deployApp(envVars=)` so they land as content secrets (placeholders refused).
3. Runs `rsconnect::deployApp(server = "connect.posit.cloud", ...)`, which bundles
   the files, snapshots R dependencies from the local library, uploads, and
   publishes. A redeploy of the same `--name` updates the existing content.
4. Resolves the content GUID from the local deployment record.
5. Sets the **display title** and **public access** via `PATCH /v1/contents/{guid}`.
6. Sets the **custom URL** via `PATCH /v1/contents/{guid}` with
   `{"vanity_name": "<slug>", "domain_id": null}` (the explicit `domain_id: null`
   is required, otherwise the API rejects the vanity).
7. Reports the account's `N/5` application-slot usage (best effort).
8. Verifies the live URL over HTTP and prints the public URL + dashboard link.

A first publish typically takes a **few minutes** (Connect Cloud installs the R
dependencies remotely). Redeploys are faster.

### Free-tier cap (5 applications) — agent rule

The free plan runs **5 applications**. `deploy.R` reports current usage as `N/5`.
When the account is at 5 and the user asks to deploy a **new** survey (a new
`--name`), **stop and tell the user** — deleting/retiring an existing one or
choosing a different host (e.g. Hugging Face) is the user's decision, not an
automatic retry. Redeploying any of the existing 5 is always fine.

## Files (in this folder)

| File | Purpose |
|------|---------|
| `deploy.sh` | Entry point: validates inputs, resolves the account, runs `deploy.R` |
| `deploy.R` | R workhorse: `deployApp` + sets title/URL/secrets via the Connect Cloud API |
| `README.md` | This guide |
