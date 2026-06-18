# Walkthrough: template_reactive_questions
#
# One page (welcome) with a reactive dependency:
#   - pet_type  : mc (radio), STATIC controller (Dogs->dog, Cats->cat)
#   - pet_owner : mc (radio), REACTIVE dependent, rendered server-side only
#                 after pet_type is answered (values always yes/no)
# Then an end page.

cat("Answering welcome page...\n")

# Controller first.
click('input[name="pet_type"][value="dog"]')
pause(2) # let the reactive pet_owner question render

# Dependent (values are yes/no regardless of the chosen pet).
click('input[name="pet_owner"][value="yes"]')
pause(1)

click("#welcome_next")
pause(2)

cat("Reached end of survey.\n")
