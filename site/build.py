"""Build the GitHub Pages site into _site/.

    pip install markdown   # Python-Markdown 3.x
    python3 site/build.py

The landing page (index.html) is hand-written; guides are rendered from the
Markdown in the repository, so they have one source. A screenshot.png in
site/ is shown on the landing page; without one, its <figure> is left out.
"""

import html
import re
import shutil
from pathlib import Path

import markdown

BASE = "https://nexusdynamic.org/liblsl.dart/"
SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
OUT = ROOT / "_site"

# Rendered guides: output file, source, title, description.
GUIDES = [
    (
        "relay.html",
        "packages/lsl_tools/doc/relay.md",
        "LSL over the network: WebSocket bridge and relay setup guide",
        "How to share Lab Streaming Layer (LSL) streams across networks and "
        "with web browsers: lsl share, lsl bridge, lsl publish and lsl relay, "
        "tokens, TLS (wss://) with Caddy or nginx, and LSL Viewer.",
    ),
]


def render(md_text: str) -> str:
    body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
        extension_configs={"toc": {"permalink": False}},
    )
    # Links between guides in the repository work on the site too.
    return re.sub(r'href="([^"]*?)relay\.md', r'href="\1relay.html', body)


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    for name in ["style.css", "robots.txt", "sitemap.xml"]:
        shutil.copy(SITE / name, OUT / name)
    shutil.copy(ROOT / "apps/lsl_viewer/assets/icon/icon.png", OUT / "icon.png")
    (OUT / ".nojekyll").touch()

    index = (SITE / "index.html").read_text()
    shot = SITE / "screenshot.png"
    if shot.exists():
        shutil.copy(shot, OUT / "screenshot.png")
    else:
        index = re.sub(
            r"\s*<!-- screenshot -->.*?<!-- /screenshot -->", "", index, flags=re.S
        )
    (OUT / "index.html").write_text(index)

    template = (SITE / "page.html").read_text()
    for out, source, title, description in GUIDES:
        page = template
        for key, value in {
            "title": html.escape(title),
            "description": html.escape(description),
            "url": BASE + out,
            "base": BASE,
            "source": source,
            "content": render((ROOT / source).read_text()),
        }.items():
            page = page.replace("{" + key + "}", value)
        (OUT / out).write_text(page)
    print(f"Built {OUT}")


if __name__ == "__main__":
    main()
