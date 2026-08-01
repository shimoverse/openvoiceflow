// Full render: Playwright frames piped straight into x264. Never writes
// frames to disk. Reads fps/duration/width/height from timings.js — the
// single timing source — so nothing here needs editing per film.
import { chromium } from 'playwright-core';
import { spawn, execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const T = JSON.parse(fs.readFileSync(path.join(dir, 'timings.js'), 'utf8')
  .trim().replace(/^window\.TIMING\s*=\s*/, '').replace(/;$/, ''));
const W = T.width || 1920, H = T.height || 1080;
const FRAMES = Math.round(T.fps * T.duration);

function findFFmpeg() {
  if (process.env.FF && fs.existsSync(process.env.FF)) return process.env.FF;
  try {
    return execSync('python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"',
      { encoding: 'utf8' }).trim();
  } catch { /* fall through */ }
  for (const c of ['/usr/local/bin/ffmpeg', '/opt/homebrew/bin/ffmpeg', '/usr/bin/ffmpeg']) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error('No ffmpeg found. pip install imageio-ffmpeg, or set FF=/path/to/ffmpeg (must have libx264).');
}
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

const FF = findFFmpeg();
const ff = spawn(FF, [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(T.fps), '-c:v', 'mjpeg', '-i', 'pipe:0',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart',
  path.join(dir, 'film_video.mp4'),
], { stdio: ['pipe', 'inherit', 'inherit'] });

const browser = await chromium.launch({ executablePath: findChromium(),
  args: ['--force-color-profile=srgb', '--disable-lcd-text', '--hide-scrollbars'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(dir, 'film.html'));
await page.evaluate('window.filmReady');

const t0 = Date.now();
for (let f = 0; f < FRAMES; f++) {
  await page.evaluate(`window.seek(${(f / T.fps).toFixed(5)})`);
  const buf = await page.screenshot({ type: 'jpeg', quality: 94 });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (f % 150 === 0) console.log(`frame ${f}/${FRAMES} (${((Date.now()-t0)/1000).toFixed(0)}s)`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log(`done: ${FRAMES} frames @ ${W}x${H} in ${((Date.now()-t0)/1000).toFixed(0)}s`);
