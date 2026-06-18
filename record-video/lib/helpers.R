# Browser-driving helpers for recording surveydown walkthroughs.
#
# Adapted from the surveydown source-code test helpers
# (tests/manual/helpers.R). The interactive input drivers (click, set_text,
# set_select, set_slider*, set_date*, ...) are reused verbatim because they
# mimic real user behavior on every surveydown question type. The only
# substantive change is the browser connection: instead of chromote's
# default HEADLESS session, we launch a VISIBLE Chrome ourselves and attach
# chromote to it via ChromeRemote, so an OS screen recorder can film it.
# (chromote 0.5.1 cannot launch Chrome headed on its own.)

library(chromote)

# --- Globals shared across helpers ------------------------------------------

b <- NULL # the active ChromoteSession (the driven tab)
chromote_obj <- NULL # the Chromote connection to our headed browser
chrome_profile <- NULL # the throwaway --user-data-dir we launched Chrome with

CHROME_BIN <- "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

shot_dir <- file.path(tempdir(), "sd_record_shots")
dir.create(shot_dir, showWarnings = FALSE, recursive = TRUE)

app_url <- function(port) sprintf("http://127.0.0.1:%d/", port)

# --- Global time factor -----------------------------------------------------
# All demo-pacing pauses below run through pause(), which scales them by a
# global time factor. 1.0 = baseline pacing; 0.8 (the default) is ~20%
# quicker while keeping motion smooth. Functional waits (page load, ffmpeg
# init, polling loops) use Sys.sleep() directly and are NOT scaled.
# Override per run via the SD_TIME_FACTOR global or environment variable.
sd_time_factor <- function() {
  v <- suppressWarnings(as.numeric(get0("SD_TIME_FACTOR", ifnotfound = NA_real_)))
  if (is.na(v)) {
    e <- Sys.getenv("SD_TIME_FACTOR", "")
    v <- if (nzchar(e)) suppressWarnings(as.numeric(e)) else NA_real_
  }
  if (is.na(v) || v <= 0) 0.8 else v
}

# Sleep for `seconds` scaled by the global time factor.
pause <- function(seconds) Sys.sleep(seconds * sd_time_factor())

# --- Survey app lifecycle ---------------------------------------------------

# Launch a surveydown app in a background R process and wait until it
# responds. The first run renders survey.qmd, which can take ~60s.
launch_app <- function(app_dir, port, clean = TRUE) {
  if (!dir.exists(app_dir)) {
    stop("Survey app not found at ", app_dir)
  }
  # Kill any stale app holding this port, otherwise the new app fails to
  # bind and we silently talk to the zombie process.
  system(sprintf("pkill -f 'shiny::runApp.*%d'", port), ignore.stderr = TRUE)
  Sys.sleep(1)

  if (clean) {
    # Start clean: stale artifacts contaminate the recording (e.g. an old
    # _survey/ cache carries content from a previous package version).
    unlink(file.path(app_dir, "_survey"), recursive = TRUE)
    unlink(file.path(app_dir, "preview_data.csv"))
    unlink(file.path(app_dir, "local_data.csv"))
    unlink(file.path(app_dir, "survey_files"), recursive = TRUE)
  }

  cat("Launching survey app from", app_dir, "...\n")
  system(sprintf(
    "Rscript -e 'shiny::runApp(\"%s\", port = %d)' > /tmp/sd_record_app.log 2>&1 &",
    normalizePath(app_dir), port
  ))
  up <- FALSE
  for (i in 1:60) {
    up <- tryCatch(
      {
        suppressWarnings(readLines(app_url(port), n = 1))
        TRUE
      },
      error = function(e) FALSE
    )
    if (up) break
    Sys.sleep(3)
  }
  if (!up) stop("Survey app did not start. See /tmp/sd_record_app.log")
  cat("Survey app is up at", app_url(port), "\n")
}

# --- Headed browser lifecycle -----------------------------------------------

