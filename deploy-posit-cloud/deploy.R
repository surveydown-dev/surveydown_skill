#!/usr/bin/env Rscript
#
# deploy.R — the R workhorse behind deploy.sh for Posit Connect Cloud.
#
# You normally do not call this directly; run deploy.sh, which validates inputs,
# resolves the account, and hands the settings to this script via SD_PC_* env
# vars. Everything here uses rsconnect (the deploy) plus the Connect Cloud REST
# API at api.connect.posit.cloud (the display title and custom URL), reusing the
# OAuth token that rsconnect stores after a one-time connectCloudUser() login —
# so the token is never printed, passed on a command line, or written to a file.
#
# Reads these environment variables (set by deploy.sh):
#   SD_PC_DIR      survey directory (absolute)                         (required)
#   SD_PC_ACCOUNT  connect.posit.cloud account name                    (required)
#   SD_PC_NAME     content name / rsconnect appName (stable id)        (required)
#   SD_PC_TITLE    display title (any text, spaces ok)                 (required)
#   SD_PC_SLUG     vanity name -> <account>-<slug>.share.connect...    (may be "")
#   SD_PC_MODE     survey mode read from survey.qmd (preview/database) (required)
#   SD_PC_SECRETS  "true"/"false" — push SD_* DB secrets in db mode
#   SD_PC_VANITY   "true"/"false" — set the custom URL from SD_PC_SLUG
#   SD_PC_VERIFY   "true"/"false" — curl the live URL and report status

suppressWarnings(suppressMessages({
  library(rsconnect)
}))

API <- "https://api.connect.posit.cloud/v1"
SERVER <- "connect.posit.cloud"

cfg <- list(
  dir     = Sys.getenv("SD_PC_DIR"),
  account = Sys.getenv("SD_PC_ACCOUNT"),
  name    = Sys.getenv("SD_PC_NAME"),
  title   = Sys.getenv("SD_PC_TITLE"),
  slug    = Sys.getenv("SD_PC_SLUG"),
  mode    = Sys.getenv("SD_PC_MODE", "preview"),
  secrets = !identical(Sys.getenv("SD_PC_SECRETS"), "false"),
  vanity  = !identical(Sys.getenv("SD_PC_VANITY"), "false"),
  verify  = !identical(Sys.getenv("SD_PC_VERIFY"), "false")
)

die  <- function(...) { cat("    ! ", sprintf(...), "\n", sep = "", file = stderr()); quit(status = 1) }
note <- function(...) cat("    ", sprintf(...), "\n", sep = "")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---- Survey files to bundle ---------------------------------------------------
# rsconnect does NOT honour .gitignore, so we pass an explicit allow-list: every
# file under the survey dir minus build artifacts, dev junk, and SECRETS (.env /
# .Renviron must never leave the machine). Mirrors the HF/Cloud Run excludes.
survey_files <- function(dir) {
  # NOTE: _survey/ IS shipped (the pre-rendered cache) so Connect Cloud cold starts
  # import it instead of re-running Quarto every time. survey_files/ (Quarto's
  # intermediate output dir) is not needed — survey.html is self-contained.
  excl_dirs  <- c(".git", "survey_files", "rsconnect", ".posit",
                  ".Rproj.user", ".Ruserdata")
  excl_files <- c(".gitignore", ".gitattributes", ".env", ".Renviron",
                  "preview_data.csv", "local_data.csv",
                  "manifest.json", ".DS_Store")
  # Drop the stray ROOT-level survey.html (a render artifact), but keep
  # _survey/survey.html — so this must be path-specific, not basename-based.
  excl_paths <- c("survey.html")
  all <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  keep <- vapply(all, function(p) {
    segs <- strsplit(p, "/", fixed = TRUE)[[1]]
    if (any(segs %in% excl_dirs)) return(FALSE)
    if (p %in% excl_paths) return(FALSE)
    base <- basename(p)
    if (base %in% excl_files) return(FALSE)
    if (endsWith(base, ".Rproj")) return(FALSE)
    TRUE
  }, logical(1))
  unname(all[keep])
}

