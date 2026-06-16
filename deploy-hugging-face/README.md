# Deploy a surveydown survey to Hugging Face Spaces

Deploy **any** surveydown survey — one you made from a template or wrote from
scratch — to a **Hugging Face Space** (Docker SDK). The generator script
(`deploy.sh`) and shared assets live in this folder.

Your survey directory is the source of truth. The tooling only *generates* the
Hugging Face packaging (a Dockerfile, a README, a package list) and pushes it to a
Space — it never modifies your survey.

## Agent workflow (follow this when deploying for a user)

When you (the assistant) deploy a survey to Hugging Face on a user's behalf,
settle the following with the user **before** running `deploy.sh` — do not assume
any of them.

### A. Survey configuration — ALWAYS ASK BOTH

Mode and cookies are critical settings for every survey, so **always ask both
questions**, then edit the `survey-settings:` block in the survey's `survey.qmd`
to match the answers. (This edits the survey itself — an authoring step done with
the user's consent — and is separate from `deploy.sh`, which never touches the
survey.)

1. **Mode** — ask which data mode to use, presenting these three options with a
   one-line description each:
   - **local** — responses saved to a local `local_data.csv` file; no database.
     Good for collecting data while the app runs on your own machine.
   - **preview** — responses saved to a local `preview_data.csv`; meant for
     testing/previewing. Any database connection is ignored in this mode.
   - **database** — responses stored in an external PostgreSQL database. The only
     **durable** option on ephemeral hosts (local/preview CSV files are wiped when
     a Hugging Face Space restarts).

   Set `mode: <choice>` in `survey.qmd`. **If the user chooses `database`**, the
   credentials must reach the running container — walk them through both steps:
   1. **Locally:** run `surveydown::sd_db_config()` (or hand-edit a `.env`) to
      create a `.env` holding `SD_HOST`, `SD_PORT`, `SD_DBNAME`, `SD_USER`,
      `SD_TABLE`, `SD_PASSWORD`. The `.env` is git-ignored and is **never** pushed
      to the Space (`deploy.sh` excludes it).
   2. **On Hugging Face:** the same six `SD_*` values must exist as Space
      **Secrets** (not public Variables); `sd_db_connect()` reads them from the
      environment. Until they are set, the live survey runs but shows a "DATABASE
      NOT CONNECTED — responses are not being saved" banner.
      - **Automatic (default):** when the survey is in `mode: database` and a real
        `.env` sits next to it, **`deploy.sh` syncs the secrets for you** after the
        push — it calls `set-secrets.sh`, which reads the `.env` and pushes each
        value as a Secret via the `huggingface_hub` API **without printing the
        values**, refusing obvious placeholders. So the one deploy command also
        provisions the secrets. (Pass `--no-secrets` to skip this.)
      - **Standalone:** run it yourself any time (e.g. after rotating a password):
        ```bash
        /path/to/deploy-hugging-face/set-secrets.sh --space <owner>/<name>
        # reads ./.env by default; pass --env <path> for a survey elsewhere
        ```
      - **Manual UI:** add each `SD_*` as a **Secret** under the Space's
        **Settings → Variables and secrets**
        (`https://huggingface.co/spaces/<owner>/<name>/settings`).

      As the assistant, rely on the automatic/standalone script paths — never ask
      the user to paste credentials into the conversation.

2. **Cookies** — ask "Do you want to use cookies?" with **yes** / **no**:
   - **yes** (`use-cookies: true`) — a per-browser cookie lets each participant
     resume the survey where they left off (state restored on reload). Each browser
     is its own independent entity, so concurrent participants never collide.
   - **no** (`use-cookies: false`) — no resume; reloading starts the survey fresh.

   Set `use-cookies: <true|false>` in `survey.qmd`.

### B. Deployment target — confirm before pushing

3. **URL slug** — confirm the target `--space <owner>/<name>`. The `<name>`
   becomes the URL (`https://<owner>-<name>.hf.space`) and must be URL-safe
   (lowercase, dashes, no spaces). Propose a sensible slug from the survey/folder
   name and let the user accept or change it.