# Launch a VISIBLE Chrome window with a DevTools debugging port, then attach
# chromote to it. Returns invisibly; sets chromote_obj / chrome_profile.
launch_browser <- function(debug_port = 9222, width = 1280, height = 720,
                           pos_x = 0, pos_y = 0) {
  if (!file.exists(CHROME_BIN)) {
    stop("Google Chrome not found at ", CHROME_BIN)
  }
  system(
    sprintf("pkill -f 'remote-debugging-port=%d'", debug_port),
    ignore.stderr = TRUE
  )
  Sys.sleep(1)

  chrome_profile <<- tempfile("sd-record-chrome-")
  cat("Launching headed Chrome on debug port", debug_port, "...\n")
  system2(
    CHROME_BIN,
    c(
      sprintf("--remote-debugging-port=%d", debug_port),
      "--remote-allow-origins=*", # required or the CDP websocket is rejected
      sprintf("--user-data-dir=%s", chrome_profile),
      sprintf("--window-size=%d,%d", width, height),
      sprintf("--window-position=%d,%d", pos_x, pos_y),
      "--no-first-run", "--no-default-browser-check",
      "--disable-extensions", "--disable-infobars",
      "--new-window", "about:blank"
    ),
    stdout = "/tmp/sd_record_chrome.log",
    stderr = "/tmp/sd_record_chrome.log",
    wait = FALSE
  )

  up <- FALSE
  for (i in 1:30) {
    up <- tryCatch(
      {
        suppressWarnings(readLines(
          sprintf("http://127.0.0.1:%d/json/version", debug_port),
          n = 1
        ))
        TRUE
      },
      error = function(e) FALSE
    )
    if (up) break
    Sys.sleep(0.5)
  }
  if (!up) stop("Chrome debug endpoint never came up. See /tmp/sd_record_chrome.log")

  chromote_obj <<- Chromote$new(
    browser = ChromeRemote$new(host = "127.0.0.1", port = debug_port)
  )
  cat("Headed Chrome is up and chromote is attached.\n")
  invisible(TRUE)
}

# Open the survey in a new tab of our headed browser and bring it to the
# front so the screen recorder films it (not the about:blank launch tab).
new_session <- function(port, wait = 6) {
  b <<- chromote_obj$new_session()
  # Optional query string (e.g. survey URL parameters) via SD_URL_QUERY, so it
  # is present when the Shiny session connects (sd_get_url_pars reads it once).
  url <- app_url(port)
  q <- Sys.getenv("SD_URL_QUERY", "")
  if (nzchar(q)) url <- paste0(url, q)
  b$Page$navigate(url)
  try(b$Page$bringToFront(), silent = TRUE)

  # chromote applies a default 992px device-metrics emulation, which renders
  # the page narrower than the real window and leaves white space on the
  # right of the recording. Clear it so the page fills the actual window.
  try(b$Emulation$clearDeviceMetricsOverride(), silent = TRUE)

  # Close the leftover about:blank launch tab so only the survey tab shows.
  try(
    {
      infos <- b$Target$getTargets()$targetInfos
      for (t in infos) {
        url <- if (is.null(t$url)) "" else t$url
        if (isTRUE(t$type == "page") && startsWith(url, "about:blank")) {
          b$Target$closeTarget(targetId = t$targetId)
        }
      }
    },
    silent = TRUE
  )

  Sys.sleep(wait) # let the survey page finish loading before injecting
  inject_cursor() # overlay arrow cursor + click ripple for the recording
}

# --- Demo cursor overlay ----------------------------------------------------

# Quote an arbitrary string as a JS double-quoted literal (selectors may
# themselves contain double quotes, e.g. input[name="fruit"]).
js_str <- function(s) paste0('"', gsub('"', '\\\\"', s, perl = TRUE), '"')

cursor_js_path <- function() {
  file.path(get0("SD_LIB_DIR", ifnotfound = "lib"), "cursor.js")
}

