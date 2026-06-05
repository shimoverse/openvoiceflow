import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceDir = path.join(root, "docs");
const outputDir = path.join(root, "public");

if (!fs.existsSync(path.join(sourceDir, "index.html"))) {
  throw new Error(`Missing docs/index.html at ${sourceDir}`);
}

fs.rmSync(outputDir, { recursive: true, force: true });
fs.mkdirSync(outputDir, { recursive: true });
fs.cpSync(sourceDir, outputDir, { recursive: true });

console.log(`Copied ${sourceDir} -> ${outputDir}`);
