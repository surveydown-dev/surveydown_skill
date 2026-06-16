# Deploy a surveydown survey to Google Cloud Run

Deploy **any** surveydown survey to **Google Cloud Run** (Docker). The generator
script (`deploy.sh`) and shared assets live in this folder. Your survey directory
is the source of truth; the tooling only *generates* the Cloud Run packaging and
deploys it.

## Why Cloud Run

Each survey becomes its **own Cloud Run service** — there's **no per-account app
cap** (unlike Hugging Face's ~3 concurrent or shinyapps.io/Connect Cloud's 5).
Services **scale to zero** when idle, so an unused survey costs ≈ $0, and the
usage-based free tier (2M requests, 360k vCPU-seconds, 180k GiB-seconds per month)
covers low-traffic research surveys.

Trade-offs to know:
- **A billing account (card) is required** on the GCP project, even though usage
  stays free within the tier. Set a $1 budget alert for peace of mind.
- **Cold starts:** an idle service sleeps and takes ~10-40s to wake on the next
  visit (it boots R + renders the survey).
- **URLs carry a project token** you can't remove: `https://<service>-<project
  number>.<region>.run.app`. You choose `<service>` (the slug); the rest is fixed.
  For a clean hostname, map a custom domain (free domain mapping, or a paid load
  balancer) — see Google's docs.
- **Sessions cap at 60 min** (Cloud Run request timeout); fine for typical surveys.

## Prerequisites

- The **gcloud CLI**, logged in. Install: `brew install --cask google-cloud-sdk`
  (or <https://cloud.google.com/sdk/docs/install>), then `gcloud auth login` in a
  real terminal.
- A **GCP project with billing enabled** (`gcloud config set project <id>`; link a
  billing account in the Cloud Console).
- `rsync` (falls back to `cp`).

## Agent workflow (follow this when deploying for a user)

**First, once per session:** before the *first* Cloud Run deployment, show the
user the contents of [`caveat.md`](caveat.md) (billing-card requirement, why it's
usually free, when it can cost money, and the suggested $1 budget alert). Show it
**only once** — if deploying many surveys in one go, do not repeat it.

Then settle these with the user **before** running `deploy.sh` — do not assume any.

### A. Survey configuration — ALWAYS ASK BOTH

Same two critical `survey.qmd` settings as every host. Ask both, then edit the
`survey-settings:` block to match (an authoring step done with the user's consent).

1. **Mode** — `local` / `preview` / `database` (see the Hugging Face section for
   the one-line descriptions). For real data on Cloud Run use **`database`** — the
   local CSVs of `preview`/`local` live on the container's ephemeral disk and are
   lost when it scales to zero or restarts.
   - **If `database`:** the `SD_*` credentials are stored in **Google Secret
     Manager** and wired into the service. The flow (handled automatically by
     `deploy.sh` when a real `.env` is present):
     1. Locally: `surveydown::sd_db_config()` (or edit `.env`) → `SD_HOST`,
        `SD_PORT`, `SD_DBNAME`, `SD_USER`, `SD_TABLE`, `SD_PASSWORD`. The `.env`
        is git-ignored and never shipped.
     2. `set-secrets.sh` stores them in Secret Manager (values never printed,
        placeholders refused) **and grants the Cloud Run runtime service account
        the `secretmanager.secretAccessor` role** on each (otherwise the revision
        fails with "Permission denied on secret …"); the deploy references them
        with `--set-secrets`. Don't ask the user to paste credentials into chat.

2. **Cookies** — "Do you want to use cookies?" **yes** (`use-cookies: true`,
   per-browser resume) / **no** (`use-cookies: false`, fresh each load). Set it in
   `survey.qmd`.

### B. Deployment target — confirm before deploying

3. **URL slug** = the **Cloud Run service name** — ask the user. It's the leading
   label of the URL (`https://<slug>-<projectnumber>.<region>.run.app`). Must be
   lowercase letters/digits/hyphens, start with a letter. Propose one from the
   survey/folder name (e.g. `surveydown-default`) and let them accept or change it.
   There is **no separate display title** on Cloud Run (unlike a Hugging Face
   Space card), so slug is the only name to choose.
4. **Project & region** — confirm the target **GCP project** (it determines
   billing *and* appears in the URL) and **region** (default `us-central1`). Show
   the active project (`gcloud config get-value project`) and let the user confirm
   or override with `--project` / `--region`.

## Usage

```bash
# from inside your survey folder:
/path/to/deploy-google-cloud/deploy.sh --service my-survey

# point at the survey explicitly, choose project/region:
/path/to/deploy-google-cloud/deploy.sh --service my-survey \
  --dir ~/surveys/my-survey --project my-gcp-project --region us-central1

# heavier templates (leaflet/plotly) may need more memory:
/path/to/deploy-google-cloud/deploy.sh --service my-survey --memory 2Gi

# database mode also stores .env's SD_* in Secret Manager and wires them in;
# use --no-secrets to skip that.
```

`gcloud run deploy` is synchronous — it waits for the service to be healthy, so
there's no separate `--wait`. On success the script prints **two links**:
1. the live survey URL in the **canonical project-number form**
   (`https://<service>-<projectnumber>.<region>.run.app`) — the same URL the Cloud
   Run console shows (not the legacy `…-<hash>-<regioncode>.a.run.app` alias); and
2. the **Cloud Run dashboard** link for the service
   (`https://console.cloud.google.com/run/detail/<region>/<service>/metrics?project=<project>`).

## How the generator works

1. Copies the survey's runtime files (excluding build artifacts, dev junk, and
   secrets like `.env`/`.Renviron`).
2. Adds the shared `assets/Dockerfile`, `assets/start.sh`, and a generated
   `packages.txt`.
3. `gcloud run deploy --source` → Cloud Build builds the image, Cloud Run serves
   it (public, scale-to-zero, single instance + session affinity, 60-min timeout).
4. Database mode: stores `SD_*` in Secret Manager (via `set-secrets.sh`) and
   references them with `--set-secrets`. Skipped for `local`/`preview`, when
   there's no `.env`, or with `--no-secrets`.

### The read-only filesystem fix

Cloud Run mounts the image filesystem **read-only**, but surveydown renders the
survey into `_survey/` next to the app **at startup, in every mode** (it's the
rendered UI, not data). So `start.sh` copies the app into writable **`/tmp`** and
runs from there, pointing `HOME`/caches at `/tmp` too. Without this the container
exits with `EACCES … _survey` before binding the port.

## Files (in this folder)

| File | Purpose |
|------|---------|
| `deploy.sh` | Build context generator + `gcloud run deploy` |
| `set-secrets.sh` | Store DB credentials from `.env` in Secret Manager (never prints values) |
| `caveat.md` | Billing-card requirement + cost caveat + $1 budget — show once per session |
| `assets/Dockerfile` | Shared Cloud Run Dockerfile (listens on `$PORT`) |
| `assets/start.sh` | Runs the app from writable `/tmp` (read-only-fs fix) |
| `assets/dockerignore` | Copied into the build context as `.dockerignore` |