# Inject the overlay cursor (lib/cursor.js) into the current page.
inject_cursor <- function() {
  p <- cursor_js_path()
  if (!file.exists(p)) {
    cat("[note] cursor.js not found at", p, "- recording without cursor\n")
    return(invisible(FALSE))
  }
  js(paste(readLines(p, warn = FALSE), collapse = "\n"))
  invisible(TRUE)
}

# Glide the overlay cursor to an element's center (CSS animates the move),
# then wait out the glide so it is visible on camera.
cursor_to <- function(sel, glide = 0.65) {
  js(sprintf("window.__sdMove && window.__sdMove(%s)", js_str(sel)))
  pause(glide)
}

# Flash a click ripple at the cursor's current position.
cursor_click <- function(hold = 0.35) {
  js("window.__sdRipple && window.__sdRipple(); true")
  pause(hold)
}

# Scroll the element matching `sel` to the vertical center of the viewport so
# it (and any dropdown/cursor on it) is visible on camera. For visually hidden
# inputs (button groups, image cards) scroll a visible ancestor instead.
scroll_into_view <- function(sel) {
  js(sprintf(
    "var el=document.querySelector('%s');
     if(el){var r=el.getBoundingClientRect();
       var t=(r.width<2||r.height<2)?(el.closest('label,.btn,.form-check,.sd-image-card,.shiny-options-group,[id^=container-]')||el.parentElement||el):el;
       t.scrollIntoView({block:'center', behavior:'smooth'});}
     true",
    sel
  ))
}

# Wait for a smooth scroll to finish: poll the page scroll position until it
# stops changing, so the cursor lands at the element's FINAL location rather
# than chasing it mid-animation. Functional wait (not time-factor scaled).
wait_scroll_settled <- function(timeout = 2.5) {
  t0 <- Sys.time(); last <- NA_real_; stable <- 0
  repeat {
    Sys.sleep(0.1)
    cur <- suppressWarnings(as.numeric(js("Math.round(window.scrollY)")))
    if (!is.na(last) && !is.na(cur) && cur == last) {
      stable <- stable + 1
      if (stable >= 2) break
    } else {
      stable <- 0
    }
    last <- cur
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > timeout) break
  }
}

# Bring an input on camera before driving it: smooth-scroll it to center, wait
# for the scroll to settle, glide the cursor onto it, and flash a click ripple.
# `scroll_sel` defaults to `sel` but can target a container (e.g. for sliders
# the input itself is hidden).
approach <- function(sel, scroll_sel = sel) {
  scroll_into_view(scroll_sel)
  wait_scroll_settled()
  cursor_to(sel)
  cursor_click()
}

# Reload the current page (simulates a refresh)
reload <- function(wait = 8) {
  b$Page$reload()
  Sys.sleep(wait)
}

# --- JS execution + waiting -------------------------------------------------

js <- function(code) {
  b$Runtime$evaluate(code, returnByValue = TRUE)$result$value
}

wait_for <- function(sel, timeout = 20) {
  t0 <- Sys.time()
  while (as.numeric(difftime(Sys.time(), t0, units = "secs")) < timeout) {
    found <- js(sprintf("document.querySelector('%s') !== null", sel))
    if (isTRUE(found)) return(invisible(TRUE))
    Sys.sleep(0.3)
  }
  stop("Timeout waiting for: ", sel)
}

# --- Input drivers (one per surveydown question type) -----------------------
# These are reused verbatim from the surveydown test helpers.

click <- function(sel, wait = 1.2) {
  wait_for(sel)
  approach(sel)
  js(sprintf("document.querySelector('%s').click(); true", sel))
  pause(wait)
}

# Dispatch a real mousedown event (for handlers bound to mousedown rather
# than click, e.g. the numeric input's spinner buttons)
mousedown <- function(sel, wait = 1.2) {
  wait_for(sel)
  js(sprintf(
    "document.querySelector('%s').dispatchEvent(
       new MouseEvent('mousedown', {bubbles: true})
     );
     true",
    sel
  ))
  pause(wait)
}

