import { mkdir } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const jobs = [
  {
    input: "public/assets/brand/logo-mark.svg",
    outputs: [
      { file: "public/favicon-32x32.png", width: 32, height: 32 },
      { file: "public/apple-touch-icon.png", width: 180, height: 180 },
      { file: "public/assets/brand/logo-mark-512.png", width: 512, height: 512 }
    ]
  },
  {
    input: "public/assets/brand/brand-study.svg",
    outputs: [{ file: "public/assets/brand/brand-study.png", width: 1600, height: 2000 }]
  },
  {
    input: "public/social/og-card.svg",
    outputs: [{ file: "public/social/og-card.png", width: 1200, height: 630 }]
  }
];

for (const job of jobs) {
  for (const output of job.outputs) {
    const outputDir = path.dirname(output.file);
    await mkdir(outputDir, { recursive: true });

    await sharp(job.input, { density: 300 })
      .resize(output.width, output.height, {
        fit: "cover"
      })
      .png()
      .toFile(output.file);
  }
}

console.log("Brand assets rendered.");

