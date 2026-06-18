# Walkthrough: template_reactive_drilldown
#
# One survey page (id = "vehicle") with three select questions, then an end
# page:
#   - year  : static select (model years 2025..2010)
#   - make  : select rendered server-side (mpg manufacturers)
#   - model : select rendered REACTIVELY from the chosen make
#             (app.R observes sd_value("make") and re-renders the options)
#
# The reactive dependency is the whole point of this template, so we pause
# after choosing the make to let the model options re-render before picking
# one. Values below are exact mpg-derived option labels (Toyota -> Camry).
#
# Sourced by record-walkthrough.R, which provides the helper functions and
# the live session `b`.

cat("Answering page 1 (vehicle)...\n")

set_select("year", "2020")
pause(1.5)

set_select("make", "Toyota")
pause(2.5) # let the reactive `model` question re-render for this make

set_select("model", "Camry")
pause(1.5)

# NOTE: do NOT call shot()/b$screenshot() mid-recording. chromote applies a
# device-metrics override to capture, which briefly reflows the page to a tiny
# emulated viewport (with dark fill around it) -- a visible blink in the video.

# Advance to the end page. surveydown names the next button "<page_id>_next".
click("#vehicle_next", wait = 3)
pause(2)

cat("Reached end of survey.\n")