# ---- Connect Cloud REST helpers (reuse rsconnect's stored OAuth token) ---------
auth_token <- function(account) {
  ai <- tryCatch(rsconnect:::accountInfo(account, SERVER), error = function(e) NULL)
  if (is.null(ai) || is.null(ai$accessToken) || !nzchar(ai$accessToken)) {
    die("no Connect Cloud token for account '%s'. Run rsconnect::connectCloudUser() once.", account)
  }
  ai$accessToken
}

api <- function(method, path, token, body = NULL) {
  h <- curl::new_handle()
  hdr <- c(Authorization = paste("Bearer", token), Accept = "application/json")
  if (!is.null(body)) hdr <- c(hdr, "Content-Type" = "application/json")
  do.call(curl::handle_setheaders, c(list(h), as.list(hdr)))
  if (!identical(method, "GET")) curl::handle_setopt(h, customrequest = method)
  if (!is.null(body)) curl::handle_setopt(h, postfields = body)
  r <- curl::curl_fetch_memory(paste0(API, path), handle = h)
  txt <- rawToChar(r$content)
  list(status = r$status_code,
       body = tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                       error = function(e) txt))
}

http_status <- function(url, tries = 8, wait = 4) {
  for (i in seq_len(tries)) {
    code <- tryCatch({
      h <- curl::new_handle(); curl::handle_setopt(h, nobody = TRUE, followlocation = TRUE, timeout = 30L)
      curl::curl_fetch_memory(url, handle = h)$status_code
    }, error = function(e) 0L)
    if (code == 200L) return(code)
    if (i < tries) Sys.sleep(wait)
  }
  code
}

# ---- Validate -----------------------------------------------------------------
if (!nzchar(cfg$dir) || !file.exists(file.path(cfg$dir, "app.R")))
  die("survey directory invalid (no app.R): %s", cfg$dir)
accts <- rsconnect::accounts()
if (!any(accts$name == cfg$account & accts$server == SERVER))
  die("account '%s' is not registered for %s. Run rsconnect::connectCloudUser().", cfg$account, SERVER)

# ---- Database secrets ---------------------------------------------------------
# In database mode, load SD_* from the survey's .env into this process so
# deployApp(envVars=) ships them to Connect Cloud as content secrets (write-only).
# .env itself is never bundled. Placeholder values are refused.
env_vars <- character(0)
if (cfg$secrets && identical(cfg$mode, "database")) {
  envf <- file.path(cfg$dir, ".env")
  keys <- c("SD_HOST", "SD_PORT", "SD_DBNAME", "SD_USER", "SD_TABLE", "SD_PASSWORD")
  hints <- c("your-", "example", "changeme", "<", "placeholder", "xxxx")
  if (file.exists(envf)) {
    vals <- list()
    for (ln in readLines(envf, warn = FALSE)) {
      ln <- trimws(ln)
      if (!nzchar(ln) || startsWith(ln, "#") || !grepl("=", ln)) next
      kv <- strsplit(ln, "=", fixed = TRUE)[[1]]
      vals[[trimws(kv[1])]] <- gsub("^['\"]|['\"]$", "", trimws(paste(kv[-1], collapse = "=")))
    }
    present <- keys[vapply(keys, function(k) nzchar(vals[[k]] %||% ""), logical(1))]
    stubs <- present[vapply(present, function(k) any(grepl(paste(hints, collapse = "|"), tolower(vals[[k]]))), logical(1))]
    if (length(stubs))
      die("refusing to push placeholder secrets: %s. Fill real values in %s.", paste(stubs, collapse = ", "), envf)
    if (length(present)) {
      do.call(Sys.setenv, vals[present])
      env_vars <- present
      note("database mode — shipping %d DB secret(s) from .env: %s", length(present), paste(present, collapse = ", "))
    }
  } else {
    note("database mode but no .env in %s — deploying without DB credentials.", cfg$dir)
  }
}

