// Render one mermaid .mmd file to an SVG, using the slidev image's Chromium.
//
// mermaid v11 is ESM-only and its entry pulls chunks/ relative to itself, so the
// bundle is served over a loopback HTTP server and loaded as a native module.
//
//   docker compose --profile slides run --rm -v "$PWD/scripts:/scripts" --entrypoint sh slides-build \
//     -c "NODE_PATH=/usr/local/lib/node_modules node /scripts/render-diagram.cjs <in.mmd> <out.svg>"
const fs = require('fs');
const http = require('http');
const { chromium } = require('playwright-chromium');

const [, , srcPath, outPath] = process.argv;
if (!srcPath || !outPath) {
  console.error('usage: render-diagram.cjs <in.mmd> <out.svg>');
  process.exit(1);
}

const MERMAID_ESM = '/deps/node_modules/mermaid/dist/mermaid.esm.min.mjs';
const MIME = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.html': 'text/html' };

const pageHtml = () =>
  `<body><div id="c"></div>
  <script type="module">
    import mermaid from "/mermaid.esm.min.mjs";
    window.mermaid = mermaid;
  </script></body>`;

(async () => {
  const code = fs.readFileSync(srcPath, 'utf8');
  const bundle = fs.readFileSync(MERMAID_ESM);

  const DIST = '/deps/node_modules/mermaid/dist';
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]);
    if (rel === '/' || rel === '') {
      res.writeHead(200, { 'Content-Type': MIME['.html'] });
      res.end(pageHtml());
      return;
    }
    const file = `${DIST}${rel}`;
    const ct = MIME[rel.slice(rel.lastIndexOf('.'))] || 'text/plain';
    try {
      const body = file === '/mermaid.esm.min.mjs' ? bundle : fs.readFileSync(file);
      res.writeHead(200, { 'Content-Type': ct });
      res.end(body);
    } catch {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('no file ' + rel);
      console.error('404:', rel);
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();

  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.error('pageerror:', e.message));
  page.on('console', (m) => console.error('console:', m.type(), m.text()));

  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load' });
  await page.waitForFunction('typeof window.mermaid !== "undefined"', null, { timeout: 20000 });

  const svg = await page.evaluate(async ({ code }) => {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'loose',
      theme: 'default',
      flowchart: { htmlLabels: true, curve: 'basis' },
    });
    const { svg } = await mermaid.render('mmd' + Date.now(), code);
    return svg;
  }, { code });

  await browser.close();
  server.close();
  fs.writeFileSync(outPath, svg);
  console.log(`rendered ${outPath} (${(svg.length / 1024).toFixed(1)} kB)`);
})().catch((e) => { console.error(e); process.exit(1); });
