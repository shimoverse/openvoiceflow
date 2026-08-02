// Art-direction stills: node stills.mjs 2.4 7.1 10.6 …
// Renders single frames so you can review composition BEFORE the full
// render. Same discovery + sizing logic as render.mjs.
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const T = JSON.parse(fs.readFileSync(path.join(dir, 'timings.js'), 'utf8')
  .trim().replace(/^window\.TIMING\s*=\s*/, '').replace(/;$/, ''));
const W = T.width || 1920, H = T.height || 1080;

function findChromium() {
  if (process.env.CHROMIUM && fs.existsSync(process.env.CHROMIUM)) return process.env.CHROMIUM;
  const globs = [];
  if (process.env.PLAYWRIGHT_BROWSERS_PATH) globs.push(process.env.PLAYWRIGHT_BROWSERS_PATH);
  globs.push(path.join(process.env.HOME || '', '.cache/ms-playwright'));
  for (const root of globs) {
    if (!fs.existsSync(root)) continue;
    for (const d of fs.readdirSync(root).filter(n => n.startsWith('chromium')).sort().reverse()) {
      for (const rel of ['chrome-linux/chrome', 'chrome-mac/Chromium.app/Contents/MacOS/Chromium']) {
        const p = path.join(root, d, rel);
        if (fs.existsSync(p)) return p;
      }
    }
  }
  for (const c of ['/opt/pw-browsers', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome',
                   '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']) {
    if (!fs.existsSync(c)) continue;
    if (fs.statSync(c).isFile()) return c;
    for (const d of fs.readdirSync(c).filter(n => n.startsWith('chromium')).sort().reverse()) {
      const p = path.join(c, d, 'chrome-linux/chrome');
      if (fs.existsSync(p)) return p;
    }
  }
  throw new Error('No Chromium found. Set CHROMIUM=/path/to/chrome, or: npm i playwright && npx playwright install chromium');
}

const times = process.argv.slice(2).map(Number);
const browser = await chromium.launch({ executablePath: findChromium(),
  args: ['--force-color-profile=srgb', '--disable-lcd-text', '--hide-scrollbars'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(dir, 'film.html'));
await page.evaluate('window.filmReady');
for (const t of times) {
  await page.evaluate(`window.seek(${t})`);
  await page.screenshot({ path: path.join(dir, `still-${t.toFixed(1)}.jpg`), type: 'jpeg', quality: 92 });
  console.log('still', t);
}
await browser.close();