set_text <- function(id, value, wait = 1.2) {
  wait_for(paste0("#", id))
  approach(paste0("#", id))
  js(sprintf(
    "var el = document.getElementById('%s');
     el.value = '%s';
     el.dispatchEvent(new Event('input',  {bubbles: true}));
     el.dispatchEvent(new Event('change', {bubbles: true}));
     true",
    id, value
  ))
  pause(wait)
}

# Set a select question (handles both selectize and plain select inputs).
# With show = TRUE (the default for recordings), the selectize dropdown is
# opened first so the options are visible on screen before one is picked.
set_select <- function(id, value, wait = 1.2, show = TRUE, show_pause = 1.0) {
  wait_for(paste0("#", id))
  if (show) {
    # 1. Center the question so its dropdown isn't clipped by the footer.
    js(sprintf(
      "(document.getElementById('container-%s') || $('#%s')[0]).scrollIntoView({block:'center', behavior:'smooth'}); true",
      id, id
    ))
    wait_scroll_settled()
    # 2. Move the cursor onto the control and open the dropdown.
    cursor_to(sprintf("#container-%s .selectize-input", id))
    cursor_click()
    js(sprintf(
      "var s = $('#%s')[0].selectize; if (s) { s.focus(); s.open(); } true", id
    ))
    pause(show_pause)
    # 3. Move the cursor onto the chosen option and highlight it, so the
    #    viewer sees which option is picked before the dropdown closes.
    opt <- sprintf("#container-%s .selectize-dropdown [data-value=\"%s\"]", id, value)
    js(sprintf(
      "(function(){var o=document.querySelector(%s);
         if(o){o.classList.add('sd-rec-pick'); o.scrollIntoView({block:'nearest'});}
         return !!o;})()",
      js_str(opt)
    ))
    cursor_to(opt)
    pause(0.9)
    cursor_click()
  }
  js(sprintf(
    "var el = $('#%s')[0];
     if (el.selectize) { el.selectize.setValue('%s'); el.selectize.close(); el.selectize.blur(); }
     else { $(el).val('%s').trigger('change'); }
     true",
    id, value, value
  ))
  pause(wait)
}

# Set a text slider (type = 'slider') to the 1-based position among its options
set_slider <- function(id, position, wait = 1.2) {
  wait_for(paste0("#", id))
  approach(paste0("#container-", id))
  js(sprintf(
    "var $el = $('#%s');
     $el.data('ionRangeSlider').update({from: %d});
     $el.trigger('change');
     true",
    id, position - 1
  ))
  pause(wait)
}

# Set a numeric slider (type = 'slider_numeric') to the given value
set_slider_numeric <- function(id, value, wait = 1.2) {
  wait_for(paste0("#", id))
  approach(paste0("#container-", id))
  js(sprintf(
    "var $el = $('#%s');
     $el.data('ionRangeSlider').update({from: %s});
     $el.trigger('change');
     true",
    id, value
  ))
  pause(wait)
}

# Set a numeric range slider (type = 'slider_numeric' with a length-2 default)
set_slider_range <- function(id, from, to, wait = 1.2) {
  wait_for(paste0("#", id))
  approach(paste0("#container-", id))
  js(sprintf(
    "var $el = $('#%s');
     $el.data('ionRangeSlider').update({from: %s, to: %s});
     $el.trigger('change');
     true",
    id, from, to
  ))
  pause(wait)
}

# Set a date question (type = 'date') to 'yyyy-mm-dd'.
set_date <- function(id, value, wait = 1.2) {
  wait_for(paste0("#", id, " input"))
  approach(paste0("#", id, " input"))
  js(sprintf(
    "var $inp = $('#%s input').first();
     if ($inp.bsDatepicker) { $inp.bsDatepicker('update', '%s'); }
     else { $inp.val('%s'); }
     $inp.trigger('changeDate');
     true",
    id, value, value
  ))
  pause(wait)
}

