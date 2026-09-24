# ---------------------------------------------------------------------------
# Document renderer for docs/draft.md (plain markdown - a document, NOT
# slides; Slidev would render it as one giant slide).
#
#   build : docker build -t nansen-pandoc docker/pandoc
#   run   : via compose (draft-build / draft-pdf-html services)
#
# pandoc/extra ships pandoc + a full TeX Live (xelatex), so it renders both
# HTML and PDF without extra toolchains.
#
# Mermaid: pandoc cannot rasterize diagrams, so we don't ask it to. We bake
# the pinned mermaid bundle into the image and inline it into the HTML with
# --embed-resources; the diagrams are then rendered by the browser/Chromium
# (see print-pdf.cjs). No Node, no puppeteer, no Chromium in this image.
# ---------------------------------------------------------------------------
ARG MERMAID_VERSION=11.4.1

# Fetch stage: `npm pack` avoids needing curl/wget in the final image.
FROM node:22-alpine AS mermaid
ARG MERMAID_VERSION
WORKDIR /m
RUN npm pack "mermaid@${MERMAID_VERSION}" \
    && tar -xzf "mermaid-${MERMAID_VERSION}.tgz" \
    && install -D -m 0644 package/dist/mermaid.min.js /opt/mermaid/mermaid.min.js

FROM pandoc/extra:3.11.0.0-debian

COPY --from=mermaid /opt/mermaid/mermaid.min.js /opt/mermaid/mermaid.min.js
COPY mermaid-head.html /opt/mermaid/head.html

# base image's ENTRYPOINT is `pandoc` - reset it so CMD runs as a command
ENTRYPOINT []

# GitHub-ish styling for the long-form rendering
COPY pandoc.css /pandoc.css

# HTML renderer entry (defaults: -> /docs/dist/site/draft/index.html)
COPY render-draft.sh /usr/local/bin/render-draft
RUN chmod +x /usr/local/bin/render-draft

# HTML renderer with the mermaid shim inlined (input for the print-to-PDF step)
COPY render-draft-print.sh /usr/local/bin/render-draft-print
RUN chmod +x /usr/local/bin/render-draft-print

WORKDIR /docs

CMD ["/usr/local/bin/render-draft"]