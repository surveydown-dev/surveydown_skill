# Walkthrough: template_random_options
#
# Pages: welcome (q1) -> page2 (text) -> end.
#   - q1 : mc (radio), rendered server-side with RANDOM option labels each
#          load (sample(1:100, 3)). The option VALUES are the fixed strings
#          "option 1/2/3", so we pick the first available radio rather than a
#          hardcoded value.

cat("Answering welcome page...\n")

pause(1) # ensure the reactive q1 radios are rendered
click('input[name="q1"]') # first available option (labels are random)
pause(1)

click("#welcome_next")
pause(1)

click("#page2_next")
pause(2)

cat("Reached end of survey.\n")
