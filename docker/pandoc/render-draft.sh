#!/bin/sh
# Render docs/draft.md -> self-contained HTML with TOC and rendered Mermaid.
#
# The mermaid bundle is inlined by --embed-resources (see mermaid-head.html),
# so this single file works offline, on GitHub Pages and from file:// - and it
# is also the input for the print-to-PDF step (docker/slidev/print-pdf.cjs).
#
# Used by the draft-build compose service and CI (site/draft/index.html).
#
#   render-draft [output-file]
set -eu

OUT="${1:-/docs/dist/site/draft/index.html}"

mkdir -p "$(dirname "$OUT")"

pandoc /docs/draft.md \
  --from markdown \
  --to html5 \
  --standalone \
  --toc \
  --embed-resources \
  --css /pandoc.css \
  --include-in-header=/opt/mermaid/head.html \
  --metadata title='Nansen: on-chain pipeline design (draft)' \
  --metadata lang=en \
  --output "$OUT"

echo "draft rendered -> $OUT"