4. **Display title** — always **ask the user what display title to show on the
   Space card**. Offer a few reasonable suggestions (e.g. the Title-Cased slug, or
   a descriptive phrase drawn from the survey's `survey.qmd` title / `README`), and
   also let them type their own. Pass their choice via `--title "..."`. The title
   is display-only; it never changes the URL. (If the user explicitly says they
   don't care, fall back to the default Title-Cased slug.)

This keeps the title intentional rather than an auto-generated guess, and because
the README is regenerated on every deploy, `--title` is the durable way to set it.

## Why Hugging Face

surveydown surveys are live R/Shiny apps, so they need a host that runs R — not a
static host. Hugging Face Spaces (Docker SDK) runs R Shiny, has no per-account app
limit on the free tier, and serves each app on a clean standalone URL with no HF
chrome: `https://<owner>-<space>.hf.space`.

Trade-offs to know:
- One Space = one container = one R process (no horizontal scaling). Fine for
  modest N; not for thousands of simultaneous users.
- Free Spaces sleep after inactivity and wake on next visit (cold start).
- Container disk is ephemeral → never rely on `preview_data.csv` for real data;
  use `mode: database` + external PostgreSQL.

## Prerequisites

- `rsync` (the script falls back to `cp` if it's missing). No `git` needed — the
  push uses `hf upload` (the Hub HTTP API), not raw git.
- A surveydown survey directory containing `app.R` and `survey.qmd`.
- The Hugging Face `hf` CLI, **logged in** — see Setup below. `deploy.sh` creates
  the Space for you (if it doesn't exist) and uploads as the **active** login, so
  switching accounts (`hf auth switch`) just works — no OS git credential to go
  stale.

## Setup (one time)

### 1. Install the `hf` CLI

The CLI ships in the `huggingface_hub` package.

- **macOS / Homebrew Python:** `pip` is blocked by PEP 668 ("externally managed
  environment"), and `pip install --user` is blocked too — so use an isolated
  install:
  ```bash
  brew install pipx && pipx install huggingface_hub
  # or, if Homebrew has the formula: brew install huggingface-cli
  ```
- **Other systems / virtualenv:** `pip install -U huggingface_hub` is fine.

Verify: `hf version` (the binary may land in `~/.local/bin` — add it to `PATH` if
`hf` isn't found, e.g. `export PATH="$HOME/.local/bin:$PATH"`).

### 2. Log in with a Write token (safely)

Create a **Write** token at <https://huggingface.co/settings/tokens>. You log in
**once**; after that the token lives in your OS keychain and the tooling (`hf`,
`huggingface_hub`) reads it automatically — you never pass it again.

**Preferred — interactive login in a real terminal:**

```bash
hf auth login        # paste the token at the hidden prompt
```

Run this in a normal terminal (Terminal.app, your IDE's terminal) where hidden
input works. The token is **never echoed, never written to a file you edit, and
never appears in any log or chat transcript** — it goes straight into the keychain.

Verify: `hf auth whoami`.

#### Token safety (important — for both the user and the assistant)

- **Never paste a token into a chat/conversation, a script, or a committed file.**
  Anything typed on a command line is recorded in the transcript/shell history.
- **Don't put the token in `.zshrc`/`.bashrc` or any dotfile.** Dotfiles are
  plaintext, often synced to git (accidental public leak), and load the secret
  into *every* shell and process. The keychain (via `hf auth login`) is the right
  place and is already wired into the tooling.
- **Assistant rule:** to authenticate, rely on the **existing keychain login** —
  do not ask the user to paste a token into the conversation. If no valid login
  exists (`hf auth whoami` errors), ask the user to run `hf auth login` themselves
  in their own terminal, then continue. Never run `hf auth token` (it prints the
  token to stdout, putting it back in the transcript).
- **Multiple accounts:** `hf auth list` shows stored logins; `hf auth switch`
  changes the active one; `hf auth whoami` confirms it. Log in once per account and
  switch as needed — the push uploads as whoever is active, so switching is all it
  takes to deploy under a different account.

**Fallback — non-interactive shells only.** If you must log in from a shell that
can't read hidden input (e.g. an embedded shell — you'll see *"Can not control
echo on the terminal"* and the prompt aborts), use the `--token` form, but know
the token will be visible in that command:

```bash
hf auth login --token <YOUR_WRITE_TOKEN>
```

Prefer the interactive method whenever possible; only fall back to `--token` when
hidden input is genuinely unavailable, and rotate the token afterward if it landed
anywhere persistent.

> The `hf` CLI is required — both to create the Space and to upload (the push goes
> through `hf upload`, the Hub HTTP API). Install it as in step 1 above.

## Usage

Run from your survey directory (or pass `--dir`):

```bash
# from inside your survey folder:
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey

# or point at the survey explicitly, from anywhere:
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey --dir ~/surveys/my-survey

# build only — assemble the Space folder under /tmp and inspect it, no push:
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey --no-push

# set the display title shown on the Space card (URL is unaffected):
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey \
  --title "My Survey — Pilot Wave 1"

# deploy AND wait: poll until the Space is RUNNING, then report URL + HTTP status:
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey --wait

# database-mode survey: this also pushes the .env's SD_* values as Space Secrets:
/path/to/deploy-hugging-face/deploy.sh --space yourname/my-survey --wait
# ...or skip the secret sync with --no-secrets
```

If the Space doesn't exist yet, `deploy.sh` creates it for you (Docker SDK, via the
`hf` CLI) and then pushes — no need to pre-create it. For a `mode: database` survey
with a real `.env` alongside it, the same command also provisions the database
Secrets on the Space (see the Agent workflow section).

(When the skill is installed, the script is at
`~/.claude/skills/surveydown-skill/deploy-hugging-face/deploy.sh`.)

The Space name is yours to choose; the survey loads at
`https://<owner>-<space>.hf.space`.

### Display title vs. URL slug

A Space has two distinct names:

- **URL slug** — the `<owner>/<name>` you pass to `--space`. It defines the URL
  (`https://<owner>-<name>.hf.space`) and must be URL-safe (lowercase, dashes).
  Changing it later (Space → Settings → *Rename or transfer*) **changes the URL**.
- **Display title** — the heading on the Space card. By default it's the slug in
  Title Case (`questions-yml` → "Questions Yml"). Pass `--title "Any Text"` to set
  it to anything (spaces and punctuation allowed); the **URL is unaffected**.

Because the README (which carries the title) is *generated* on every deploy, set
the title with `--title` rather than hand-editing it on Hugging Face — otherwise
the next deploy overwrites your edit.

## How the generator works

For the survey directory, `deploy.sh`:

1. Copies the survey's runtime files (`app.R`, `survey.qmd`, and any `images/`,
   `data/`, `www/`, `*.yml`, etc.), excluding build artifacts and dev junk
   (`_survey/`, `preview_data.csv`, `rsconnect/`, `.git/`, `*.Rproj`, …).
2. Adds the shared `assets/Dockerfile`, a generated `README.md` (with Hugging Face
   frontmatter), and a generated `packages.txt`.
3. Creates the Space if it doesn't exist (Docker SDK, via the `hf` CLI), then
   uploads the result with `hf upload` (the Hub HTTP API, `--delete "*"` to replace
   contents), which auto-rebuilds. Upload authenticates as the **active** `hf`
   login — not via git — so deploying under a different account is just
   `hf auth switch` away, with no stale OS git credential to trip over.
4. If the survey is in `mode: database` and a real `.env` is next to it, syncs the
   `SD_*` credentials to the Space as Secrets (via `set-secrets.sh`). Skipped for
   `local`/`preview` mode, when there's no `.env`, or with `--no-secrets`.
   Placeholder values are refused, and a failure here is a warning, not fatal.
5. With `--wait`, polls the Space's runtime stage until `RUNNING` and reports the
   live URL + HTTP status (otherwise it returns right after the push, while the
   build continues on Hugging Face).

A first build typically takes a **few minutes** (~2–5 min): the `rocker` base image
plus Posit Public Package Manager binaries make R-package install fast. If a build
errors, check the logs at `https://huggingface.co/spaces/<owner>/<name>?logs=build`.

`packages.txt` may be **empty** — that's normal. A survey that only uses
`surveydown` (e.g. one driven by a `questions.yml`) needs no extra R packages;
`surveydown` and `shiny` are installed by the Dockerfile regardless.

`_survey/` is **not** shipped — the container renders the survey at startup
(Quarto is in the image). This keeps the Space lean and avoids shipping a stale
build (your `survey.qmd` stays the single source of truth).

### One shared Dockerfile

`assets/Dockerfile` is the same for every survey. The R packages a given survey
needs are written to `packages.txt` (derived from its `library()`/`require()`
calls), so there is one Dockerfile to maintain. surveydown installs from GitHub
(dev v1.3.0; CRAN only has 1.0.1). The Quarto CLI is pinned to a direct download
URL (the GitHub API gets rate-limited / 403 on build servers). A survey needing an
unusual system library may need a one-line edit to the Dockerfile.

## Files (in this folder)

| File | Purpose |
|------|---------|
| `deploy.sh` | Build + push generator |
| `set-secrets.sh` | Push DB credentials from `.env` to the Space as Secrets (never prints values) |
| `assets/Dockerfile` | Shared Dockerfile used by every Space |
| `assets/dockerignore` | Copied into each Space as `.dockerignore` |
| `assets/space-readme.template.md` | README template (HF frontmatter) for each Space |
