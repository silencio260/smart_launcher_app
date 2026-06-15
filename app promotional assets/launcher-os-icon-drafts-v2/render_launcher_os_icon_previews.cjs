const path = require('node:path');
const sharp = require('/Users/faruqshabi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const dir = __dirname;
const drafts = [
  ['01-os-home-surface.svg', '01 OS Home Surface'],
  ['02-adaptive-launcher-cells.svg', '02 Adaptive Cells'],
  ['03-drawer-search-core.svg', '03 Drawer Search'],
  ['04-page-stack-dock.svg', '04 Page Stack Dock'],
  ['05-category-orbit.svg', '05 Category Orbit'],
  ['06-themed-launcher-glyph.svg', '06 Themed Glyph'],
];

async function main() {
  for (const [svg] of drafts) {
    await sharp(path.join(dir, svg), { density: 144 })
      .resize(1024, 1024)
      .png()
      .toFile(path.join(dir, svg.replace('.svg', '-preview.png')));
  }

  const width = 1800;
  const height = 1500;
  const cellWidth = 520;
  const cellHeight = 560;
  const gap = 48;
  const startX = 72;
  const startY = 250;

  const labelBlocks = drafts
    .map(([, label], index) => {
      const col = index % 3;
      const row = Math.floor(index / 3);
      const x = startX + col * (cellWidth + gap);
      const y = startY + row * (cellHeight + gap);
      return `<rect x="${x}" y="${y}" width="${cellWidth}" height="${cellHeight}" rx="8" fill="#ffffff" stroke="#d9e3ec"/>
        <text x="${x + 34}" y="${y + 502}" font-family="Arial, Helvetica, sans-serif" font-size="30" font-weight="720" fill="#172033">${label}</text>`;
    })
    .join('');

  const base = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#eef3f7"/>
      <text x="72" y="96" font-family="Arial, Helvetica, sans-serif" font-size="27" fill="#506070">Smart Launcher icon replacement drafts</text>
      <text x="72" y="164" font-family="Arial, Helvetica, sans-serif" font-size="58" font-weight="760" fill="#172033">Launcher OS directions</text>
      <text x="1190" y="164" font-family="Arial, Helvetica, sans-serif" font-size="25" fill="#506070">adaptive-icon style SVG masters</text>
      ${labelBlocks}
    </svg>`);

  const composites = [];
  for (let index = 0; index < drafts.length; index += 1) {
    const [svg] = drafts[index];
    const col = index % 3;
    const row = Math.floor(index / 3);
    const x = startX + col * (cellWidth + gap) + 61;
    const y = startY + row * (cellHeight + gap) + 42;
    const input = await sharp(path.join(dir, svg.replace('.svg', '-preview.png')))
      .resize(398, 398)
      .png()
      .toBuffer();
    composites.push({ input, left: x, top: y });
  }

  await sharp(base)
    .composite(composites)
    .png()
    .toFile(path.join(dir, 'launcher-os-icon-drafts-v2-contact-sheet.png'));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
