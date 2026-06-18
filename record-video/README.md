# Record a video of a survey walkthrough

Render a surveydown survey locally, drive a **visible** browser through it
answering every question, and capture the whole thing as an `.mp4`. Useful for
templates that can't be deployed online (e.g. a host free-tier is exhausted)
but still need a demo people can watch.

This reuses surveydown's own browser-automation test helpers
(`surveydown/tests/manual/helpers.R`) as the interaction engine, so every
question type is driven the same way the package's own tests drive it.

## How it works

```
record-video/
├── record-walkthrough.R          # orchestrator (entry point)
├── lib/
│   ├── helpers.R                 # headed Chrome + ChromeRemote + input drivers
│   └── record.R                  # ffmpeg avfoundation screen capture
└── walkthroughs/
    └── reactive_drilldown.R      # per-template answer script
```

The generated `.mp4` is written **into the template folder** it documents
(e.g. `templates/template_reactive_drilldown/template_reactive_drilldown.mp4`),
not under the skill.

The orchestrator:

1. **Boots the survey** (`shiny::runApp` in a background R process). The first
   run renders `survey.qmd`, which can take ~60s.
2. **Opens a visible Chrome window** and attaches chromote to it. chromote
   normally launches Chrome *headless*; it can't be made headed directly
   (`chrome_headless_mode()` always injects a `--headless` flag). So instead we
   launch Chrome ourselves with `--remote-debugging-port` and connect via
   chromote's `ChromeRemote` class. The window is launched at a fixed
   position/size so the recording can be cropped to just the browser. We also
   call `Emulation.clearDeviceMetricsOverride` (chromote applies a default
   992px viewport that would otherwise leave white space on the right) and
   close the leftover `about:blank` launch tab.
   It also injects an **overlay cursor** (`lib/cursor.js`): a visible arrow
   that glides to each control with a click ripple, since CDP-synthesized
   clicks don't move the real OS pointer.
3. **Starts the screen recorder** (`ffmpeg -f avfoundation`), cropped to the
   browser window's device-pixel bounds. The window is a 16:9 shape
   (1280×720 → 2560×1440 video).
4. **Runs the walkthrough script**, which answers each question using the
   helper drivers, pausing where a survey is reactive (later answers depend on
   earlier ones).
5. **Stops recording** (SIGINT so ffmpeg finalizes the mp4) and tears down the
   browser and app.

## Requirements (macOS)

- **Google Chrome** at `/Applications/Google Chrome.app` (vanilla Chromium
  build; Safari and ChatGPT Atlas do **not** work — see Notes).
- **R packages**: `chromote`, plus whatever the survey's `app.R` loads
  (`surveydown`, and e.g. `tidyverse` for the drilldown template).
- **Quarto** (to render `survey.qmd`).
- **ffmpeg** (`brew install ffmpeg`).
- **Screen Recording permission** for the app that runs this script (Terminal,
  iTerm, Positron, VS Code, …). Grant it under *System Settings → Privacy &
  Security → Screen Recording*, then **fully quit and reopen** that app — the
  permission only takes effect after a restart. Symptom if missing: ffmpeg
  hangs with no output file (it receives zero frames).

## Usage

From the `record-video/` directory:

```bash
Rscript record-walkthrough.R \
  ../../templates/template_reactive_drilldown \
  walkthroughs/reactive_drilldown.R
```

Arguments: `<template_dir> <walkthrough.R> [out.mp4] [app_port] [debug_port]`.
If `out.mp4` is omitted it defaults to `<template_dir>/<template_name>.mp4`
(the video lives next to the survey it documents). Ports default to 8200/9222.

## Adding a walkthrough for another template

Each survey has different question IDs and types, so the **answer script** is
bespoke; everything under it (`lib/`) is reusable. To add one:

1. Open the template's `survey.qmd` / `app.R` and note each question's `id`,
   `type`, and (for `select`/`mc`) its option values, plus the page IDs.
2. Copy `walkthroughs/reactive_drilldown.R` to
   `walkthroughs/<template_name>.R` and replace the body with the right calls.

Available helper drivers (one per question type), all keyed by question `id`:

| Question type | Helper call |
|---|---|
| `mc`, `mc_multiple`, `mc_buttons`, image choice | `click('input[name="<id>"][value="<v>"]')` |
| `text`, `numeric`, `textarea` | `set_text("<id>", "<v>")` |
| `select` | `set_select("<id>", "<v>")` |
| `slider` (text options) | `set_slider("<id>", <1-based position>)` |
| `slider_numeric` | `set_slider_numeric("<id>", <v>)` |
| `slider_numeric` range | `set_slider_range("<id>", <from>, <to>)` |
| `date` | `set_date("<id>", "yyyy-mm-dd")` |
| `daterange` | `set_daterange("<id>", "yyyy-mm-dd", "yyyy-mm-dd")` |
| next button | `click("#<page_id>_next")` |

Other useful helpers: `body_has("text")`, `visible("<id>")`, `present("<sel>")`,
`js("<expr>")`, and `pause()` to pace the video and let reactive questions
re-render.

> **Do not call `shot()` / `b$screenshot()` while recording.** chromote applies
> a device-metrics override to capture a screenshot, which briefly reflows the
> page to a tiny emulated viewport (dark fill around it) — a visible blink in
> the video. `shot()` is fine only for offline debugging when not recording.

## Notes and limitations

- **Dropdowns are shown opening.** `set_select()` opens the selectize dropdown,
  moves the cursor onto the chosen option and highlights it in blue (so the
  viewer sees the pick), then selects it. Pass `show = FALSE` to set silently.
- **Overlay cursor, not a real one.** The arrow and click ripple are an
  injected overlay (`lib/cursor.js`), because CDP clicks don't move the real
  macOS pointer. Drives off `window.__sdMove()` / `window.__sdRipple()`.
- **16:9 output.** The browser window is launched at a 16:9 size, so cropping
  to the window yields a 16:9 video. Long dropdowns are capped to scroll
  internally (via injected CSS) so they don't spill off the shorter viewport.
- **Global time factor.** Every demo-pacing pause runs through `pause()`, which
  scales it by `SD_TIME_FACTOR` (default `0.8` — ~20% quicker than baseline
  `1.0`). Functional waits (page load, ffmpeg init, polling) are not scaled.
  Override per run by exporting `SD_TIME_FACTOR=1.0` (slower) or `0.5` (faster)
  before calling the script, or setting the `SD_TIME_FACTOR` global in R.
- **Inputs scroll into view.** Every driver (`click`, `set_text`, `set_select`,
  sliders, dates) scrolls its question to the center and glides the cursor onto
  it before acting, so the working location is always on camera.
- **Reactive surveys need pacing.** When a later question's options depend on an
  earlier answer (the drilldown's `model` depends on `make`), `pause(~2s)` after
  the controlling answer so the dependent question re-renders before you set it
  (the `pause()` value is itself scaled by the time factor).
- **Why not Safari or ChatGPT Atlas?** Safari is WebKit and speaks no Chrome
  DevTools Protocol. ChatGPT Atlas is a productized Chromium that ignores
  `--headless`/`--remote-debugging-port` and exposes no CDP endpoint. chromote
  needs a vanilla Chrome/Chromium.
- **macOS only** as written (the recorder uses `avfoundation`). Porting to
  Linux/Windows means swapping the ffmpeg input in `lib/record.R`
  (`x11grab` / `gdigrab`).
