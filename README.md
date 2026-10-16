# Baba

A local meme generator for macOS, in the shape of [Yaga](https://github.com/marcusds/yaga): a menu bar
app. Hit **⌥⌘M**, pick a template, type the caption, then **copy** or **drag the
finished meme straight into** a chat box. Templates are downloaded once from
imgflip and live on disk, so it works offline.

## Setup

```sh
./build.sh --install        # build, install to /Applications, launch
./build.sh --dist           # zip for another Mac (templates not included)
```

On first run the grid is empty: click **Download 1000 memes**. Baba fetches the
most popular imgflip templates (about a minute), saving each one's full-size
image and thumbnail to `~/Library/Application Support/Baba`, and the grid fills
in as pages arrive. It is resumable and walks imgflip politely, a page at a
time. Right-click the menu bar icon → **Download Memes…** tops it up later.

`scripts/crawl.py` does the same job from the command line and can go further:
`--count 3000` fetches more, `--dest DIR` writes elsewhere (point the app at it
with `BABA_LIBRARY=DIR`). `Baba --crawl N` runs the in-app downloader headlessly.

Needs the Swift toolchain (Xcode or Command Line Tools). `build.sh` falls back
to the 26.5 SDK when only the Command Line Tools are installed, because the
newest SDK there lacks the SwiftUI macro plugin.

## Adding your own images

Drop any image (png, jpg, gif, webp, heic…) into `~/Library/Application Support/Baba/custom/`
(right-click the menu bar icon → **Add Your Own Images…** opens it). It shows up
in the grid the next time you open the panel, named after the file
(`distracted_boyfriend.jpg` → "distracted boyfriend"), newest first. Delete the
file to remove it.

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
