const path = require('node:path');
const sharp = require('/Users/faruqshabi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const dir = __dirname;
const drafts = [
  ['01-smart-grid-mark.svg', '01 Smart Grid'],
  ['02-search-orbit-mark.svg', '02 Search Orbit'],
  ['03-private-home-mark.svg', '03 Private Home'],
  ['04-launch-ribbon-mark.svg', '04 Launch Ribbon'],
  ['05-organized-stack-mark.svg', '05 Organized Stack'],
  ['06-vibe-monogram-mark.svg', '06 Vibe Monogram'],
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
      <text x="72" y="96" font-family="Arial, Helvetica, sans-serif" font-size="27" fill="#506070">Smart Launcher logo replacement drafts</text>
      <text x="72" y="164" font-family="Arial, Helvetica, sans-serif" font-size="58" font-weight="760" fill="#172033">First six directions</text>
      <text x="1208" y="164" font-family="Arial, Helvetica, sans-serif" font-size="25" fill="#506070">1024x1024 SVG masters with PNG previews</text>
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
    .toFile(path.join(dir, 'logo-drafts-contact-sheet.png'));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
