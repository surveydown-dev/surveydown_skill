# Walkthrough: template_questions_yml
#
# Pages: welcome -> question_types (every question type) -> end.
# Questions are defined in questions.yml; page 2 showcases one of each type.
# Selector conventions:
#   mc / mc_multiple / mc_image / mc_multiple_image -> input[name=ID][value=V]
#   mc_buttons / mc_multiple_buttons               -> #ID input[value=V]
#   matrix / matrix_multiple                        -> per-row sub-question ids
#   select -> set_select; sliders/dates -> their helpers

cat("Page 1: welcome...\n")
click("#welcome_next")
pause(1)

cat("Page 2: question_types (all types)...\n")

set_text("silly_word", "flibberjam")
set_text("silly_paragraph", "Once upon a silly time, a banana wore a tiny hat.")
set_text("age", "42")

click('input[name="artist"][value="taylor_swift"]')        # mc
click('#fruit input[value="apple"]')                       # mc_buttons

click('input[name="swift"][value="fearless"]')             # mc_multiple
click('input[name="swift"][value="red"]')
click('#michael_jackson input[value="thriller"]')          # mc_multiple_buttons
click('#michael_jackson input[value="billie_jean"]')

click('input[name="apple_image"][value="fuji"]')           # mc_image
click('input[name="apple_buy"][value="fuji"]')             # mc_multiple_image
click('input[name="apple_buy"][value="honeycrisp"]')

set_select("education", "college_grad")                    # select (selectize)

set_slider("climate_care", 4)                              # category slider -> "Believe"
set_slider_numeric("slider_single_val", 7)                 # numeric slider
set_slider_range("slider_range", 2, 8)                     # numeric range slider

set_date("dob", "1990-05-15")
set_daterange("hs_date", "2004-09-01", "2008-06-15")

click('input[name="car_preference_buy_gasoline"][value="disagree"]')  # matrix row 1
click('input[name="car_preference_buy_ev"][value="agree"]')           # matrix row 2

click('input[name="vehicle_features_gasoline"][value="affordable"]')  # matrix_multiple
click('input[name="vehicle_features_gasoline"][value="fast"]')
click('input[name="vehicle_features_ev"][value="eco_friendly"]')

pause(1)
click("#question_types_next")
pause(2)

cat("Reached end of survey.\n")
