# Walkthrough: template_custom_plotly_chart
#
# One page (plotly_chart) with a single REQUIRED custom question
# `point_selection`: the user clicks a marker in a plotly scatter plot of
# mtcars (wt vs mpg). There is no standard form input, so a JS .click() will
# not register -- we dispatch a real synthetic mouse click (CDP Input) at a
# marker's pixel coordinates, which fires plotly_click.

cat("Selecting a point on the plotly chart...\n")

pause(2) # let the plotly widget finish rendering its markers

# Locate a scatter marker and compute its viewport-center in CSS pixels.
# NOTE: js() evaluates an EXPRESSION, so no top-level `return` (that throws).
marker <- "#scatter_plot .scatterlayer .points path"
if (!present(marker)) marker <- "#scatter_plot path.point"

mx <- js(sprintf(
  "document.querySelector('%s').getBoundingClientRect().left + document.querySelector('%s').getBoundingClientRect().width/2",
  marker, marker
))
my <- js(sprintf(
  "document.querySelector('%s').getBoundingClientRect().top + document.querySelector('%s').getBoundingClientRect().height/2",
  marker, marker
))

if (is.numeric(mx) && mx > 0) {
  # Glide the overlay cursor to the marker, flash a ripple, then dispatch a
  # real mouse click there so plotly registers the point selection.
  cursor_to(marker)
  cursor_click()
  b$Input$dispatchMouseEvent(type = "mouseMoved", x = mx, y = my)
  b$Input$dispatchMouseEvent(type = "mousePressed", x = mx, y = my,
                             button = "left", clickCount = 1)
  b$Input$dispatchMouseEvent(type = "mouseReleased", x = mx, y = my,
                             button = "left", clickCount = 1)
  pause(2) # let selected_point() update the "You selected:" line
} else {
  cat("[warn] no plotly marker found to click\n")
}

click("#plotly_chart_next")
pause(2)

cat("Reached end of survey.\n")
