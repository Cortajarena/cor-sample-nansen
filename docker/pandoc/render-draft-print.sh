#!/bin/sh
# Render docs/draft.md -> self-contained HTML with Mermaid diagrams.
#
# Same idea as render-draft.sh (site HTML) plus the mermaid shim:
# --embed-resources inlines mermaid.min.js, so this single file renders
# diagrams offline in any browser - and is the input for print-pdf.cjs.
#
#   render-draft-print [output-file]
set -eu

OUT="${1:-/docs/dist/draft-print/index.html}"

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

echo "draft (print) rendered -> $OUT"
