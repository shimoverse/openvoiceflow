import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceDir = path.join(root, "docs");
const outputDir = path.join(root, "public");

if (!fs.existsSync(path.join(sourceDir, "index.html"))) {
  throw new Error(`Missing docs/index.html at ${sourceDir}`);
}

// Internal working documents that must never be published to the website.
const EXCLUDED_TOP_LEVEL = new Set(["superpowers"]);

fs.rmSync(outputDir, { recursive: true, force: true });
fs.mkdirSync(outputDir, { recursive: true });
fs.cpSync(sourceDir, outputDir, {
  recursive: true,
  filter: (src) => {
    const rel = path.relative(sourceDir, src);
    const topLevel = rel.split(path.sep)[0];
    return !EXCLUDED_TOP_LEVEL.has(topLevel);
  },
});

console.log(`Copied ${sourceDir} -> ${outputDir} (excluded: ${[...EXCLUDED_TOP_LEVEL].join(", ")})`);
