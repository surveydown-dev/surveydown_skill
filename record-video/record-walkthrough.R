# Record a screen video of a surveydown survey being filled out end to end.
#
# Usage (from the record-video/ directory, or with absolute paths):
#   Rscript record-walkthrough.R <template_dir> <walkthrough.R> [out.mp4] \
#       [app_port] [debug_port]
#
# Example:
#   Rscript record-walkthrough.R \
#     ../../templates/template_reactive_drilldown \
#     walkthroughs/reactive_drilldown.R \
#     output/reactive_drilldown.mp4
#
# It boots the survey app, opens it in a VISIBLE Chrome window, starts the
# screen recorder, sources the walkthrough (which answers every question via
# the helpers), then stops recording and tears everything down.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript record-walkthrough.R <template_dir> <walkthrough.R> ",
       "[out.mp4] [app_port] [debug_port]")
}

here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
# When run via Rscript, resolve this script's directory for sourcing lib/.
script_dir <- {
  ca <- commandArgs(FALSE)
  f <- sub("^--file=", "", ca[grepl("^--file=", ca)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}

template_dir   <- normalizePath(args[[1]], mustWork = TRUE)
walkthrough    <- normalizePath(args[[2]], mustWork = TRUE)
# By default the video lands INSIDE the template folder it documents, named
# video-recording.mp4 (consistent across every survey project).
out_mp4        <- if (length(args) >= 3) args[[3]] else
  file.path(template_dir, "video-recording.mp4")
app_port       <- if (length(args) >= 4) as.integer(args[[4]]) else 8200L
debug_port     <- if (length(args) >= 5) as.integer(args[[5]]) else 9222L

out_mp4 <- normalizePath(out_mp4, mustWork = FALSE)

SD_LIB_DIR <- file.path(script_dir, "lib") # so inject_cursor() finds cursor.js
source(file.path(script_dir, "lib", "helpers.R"))
source(file.path(script_dir, "lib", "record.R"))

cat("\n=== Recording walkthrough ===\n")
cat("Template:   ", template_dir, "\n")
cat("Walkthrough:", walkthrough, "\n")
cat("Output:     ", out_mp4, "\n")
cat("Time factor:", sd_time_factor(), "\n\n")

ok <- TRUE
tryCatch(
  {
    launch_app(template_dir, app_port)
    launch_browser(debug_port)
    new_session(app_port, wait = 6)

    # Brief settle, then start recording just before the survey is answered.
    # Crop the capture to just the browser window (falls back to full screen).
    Sys.sleep(1)
    crop <- window_crop()
    if (is.null(crop)) cat("[note] window bounds unavailable; recording full screen\n")
    start_recording(out_mp4, crop = crop)
    Sys.sleep(0.3)

    # The walkthrough script answers every question using the helpers.
    source(walkthrough, local = FALSE)

    pause(2) # hold the final frame
  },
  error = function(e) {
    ok <<- FALSE
    cat("\n[ERROR] ", conditionMessage(e), "\n")
  }
)

stop_recording()
teardown(template_dir, app_port, debug_port)

if (file.exists(out_mp4)) {
  size_kb <- round(file.info(out_mp4)$size / 1024)
  cat(sprintf("\nVideo saved: %s (%d KB)\n", out_mp4, size_kb))
} else {
  cat("\n[WARN] No video file was produced.\n")
}
cat(if (ok) "=== Done ===\n" else "=== Finished with errors ===\n")