# ---- 0. Rebuild the _survey/ cache (delete + re-render) -----------------------
# Ship a freshly rendered _survey/ so Connect Cloud cold starts IMPORT the cache
# instead of re-running Quarto every time. DELETE any existing _survey/ first, then
# regenerate the full 5-file cache headlessly: sd_ui() writes survey.html +
# head.rds + settings.yml (the render); run_config() adds pages.rds + questions.yml
# (the parse). Output is discarded. (Literally launching app.R would block and only
# write 3 of the 5 files without a browser session; this is the headless equivalent.)
note("rebuilding _survey/ cache (delete + re-render) ...")
gen <- tempfile(fileext = ".R")
writeLines(c(
  sprintf("setwd(%s)", shQuote(cfg$dir)),
  "if (!requireNamespace('surveydown', quietly = TRUE)) quit(status = 2)",
  "unlink('_survey', recursive = TRUE)",
  "suppressMessages(suppressWarnings(library(surveydown)))",
  "invisible(sd_ui())",
  "surveydown:::run_config()"
), gen)
status <- system2("Rscript", gen, stdout = FALSE, stderr = FALSE)
unlink(gen)
sv <- list.files(file.path(cfg$dir, "_survey"))
if (status == 2L) die("the 'surveydown' package is not installed — cannot pre-render _survey/. install.packages it (or pak::pak the dev version).")
if (length(sv)) {
  note("_survey/ ready (%d files): %s", length(sv), paste(sv, collapse = ", "))
} else {
  note("! _survey/ was not generated; cold starts will re-render until it is.")
}

# ---- 1. Deploy (with a transient managed .Rprofile) --------------------------
# The shipped _survey/ alone is not enough: on each cold-start unpack the cache
# files get fresh, jittery mtimes, so surveydown's strict-`>` staleness checks
# fire non-deterministically (sometimes render, sometimes re-parse). A managed
# .Rprofile — copied from the skill's assets ONLY for this deploy — stamps every
# _survey/ file to one identical "now" at startup, making the import deterministic.
# It is added to the bundle, then REMOVED from the working copy (failure-safe), so
# it never lingers locally to mask your survey.qmd edits during development.
note("deploying '%s' to %s / %s ...", cfg$name, SERVER, cfg$account)
skill_dir <- tryCatch(
  dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))),
  error = function(e) ".")
asset_rp <- file.path(skill_dir, "assets", "Rprofile")
rp <- file.path(cfg$dir, ".Rprofile")
MARK_BEGIN <- "# >>> surveydown-deploy: transient cache stamp (auto-added, removed after deploy) >>>"
MARK_END   <- "# <<< surveydown-deploy <<<"
existing <- if (file.exists(rp)) readLines(rp, warn = FALSE) else character(0)
b <- which(existing == MARK_BEGIN); e <- which(existing == MARK_END)
if (length(b) && length(e)) existing <- existing[-(b[1]:e[length(e)])]  # strip any stale block
had_user <- any(nzchar(existing))
block <- if (file.exists(asset_rp)) readLines(asset_rp, warn = FALSE) else
  "local({ if (dir.exists('_survey')) { n<-Sys.time(); for (f in list.files('_survey', full.names=TRUE, recursive=TRUE)) try(Sys.setFileTime(f,n), silent=TRUE) } })"
writeLines(c(if (had_user) c(existing, ""), MARK_BEGIN, block, MARK_END), rp)
restore_rprofile <- function() { if (had_user) writeLines(existing, rp) else unlink(rp) }

files <- survey_files(cfg$dir)
deploy_err <- tryCatch({
  deployApp(
    appDir         = cfg$dir,
    appFiles       = files,
    appPrimaryDoc  = "app.R",
    appName        = cfg$name,
    appTitle       = cfg$title,
    account        = cfg$account,
    server         = SERVER,
    envVars        = if (length(env_vars)) env_vars else NULL,
    forceUpdate    = TRUE,
    launch.browser = FALSE,
    lint           = FALSE,
    logLevel       = "normal"
  )
  NULL
}, error = function(e) e)
restore_rprofile()
if (!is.null(deploy_err)) stop(deploy_err)

# ---- 2. Resolve the content GUID ---------------------------------------------
dep <- rsconnect::deployments(cfg$dir, nameFilter = cfg$name)
dep <- dep[dep$server == SERVER & dep$account == cfg$account, , drop = FALSE]
guid <- if (nrow(dep)) dep$appId[[1]] else die("could not resolve content GUID after deploy.")
token <- auth_token(cfg$account)

