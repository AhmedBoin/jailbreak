// Scaffolds domains/<domain>/<project> from the skill templates.
// Cross-platform: any OS with Node 16 or newer, no dependencies.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = resolve(SCRIPT_DIR, "..", "..", "..");
const SLUG = /^[a-z0-9][a-z0-9-]*$/;

const USAGE = `usage: node new-project.mjs --domain <domain> --project <project> --title "<title>"
         [--version <version>] [--summary "<summary>"] [--force] [--root <repo>]`;

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = { version: "1.0", summary: "", force: false, root: DEFAULT_ROOT };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (flag === "--force") {
      options.force = true;
    } else if (flag === "--help" || flag === "-h") {
      console.log(USAGE);
      process.exit(0);
    } else if (["--domain", "--project", "--title", "--version", "--summary", "--root"].includes(flag)) {
      if (value === undefined) fail(`${flag} needs a value`);
      options[flag.slice(2)] = value;
      i += 1;
    } else {
      fail(`unknown argument: ${flag}`);
    }
  }
  return options;
}

const options = parseArgs(process.argv.slice(2));
for (const key of ["domain", "project", "title"]) {
  if (!options[key]) fail(`missing --${key}\n${USAGE}`);
}
if (!SLUG.test(options.domain)) {
  fail("--domain must be lowercase letters, digits, and hyphens, and start with a letter or digit");
}
if (!SLUG.test(options.project)) {
  fail("--project must be lowercase letters, digits, and hyphens, and start with a letter or digit");
}

const repoRoot = resolve(options.root);
const domainsDir = join(repoRoot, "domains");
const templateDir = join(SCRIPT_DIR, "..", "references");
const targetDir = join(domainsDir, options.domain, options.project);

if (!existsSync(domainsDir)) {
  fail(`domains/ not found under ${repoRoot}; run this from a Jailbreak repository clone`);
}

const outputs = [
  ["project-readme-template.md", "README.md"],
  ["playbook-template.md", "playbook.md"],
];
for (const [, name] of outputs) {
  if (existsSync(join(targetDir, name)) && !options.force) {
    fail(`${join(targetDir, name)} already exists; use --force to overwrite the two template files`);
  }
}

const tokens = {
  "{{TITLE}}": options.title,
  "{{DOMAIN}}": options.domain,
  "{{PROJECT}}": options.project,
  "{{VERSION}}": options.version,
  "{{SUMMARY}}": options.summary,
};

mkdirSync(targetDir, { recursive: true });
for (const [templateName, outputName] of outputs) {
  let text = readFileSync(join(templateDir, templateName), "utf8");
  for (const [token, value] of Object.entries(tokens)) {
    text = text.split(token).join(value);
  }
  const outputPath = join(targetDir, outputName);
  writeFileSync(outputPath, text, "utf8");
  console.log(`created ${outputPath}`);
}

console.log(`
Project scaffolded at: ${targetDir}

Next:
  1. Fill README.md and playbook.md with the target data.
  2. Add patcher/ and legacy/ only when they contain files.
  3. Run: node skills/jailbreak/scripts/check-repo.mjs
  4. Commit and push.`);
