# Screen-recording helpers (ffmpeg + macOS avfoundation).
#
# We capture the whole display while the headed Chrome window (driven by
# lib/helpers.R) plays the survey. ffmpeg writes an H.264 .mp4.
#
# IMPORTANT: macOS requires Screen Recording permission for whichever app
# spawns ffmpeg (the terminal / IDE running this script). If the output is
# all black, grant it under System Settings > Privacy & Security > Screen
# Recording, then fully quit and reopen that app.

rec_pid <- NULL # ffmpeg process id while recording

# Discover the avfoundation device index for "Capture screen 0". The index
# is not stable across machines (cameras shift it), so detect it each run.
detect_screen_device <- function() {
  out <- suppressWarnings(system(
    "ffmpeg -f avfoundation -list_devices true -i '' 2>&1",
    intern = TRUE
  ))
  line <- grep("Capture screen 0", out, value = TRUE)
  if (length(line) == 0) {
    stop("No 'Capture screen 0' avfoundation device found. ffmpeg output:\n",
         paste(out, collapse = "\n"))
  }
  as.integer(sub(".*\\[([0-9]+)\\] Capture screen 0.*", "\\1", line[1]))
}

# Start recording to outfile. Video only (':none' audio) to avoid mic
# permission hangs. `crop` is an optional ffmpeg crop spec "w:h:x:y" (device
# pixels) to capture just the browser window instead of the whole screen.
# Returns invisibly; sets rec_pid.
start_recording <- function(outfile, fps = 30, screen = NULL, crop = NULL) {
  if (is.null(screen)) screen <- detect_screen_device()
  dir.create(dirname(normalizePath(outfile, mustWork = FALSE)),
             showWarnings = FALSE, recursive = TRUE)
  unlink(outfile)

  vf <- if (!is.null(crop)) sprintf("-vf 'crop=%s'", crop) else ""
  cmd <- sprintf(
    paste(
      "ffmpeg -y -f avfoundation -capture_cursor 1 -framerate %d -i '%d:none'",
      "%s -vcodec libx264 -preset ultrafast -pix_fmt yuv420p '%s'",
      "> /tmp/sd_record_ffmpeg.log 2>&1 & echo $!"
    ),
    fps, screen, vf, outfile
  )
  rec_pid <<- as.integer(system(cmd, intern = TRUE))
  Sys.sleep(1.3) # let ffmpeg initialize the capture before the survey starts

  if (!is_recording()) {
    stop("ffmpeg failed to start. See /tmp/sd_record_ffmpeg.log:\n",
         paste(utils::tail(readLines("/tmp/sd_record_ffmpeg.log", warn = FALSE), 15),
               collapse = "\n"))
  }
  cat(sprintf("Recording screen %d to %s (ffmpeg pid %d)\n", screen, outfile, rec_pid))
  invisible(TRUE)
}

is_recording <- function() {
  !is.null(rec_pid) && system(sprintf("kill -0 %d 2>/dev/null", rec_pid)) == 0
}

# Stop recording. Send SIGINT so ffmpeg finalizes the mp4 (writes the moov
# atom) instead of leaving a truncated file, then wait for it to exit.
stop_recording <- function() {
  if (is.null(rec_pid)) return(invisible())
  system(sprintf("kill -INT %d", rec_pid), ignore.stderr = TRUE)
  for (i in 1:30) {
    if (!is_recording()) break
    Sys.sleep(0.5)
  }
  cat("Recording stopped.\n")
  invisible(TRUE)
}
