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
  excl_dirs  <- c(".git", "_survey", "survey_files", "rsconnect", ".posit",
                  ".Rproj.user", ".Ruserdata")
  excl_files <- c(".gitignore", ".gitattributes", ".env", ".Renviron",
                  "survey.html", "preview_data.csv", "local_data.csv",
                  "manifest.json", ".DS_Store")
  all <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  keep <- vapply(all, function(p) {
    segs <- strsplit(p, "/", fixed = TRUE)[[1]]
    if (any(segs %in% excl_dirs)) return(FALSE)
    base <- basename(p)
    if (base %in% excl_files) return(FALSE)
    if (grepl("\\.Rproj$", base)) return(FALSE)
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

# ---- 1. Deploy ----------------------------------------------------------------
note("deploying '%s' to %s / %s ...", cfg$name, SERVER, cfg$account)
files <- survey_files(cfg$dir)
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
default_url <- paste0("https://", guid, ".share.connect.posit.cloud/")
public_url  <- default_url
if (cfg$vanity && nzchar(cfg$slug)) {
  body <- jsonlite::toJSON(list(vanity_name = cfg$slug, domain_id = NA), auto_unbox = TRUE, na = "null")
  v <- api("PATCH", paste0("/contents/", guid), token, body)
  if (v$status == 200L) {
    public_url <- paste0("https://", v$body$vanity_domain, ".share.connect.posit.cloud/")
    note("custom URL set: %s", public_url)
  } else {
    msg <- if (is.list(v$body)) v$body$error %||% "" else ""
    note("! custom URL not set (HTTP %s) %s — keeping the default URL.", v$status, msg)
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
