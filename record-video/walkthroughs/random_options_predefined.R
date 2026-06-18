# Walkthrough: template_random_options_predefined
#
# Pages: welcome (q1) -> page2 (text) -> end.
#   - q1 : mc (radio), rendered server-side. Each load picks one of 10
#          predefined number-triples (design.csv) as the labels; the option
#          VALUES are the fixed strings "option 1/2/3". A specific number may
#          be absent on a given run, so pick the first available radio.

cat("Answering welcome page...\n")

pause(1) # ensure the reactive q1 radios are rendered
click('input[name="q1"]') # first available option (labels are random)
pause(1)

click("#welcome_next")
pause(1)

click("#page2_next")
pause(2)

cat("Reached end of survey.\n")
