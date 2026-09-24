# ---------------------------------------------------------------------------
# Slidev deck toolchain for docs/slides.md
#
# Everything runs in Docker - no host Node/npm is required.
#
#   dev server : docker compose --profile slides up slides
#   pdf export : docker compose --profile slides run --rm slides-export
#   draft pdf  : docker compose --profile slides run --rm draft-pdf
#
# The CLI, the theme and a headless Chromium are installed globally so any
# deck mounted at /slides can use them without npm install on the host.
# ---------------------------------------------------------------------------
FROM node:22-bookworm-slim

# Pin versions for reproducible builds
ARG SLIDEV_CLI_VERSION=53.0.0
ARG SLIDEV_THEME_SERIPH_VERSION=0.25.0
ARG SLIDEV_THEME_DEFAULT_VERSION=0.25.0
ARG PLAYWRIGHT_CHROMIUM_VERSION=1.63.0

# Keep the headless browser out of $HOME (layer-friendly, cache-safe)
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# Slidev CLI + serif theme (deck) + default theme (plain markdown files
# like docs/draft.md, which have no frontmatter) + the Chromium build the
# CLI expects.
RUN npm install -g --no-fund --no-audit \
      @slidev/cli@${SLIDEV_CLI_VERSION} \
      @slidev/theme-seriph@${SLIDEV_THEME_SERIPH_VERSION} \
      @slidev/theme-default@${SLIDEV_THEME_DEFAULT_VERSION} \
      playwright-chromium@${PLAYWRIGHT_CHROMIUM_VERSION}

# Make sure the headless browser is present and has the system libs it needs
RUN node /usr/local/lib/node_modules/playwright-chromium/cli.js install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /slides
EXPOSE 3030

# Compose services always pass an explicit command; this is just a fallback
CMD ["slidev", "--help"]