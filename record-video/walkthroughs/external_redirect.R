# Walkthrough: template_external_redirect
#
# Pages: welcome (screening_question, mc) -> reactive redirect end page.
# We pick "normal_end_2" (reactive redirect, no auto-timer), routing to
# end_page_2 with a "Redirect with Normal Status" button whose onclick does
#   window.location.href = 'https://www.google.com?...&status=0'
#
# Demonstration: actually FIRE the redirect so Google opens carrying our
# status=0 parameter, then reveal the URL (with status=0) in the address bar.
#
# Launch the app WITH URL parameters so the redirect URL is populated:
#   SD_URL_QUERY="?id_a=a123&id_b=b234&id_c=c345"

cat("Answering welcome page...\n")

click('input[name="screening_question"][value="normal_end_2"]')
pause(0.5)

click("#welcome_next") # sd_skip_if jumps straight to end_page_2
pause(2)               # let the reactive redirect button render

cat("Firing the redirect (navigates this tab to Google with status=0)...\n")
click("#redirect_normal_btn", wait = 1) # onclick -> window.location.href = google url

# The navigation to Google commits ~1s after the click; until it commits the
# address bar still shows the survey URL. Wait for the commit so the whole hold
# below shows the Google URL (ending in &status=0), not the transition.
for (i in 1:40) {
  href <- tryCatch(js("window.location.href"), error = function(e) "")
  if (grepl("google\\.", href)) break
  Sys.sleep(0.25)
}
cat("Navigation committed to:", tryCatch(js("window.location.href"), error = function(e) "?"), "\n")

# Hold so the status=0 URL is clearly readable. (The omnibox is browser chrome,
# not page DOM, so it can't be clicked/selected via CDP -- but the whole URL
# fits and is visible after navigation.)
pause(7)

cat("Done: redirect fired, status=0 visible in the URL.\n")