# Set a date range question (type = 'daterange') to 'yyyy-mm-dd' start/end
set_daterange <- function(id, start, end, wait = 1.2) {
  wait_for(paste0("#", id, " input"))
  approach(paste0("#", id, " input"))
  js(sprintf(
    "var inps = $('#%s input');
     var vals = ['%s', '%s'];
     inps.each(function(i) {
       var $inp = $(this);
       if ($inp.bsDatepicker) { $inp.bsDatepicker('update', vals[i]); }
       else { $inp.val(vals[i]); }
       $inp.trigger('changeDate');
     });
     true",
    id, start, end
  ))
  pause(wait)
}

# --- Observation helpers ----------------------------------------------------

# Returns TRUE if the question container is visible
visible <- function(id) {
  wait_for(paste0("#container-", id))
  disp <- js(sprintf(
    "getComputedStyle(document.querySelector('#container-%s')).display", id
  ))
  disp != "none"
}

# Returns TRUE if an element matching the selector exists in the DOM
present <- function(sel) {
  isTRUE(js(sprintf("document.querySelector('%s') !== null", sel)))
}

# Returns TRUE if the page body text contains the given string
body_has <- function(text) {
  isTRUE(js(sprintf("document.body.innerText.includes('%s')", text)))
}

# Dismiss a SweetAlert popup (used for stop_if and required-question warnings)
dismiss_alert <- function(wait = 1) {
  js("var btn = document.querySelector('.swal2-confirm'); if (btn) btn.click(); true")
  pause(wait)
}

# Screenshot the page (offline debugging only). WARNING: do NOT call while
# recording -- chromote applies a device-metrics override to capture, which
# briefly reflows the page to a tiny emulated viewport and blinks the video.
shot <- function(name) {
  path <- file.path(shot_dir, name)
  b$screenshot(path)
  path
}

# Compute an ffmpeg crop rectangle ("w:h:x:y", in device pixels) that bounds
# just the headed Chrome window, so we can crop the full-screen recording
# down to the browser. Window bounds come back in logical points from CDP;
# multiply by the device pixel ratio to reach the captured pixel grid.
# Returns NULL if the bounds can't be read (caller falls back to full screen).
window_crop <- function() {
  tryCatch(
    {
      dpr <- js("window.devicePixelRatio")
      if (is.null(dpr) || !is.numeric(dpr) || dpr <= 0) dpr <- 1
      bnds <- b$Browser$getWindowForTarget()$bounds
      x <- max(0, round(bnds$left * dpr))
      y <- max(0, round(bnds$top * dpr))
      w <- round(bnds$width * dpr)
      h <- round(bnds$height * dpr)
      # yuv420p requires even dimensions
      w <- w - (w %% 2)
      h <- h - (h %% 2)
      sprintf("%d:%d:%d:%d", w, h, x, y)
    },
    error = function(e) NULL
  )
}

# --- Teardown ---------------------------------------------------------------

teardown <- function(app_dir, port, debug_port = 9222) {
  try(if (!is.null(b)) b$close(), silent = TRUE)
  try(if (!is.null(chromote_obj)) chromote_obj$close(), silent = TRUE)
  system(sprintf("pkill -f 'remote-debugging-port=%d'", debug_port), ignore.stderr = TRUE)
  system(sprintf("pkill -f 'shiny::runApp.*%d'", port), ignore.stderr = TRUE)
  if (!is.null(chrome_profile)) unlink(chrome_profile, recursive = TRUE)
  unlink(file.path(app_dir, "_survey"), recursive = TRUE)
  unlink(file.path(app_dir, "preview_data.csv"))
  unlink(file.path(app_dir, "survey_files"), recursive = TRUE)
  cat("Teardown complete.\n")
}
