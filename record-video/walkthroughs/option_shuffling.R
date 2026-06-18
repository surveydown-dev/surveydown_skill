# Walkthrough: template_option_shuffling
#
# Pages: welcome -> education -> question_types -> indices -> end.
# Options are shuffled in DISPLAY ORDER only; the option VALUES are stable
# (apple, banana, pear, strawberry, grape, mango, watermelon), so we answer
# by value. mc/mc_multiple use input[name=...]; the *_buttons variants use
# the "#<id> input[value=...]" form.

cat("Page 1: welcome...\n")
click("#welcome_next")
pause(0.5)

cat("Page 2: education...\n")
click("#education_next")
pause(0.5)

cat("Page 3: question_types...\n")
click('input[name="fruit_mc"][value="apple"]')                 # mc
click('#fruit_mc_buttons input[value="banana"]')               # mc_buttons
click('input[name="fruit_mc_multiple"][value="apple"]')        # mc_multiple
click('input[name="fruit_mc_multiple"][value="grape"]')        #   (2nd pick)
click('#fruit_mc_multiple_buttons input[value="mango"]')       # mc_multiple_buttons
pause(0.5)
click("#question_types_next")
pause(0.5)

cat("Page 4: indices...\n")
click('#fruit_mc_buttons_0 input[value="apple"]')
click('#fruit_mc_buttons_1 input[value="banana"]')
click('#fruit_mc_buttons_2 input[value="grape"]')
click('#fruit_mc_buttons_3 input[value="watermelon"]')
pause(0.5)
click("#indices_next")
pause(2)

cat("Reached end of survey.\n")
