#!/usr/bin/env python3
"""Downloads imgflip meme templates into Baba's library.

Walks imgflip.com/memetemplates (most popular first), saving each template's
full-size image and 250px thumbnail plus an index.json the app reads. Safe to
re-run: files already on disk are skipped, so it resumes and tops up.

    scripts/crawl.py                 # top 1000
    scripts/crawl.py --count 3000
    scripts/crawl.py --dest DIR
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_DEST = Path.home() / "Library/Application Support/Baba"
UA = "Mozilla/5.0 (Baba local meme library)"
BOX = re.compile(
    r'<h3 class="mt-title">\s*<a [^>]*href="/meme/([^"]+)">([^<]+)</a>.*?'
    r'src="//i\.imgflip\.com/4/([A-Za-z0-9]+)\.(jpg|png|gif|jpeg)"',
    re.S,
)


def fetch(url: str) -> bytes | None:
    """The body, or None on a 404. Other errors are retried, then raised."""
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if attempt == 3:
                raise
        except Exception:
            if attempt == 3:
                raise
        time.sleep(2 * (attempt + 1))
    raise AssertionError


def download(url: str, path: Path) -> bool:
    """True if the file is on disk afterwards; downloads only if it is not already."""
    if path.exists() and path.stat().st_size > 0:
        return True
    body = fetch(url)
    if body is None:
        return False
    path.write_bytes(body)
    return True


def download_original(img_id: str, dest: Path) -> str | None:
    """The full-size image's filename. Its extension is not the thumbnail's, so try each."""
    for ext in ("jpg", "png", "gif", "jpeg"):
        name = f"{img_id}.{ext}"
        if (dest / name).exists() and (dest / name).stat().st_size > 0:
            return name
    for ext in ("jpg", "png", "gif", "jpeg"):
        name = f"{img_id}.{ext}"
        if download(f"https://i.imgflip.com/{name}", dest / name):
            return name
        time.sleep(0.1)
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--count", type=int, default=1000, help="templates to fetch (default 1000)")
    ap.add_argument("--dest", type=Path, default=DEFAULT_DEST)
    ap.add_argument("--delay", type=float, default=0.25, help="seconds between requests")
    args = ap.parse_args()

    full_dir, thumb_dir = args.dest / "templates", args.dest / "thumbs"
    full_dir.mkdir(parents=True, exist_ok=True)
    thumb_dir.mkdir(parents=True, exist_ok=True)

    # IDs in excluded.txt (one per line, '#' starts a comment) are never fetched:
    # the repo's default list plus any in the destination folder.
    seen = set()
    for excluded in (Path(__file__).parent.parent / "Resources" / "excluded.txt", args.dest / "excluded.txt"):
        if excluded.exists():
            seen |= {l.split("#")[0].strip() for l in excluded.read_text().splitlines()} - {""}
    entries = []
    page = 1
    while len(entries) < args.count:
        page_html = fetch(f"https://imgflip.com/memetemplates?page={page}").decode("utf-8", "replace")
        found = BOX.findall(page_html)
        if not found:
            print(f"page {page}: no templates, stopping", file=sys.stderr)
            break
        for slug, name, img_id, ext in found:
            if img_id in seen or len(entries) >= args.count:
                continue
            seen.add(img_id)
            thumb = f"{img_id}.{ext}"
            try:
                file = download_original(img_id, full_dir)
                if not file or not download(f"https://i.imgflip.com/4/{thumb}", thumb_dir / thumb):
                    print(f"  skip {name}: image not found", file=sys.stderr)
                    continue
            except Exception as e:
                print(f"  skip {name}: {e}", file=sys.stderr)
                continue
            # Newer templates have a numeric id in front of the name: /meme/123/Name.
            slug = slug.rsplit("/", 1)[-1]
            entries.append({
                "id": img_id, "name": html.unescape(name).strip(),
                "slug": slug, "file": file, "thumb": thumb,
            })
            time.sleep(args.delay)
        print(f"page {page}: {len(entries)}/{args.count}", flush=True)
        page += 1
        time.sleep(args.delay)

    (args.dest / "index.json").write_text(json.dumps(entries, indent=1))
    print(f"wrote {len(entries)} templates to {args.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
