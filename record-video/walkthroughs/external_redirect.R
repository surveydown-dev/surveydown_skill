# Walkthrough: template_external_redirect
#
# Pages: welcome (screening_question, mc) -> a redirect end page chosen by
# sd_skip_if. We pick "normal_end_2" (reactive redirect, no auto-timer), which
# routes to end_page_2 showing a "Redirect with Normal Status" button.
#
# We deliberately STOP on the redirect-button page (cursor on the button) and
# do NOT click it -- clicking navigates the browser to an external site
# (google.com), which we don't want in the demo.

cat("Answering welcome page...\n")

click('input[name="screening_question"][value="normal_end_2"]')
pause(0.5)

click("#welcome_next") # sd_skip_if jumps straight to end_page_2
pause(2)               # let the reactive redirect button render

# Show the redirect button without firing it.
if (present("#redirect_normal")) {
  cursor_to("#redirect_normal")
} else if (present("#container-redirect_normal")) {
  cursor_to("#container-redirect_normal")
}
pause(2)

cat("Reached redirect page (not navigating out).\n")
