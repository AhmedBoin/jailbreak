// Prints SHA256 and size for one or more files.
// Cross-platform: any OS with Node 16 or newer, no dependencies.
import { createHash } from "node:crypto";
import { readFileSync, statSync } from "node:fs";

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("usage: node hash.mjs <file> [file...]");
  process.exit(2);
}

for (const file of files) {
  const bytes = readFileSync(file);
  const digest = createHash("sha256").update(bytes).digest("hex").toUpperCase();
  console.log(`${digest}  ${statSync(file).size}  ${file}`);
}