# ---- 3. Display title + public access ----------------------------------------
res <- api("PATCH", paste0("/contents/", guid), token,
           jsonlite::toJSON(list(title = cfg$title, access = "public"), auto_unbox = TRUE))
if (res$status >= 300) note("! title/access update returned HTTP %s", res$status) else note("title set: %s", cfg$title)

# ---- 4. Custom URL (vanity) ---------------------------------------------------
# The vanity is set on the CONTENT, but the live route is tied to the published
# REVISION. Setting vanity_name on already-published content does not re-point the
# active revision — a republish is required (the UI's "Republish" button). So:
# PATCH the vanity, and if the active revision still serves the default URL,
# republish and wait until the new revision serves the vanity.
default_url <- paste0("https://", guid, ".share.connect.posit.cloud/")
public_url  <- default_url
if (cfg$vanity && nzchar(cfg$slug)) {
  body <- jsonlite::toJSON(list(vanity_name = cfg$slug, domain_id = NA), auto_unbox = TRUE, na = "null")
  v <- api("PATCH", paste0("/contents/", guid), token, body)
  if (v$status != 200L) {
    msg <- if (is.list(v$body)) v$body$error %||% "" else ""
    note("! custom URL not set (HTTP %s) %s — keeping the default URL.", v$status, msg)
  } else {
    vdom <- v$body$vanity_domain
    public_url <- paste0("https://", vdom, ".share.connect.posit.cloud/")
    note("custom URL set: %s", public_url)
    cur <- api("GET", paste0("/contents/", guid), token)$body$current_revision
    if (is.null(cur$url) || !grepl(vdom, cur$url, fixed = TRUE)) {
      note("republishing so the custom URL goes live ...")
      rp <- api("POST", paste0("/contents/", guid, "/republish"), token, "{}")
      if (rp$status >= 300) {
        note("! republish returned HTTP %s — custom URL may lag; the default URL works.", rp$status)
      } else {
        ok <- FALSE
        for (i in 1:40) {  # up to ~2 min
          Sys.sleep(3)
          cr <- api("GET", paste0("/contents/", guid), token)$body$current_revision
          if (isTRUE(cr$publish_result == "success") && !is.null(cr$url) && grepl(vdom, cr$url, fixed = TRUE)) { ok <- TRUE; break }
          if (isTRUE(cr$publish_result == "failure")) { note("! republish failed — the default URL works."); break }
        }
        if (ok) note("custom URL live after republish.")
        else    note("! custom URL not confirmed within the wait window; the default URL works.")
      }
    }
  }
}

# ---- 5. Free-tier slot count (best effort) -----------------------------------
acctId <- tryCatch(rsconnect:::accountInfo(cfg$account, SERVER)$accountId, error = function(e) "")
tryCatch({
  if (!is.null(acctId) && nzchar(acctId)) {
    lst <- api("GET", paste0("/contents?account_id=", acctId, "&limit=100&include_total=true"), token)
    apps <- Filter(function(c) {
      cr <- c$current_revision; !is.null(cr) && !is.null(cr$app_mode) &&
        cr$app_mode %in% c("shiny", "shiny-rmd", "python-shiny", "python-dash", "python-streamlit", "python-bokeh", "python-fastapi", "api", "tensorflow-saved-model")
    }, lst$body$data %||% list())
    note("free-tier usage: %d/5 application slot(s) on account '%s'.", length(apps), cfg$account)
  }
}, error = function(e) invisible(NULL))

# ---- 6. Verify ----------------------------------------------------------------
dashboard <- sprintf("https://connect.posit.cloud/%s/content/%s", cfg$account, guid)
if (cfg$verify) {
  note("verifying %s ...", public_url)
  code <- http_status(public_url)
  note("live -> %s  (HTTP %s)", public_url, code)
  if (code != 200L && !identical(public_url, default_url))
    note("  (if the custom URL lags, the default URL %s serves immediately.)", default_url)
}

cat("\n")
note("deployed   : %s", cfg$title)
note("public URL : %s", public_url)
note("dashboard  : %s", dashboard)
