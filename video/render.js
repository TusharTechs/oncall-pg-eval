// Render build/scenes.html to JPEG frames with headless Chrome (deterministic: each frame = setT(t)).
//   node render.js [fps=24] [from_s] [to_s] [outdir=build/frames]
const { chromium } = require('playwright-core');
const fs = require('fs'), path = require('path');
const fps = +(process.argv[2] || 24), from = +(process.argv[3] || 0), toArg = process.argv[4], out = process.argv[5] || path.join(__dirname, 'build', 'frames');
(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, 'build', 'scenes.html'));
  const total = await page.evaluate(() => DATA.total);
  const to = toArg ? +toArg : total, n0 = Math.round(from * fps), n1 = Math.round(to * fps);
  const t0 = Date.now();
  for (let f = n0; f < n1; f++) {
    await page.evaluate(t => window.setT(t), f / fps);
    await page.screenshot({ path: path.join(out, String(f - n0).padStart(5, '0') + '.jpg'), type: 'jpeg', quality: 92 });
    if ((f - n0) % (fps * 10) === 0) process.stdout.write(`frame ${f - n0}/${n1 - n0} (${((Date.now() - t0) / 1000).toFixed(0)}s)\n`);
  }
  await browser.close();
  console.log(`done: ${n1 - n0} frames in ${((Date.now() - t0) / 1000).toFixed(0)}s -> ${out}`);
})();
