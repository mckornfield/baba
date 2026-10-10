# Baba

A local meme generator for macOS, in the shape of [Yaga](../yaga): a menu bar
app. Hit **⌥⌘M**, pick a template, type the caption, then **copy** or **drag the
finished meme straight into** a chat box. Templates are downloaded once from
imgflip and live on disk, so it works offline.

## Setup

```sh
scripts/crawl.py            # download the top 1000 templates (~15 min, resumable)
./build.sh --install        # build, install to /Applications, launch
```

`crawl.py` walks imgflip's template listing politely (a quarter-second between
requests) and saves each template's full-size image and thumbnail to
`~/Library/Application Support/Baba`. Re-running it skips what is already there.
`--count 3000` fetches more, `--dest DIR` writes elsewhere (point the app at it
with `BABA_LIBRARY=DIR`).

Needs the Swift toolchain (Xcode or Command Line Tools). `build.sh` falls back
to the 26.5 SDK when only the Command Line Tools are installed, because the
newest SDK there lacks the SwiftUI macro plugin.

## Using it

- The search box has focus on open; ↵ picks the first match. Recently used
  templates lead the grid.
- Every template starts with a top and bottom caption. **Drag** a dashed box to
  move it, drag its **corner dot** to resize it, **+ Text** adds another.
  Text is Impact, white with a black outline, and shrinks to fit its box.
- ↵ or **Copy** puts a PNG at the template's full resolution on the clipboard.
  **Drag to chat** drags the same PNG out as a file.
- Esc goes back to the grid, then closes the panel. Right-click the menu bar icon
  to open the template folder or quit.

`Baba --render out.png [TEMPLATE-ID] [TOP] [BOTTOM]` renders one meme without the UI.
