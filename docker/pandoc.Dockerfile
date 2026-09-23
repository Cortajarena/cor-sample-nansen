# ---------------------------------------------------------------------------
# Document renderer for docs/draft.md (plain markdown - a document, NOT
# slides; Slidev would render it as one giant slide).
#
#   build : docker build -f docker/pandoc.Dockerfile -t nansen-pandoc .
#   run   : via compose (draft-build / draft-pdf services)
#
# pandoc/extra ships pandoc + a full TeX Live (xelatex), so it renders both
# HTML and PDF without extra toolchains.
# ---------------------------------------------------------------------------
FROM pandoc/extra:3.11.0.0-debian

# base image's ENTRYPOINT is `pandoc` - reset it so CMD runs as a command
ENTRYPOINT []

# GitHub-ish styling for the long-form rendering
COPY pandoc.css /pandoc.css

# HTML renderer entry (defaults: -> /docs/dist/site/draft/index.html)
COPY render-draft.sh /usr/local/bin/render-draft
RUN chmod +x /usr/local/bin/render-draft

WORKDIR /docs

CMD ["/usr/local/bin/render-draft"]