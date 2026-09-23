# About

Sample solution for the [Nansen Senior Data Engineer take-home](spec.md):
the foundations of a pipeline that produces **valuable labels for blockchain
addresses**, plus a fully local, Docker-only working sample of one slice.

## What's here

| Path | What |
| --- | --- |
| `spec.md` | The assignment (cleaned up) |
| `docs/slides.md` | The presentation — Slidev, rendered via Docker |
| `docker-compose.yml` | The whole stack, root compose file |
| `dockerfiles/` | Dockerfiles, one per tool |

## The presentation

The deck is `docs/slides.md` (plain markdown, [Slidev](https://sli.dev)) — the full
solution document: discussion, label design, architecture, and the sample
pipelines. Everything runs in containers — **no Node, Python or npm on the host**.

```bash
# live deck with presenter notes: http://localhost:3030
docker compose --profile slides up slides

# one-shot PDF export -> docs/dist/slides.pdf
docker compose --profile slides run --rm slides-export

# static SPA build -> docs/dist/site/ (what CI deploys to GitHub Pages)
docker compose --profile slides run --rm slides-build
```

First run builds the Slidev image (Node 22 + headless Chromium for exports).

The deck is also published to GitHub Pages on every push to `main` that touches
it (`.github/workflows/slides-pages.yml`) — see
**Settings → Pages → Source: GitHub Actions** to enable it (one-time). Once
enabled, the interactive deck lives at:

> <https://cortajarena.github.io/cor-sample-nansen/>

with a built-in "Download PDF" button for offline viewing.

## The pipeline sample

The working sample is the **label engine slice** — see the deck for the full
architecture and trade-offs. Once the pipeline services land:

```bash
docker compose up --build
```

## Repository layout

```text
cor-sample-nansen/
├── docker-compose.yml      # root compose: deck services now, pipeline services soon
├── dockerfiles/
│   └── slidev.Dockerfile   # Slidev CLI + theme + headless Chromium
├── docs/
│   └── slides.md           # the presentation (Slidev source)
├── spec.md                 # the assignment
└── README.md               # this file
```