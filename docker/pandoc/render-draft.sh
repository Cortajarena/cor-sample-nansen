#!/bin/sh
# Render docs/draft.md -> self-contained HTML with TOC.
# Used by the draft-build compose service and CI (site/draft/index.html).
set -eu

OUT_DIR="${1:-/docs/dist/site/draft}"

mkdir -p "$OUT_DIR"

pandoc /docs/draft.md \
  --from markdown \
  --to html5 \
  --standalone \
  --toc \
  --embed-resources \
  --css /pandoc.css \
  --metadata title='Nansen: on-chain pipeline design (draft)' \
  --metadata lang=en \
  --output "$OUT_DIR/index.html"

echo "draft rendered -> $OUT_DIR/index.html"