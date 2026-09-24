// Print an HTML file to PDF with the Chromium that ships in the Slidev image.
//
//   NODE_PATH=/usr/local/lib/node_modules node print-pdf.cjs <in.html> <out.pdf>
//
// Waits for the mermaid shim to set <html data-mermaid="ready">, so we never
// print a page of unrendered ```mermaid fences. Playwright (not chromium
// --print-to-pdf directly) because it gives us that wait + real pagination.

const { chromium } = require('playwright-chromium');

const [src, out] = process.argv.slice(2);
if (!src || !out) {
  console.error('usage: print-pdf.cjs <in.html> <out.pdf>');
  process.exit(2);
}

(async () => {
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.goto('file://' + src, { waitUntil: 'load' });
    await page.waitForFunction(
      () => {
        const s = document.documentElement.dataset.mermaid;
        return s === 'ready' || (s || '').startsWith('error');
      },
      null,
      { timeout: 60_000 },
    );
    const state = await page.evaluate(() => document.documentElement.dataset.mermaid);
    if (state !== 'ready') throw new Error('mermaid: ' + state);
    await page.pdf({ path: out, format: 'A4', printBackground: true });
    console.log('pdf ->', out);
  } finally {
    await browser.close();
  }
})();
