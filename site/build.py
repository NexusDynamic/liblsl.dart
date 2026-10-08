"""Build the GitHub Pages site into _site/.

    pip install markdown pymdown-extensions
    python3 site/build.py

The landing page (index.html) is hand-written; guides are rendered from the
Markdown in the repository, so they have one source. The landing page's
screenshot is the one in the repository root.
"""

import html
import posixpath
import re
import shutil
from pathlib import Path

import markdown

BASE = "https://nexusdynamic.org/liblsl.dart/"
SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
OUT = ROOT / "_site"

REPO = "https://github.com/NexusDynamic/liblsl.dart"

# Rendered guides: output file, source, title, description.
GUIDES = [
    (
        "guides.html",
        "docs/README.md",
        "Guides for liblsl.dart: LSL, multi-device experiments and timing",
        "Step-by-step guides for Lab Streaming Layer (LSL) in Dart and "
        "Flutter: streaming between devices, coordinating a multi-device "
        "experiment, validating timing, and sharing streams over the network.",
    ),
    (
        "streaming-between-devices.html",
        "docs/streaming-between-devices.md",
        "Streaming data between two devices with liblsl for Dart",
        "How to send a Lab Streaming Layer (LSL) stream from one device and "
        "receive it on another in Dart, with timestamps, clock offsets and "
        "network requirements.",
    ),
    (
        "coordinated-experiment.html",
        "docs/coordinated-experiment.md",
        "A coordinated multi-device experiment with peer_coordinator",
        "How to run one program on several devices so that they form a "
        "session, exchange data and follow a common sequence of trials, over "
        "LSL, WebSocket or WebRTC.",
    ),
    (
        "validating-timing.html",
        "docs/validating-timing.md",
        "Validating timing in a lab: latency, jitter, loss and clock drift",
        "How to measure and report transmission latency, jitter, loss and "
        "clock drift between the devices of a lab with transport_timing.",
    ),
    (
        "relay.html",
        "packages/lsl_tools/doc/relay.md",
        "LSL over the network: WebSocket bridge and relay setup guide",
        "How to share Lab Streaming Layer (LSL) streams across networks and "
        "with web browsers: lsl share, lsl bridge, lsl publish and lsl relay, "
        "tokens, TLS (wss://) with Caddy or nginx, and LSL Viewer.",
    ),
]

PAGES = {source: out for out, source, _, _ in GUIDES}


def render(md_text: str, source: str) -> str:
    body = markdown.markdown(
        md_text,
        # superfences, not fenced_code: it also handles a code block inside a
        # list item, which the steps of the guides have.
        extensions=["tables", "pymdownx.superfences", "toc", "sane_lists"],
        extension_configs={"toc": {"permalink": False}},
    )

    # Relative links are written for the repository. On the site, a link to
    # another guide goes to its page and any other goes to the file on GitHub.
    def link(match: re.Match) -> str:
        href = match.group(1)
        if re.match(r"[a-z]+:|#|/", href):
            return match.group(0)
        path, _, anchor = href.partition("#")
        target = posixpath.normpath(posixpath.join(posixpath.dirname(source), path))
        anchor = "#" + anchor if anchor else ""
        if target in PAGES:
            return f'href="{PAGES[target]}{anchor}"'
        kind = "tree" if (ROOT / target).is_dir() else "blob"
        return f'href="{REPO}/{kind}/main/{target}{anchor}"'

    return re.sub(r'href="([^"]*)"', link, body)


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    for name in [
        "style.css",
        "robots.txt",
        "sitemap.xml",
        # The icons of nexusdynamic.org; icon.png is the social preview image.
        "nexusdynamic.svg",
        "favicon-32x32.png",
        "icon.png",
    ]:
        shutil.copy(SITE / name, OUT / name)
    (OUT / ".nojekyll").touch()

    shutil.copy(ROOT / "lsl_and_xdf_viewer_screenshot.png", OUT / "screenshot.png")
    shutil.copy(SITE / "index.html", OUT / "index.html")

    template = (SITE / "page.html").read_text()
    for out, source, title, description in GUIDES:
        page = template
        for key, value in {
            "title": html.escape(title),
            "description": html.escape(description),
            "url": BASE + out,
            "base": BASE,
            "source": source,
            "content": render((ROOT / source).read_text(), source),
        }.items():
            page = page.replace("{" + key + "}", value)
        (OUT / out).write_text(page)
    print(f"Built {OUT}")


if __name__ == "__main__":
    main()
