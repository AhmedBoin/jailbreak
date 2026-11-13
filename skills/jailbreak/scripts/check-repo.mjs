// Repository checks for a Jailbreak clone.
// Cross-platform: any OS with Node 16 or newer, no dependencies.
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { extname, join, relative, resolve, dirname } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import os from "node:os";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = resolve(SCRIPT_DIR, "..", "..", "..");
const TEXT_EXTENSIONS = new Set([
  ".md", ".txt", ".cs", ".py", ".ps1", ".sh", ".cmd", ".bat", ".js", ".mjs", ".ts",
  ".json", ".yml", ".yaml", ".toml", ".svg", ".html", ".css", ".c", ".h", ".cc", ".cpp", ".hpp",
  ".go", ".rs", ".java", ".kt", ".swift", ".m", ".mm", ".rb", ".php", ".lua", ".sql",
]);
const BINARY_EXTENSIONS = new Set([
  ".exe", ".dll", ".sys", ".scr", ".com", ".msi", ".dylib", ".so",
  ".dmg", ".pkg", ".deb", ".rpm", ".appimage", ".crx", ".xpi",
]);
const MAX_BYTES = 20 * 1024 * 1024;

const HOME_PATH = /(?:[A-Za-z]:[\\/]Users[\\/]|\/Users\/|\/home\/)[^\\/\s"'`]+/;
const SHELL_PATH = /\b(?:Desktop|OneDrive)[\\/]/i;
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const ALLOWED_EMAIL_SUFFIX = "users.noreply.github.com";

function parseRoot(argv) {
  const index = argv.indexOf("--root");
  if (index === -1) return DEFAULT_ROOT;
  const value = argv[index + 1];
  if (!value) {
    console.error("error: --root needs a path");
    process.exit(2);
  }
  return resolve(value);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function identityPatterns() {
  const values = [os.userInfo().username, os.hostname()];
  return values
    .filter((value) => value && value.length >= 4)
    .map((value) => new RegExp(`\\b${escapeRegExp(value)}\\b`, "i"));
}

function fail(failures, message) {
  failures.push(message);
}

function checkProjects(root, failures) {
  const domainsDir = join(root, "domains");
  if (!existsSync(domainsDir)) return;
  for (const domain of readdirSync(domainsDir, { withFileTypes: true })) {
    if (!domain.isDirectory()) continue;
    const domainDir = join(domainsDir, domain.name);
    for (const project of readdirSync(domainDir, { withFileTypes: true })) {
      if (!project.isDirectory()) continue;
      const projectDir = join(domainDir, project.name);
      const label = `${domain.name}/${project.name}`;
      if (!existsSync(join(projectDir, "README.md"))) {
        fail(failures, `project is missing README.md: ${label}`);
      }
      const playbooks = readdirSync(projectDir).filter((name) => /^playbook.*\.md$/i.test(name));
      if (playbooks.length === 0) {
        fail(failures, `project is missing a playbook: ${label}`);
      }
    }
  }
}

function checkSkill(root, failures) {
  const skillDir = join(root, "skills", "jailbreak");
  for (const name of [
    "SKILL.md",
    "references/playbook-template.md",
    "references/patcher-checklist.md",
    "references/project-readme-template.md",
    "scripts/new-project.mjs",
    "scripts/check-repo.mjs",
    "scripts/hash.mjs",
  ]) {
    if (!existsSync(join(skillDir, name))) fail(failures, `skill file is missing: skills/jailbreak/${name}`);
  }
}

function checkRootFiles(root, failures) {
  for (const name of ["README.md", "LICENSE", "Uncensored.md"]) {
    if (!existsSync(join(root, name))) fail(failures, `required file is missing: ${name}`);
  }
  const licensePath = join(root, "LICENSE");
  if (existsSync(licensePath) && !readFileSync(licensePath, "utf8").includes("MIT License")) {
    fail(failures, "LICENSE does not contain the MIT License header");
  }
  const readmePath = join(root, "README.md");
  if (existsSync(readmePath)) {
    const readme = readFileSync(readmePath, "utf8");
    if (/domains\/[a-z0-9-]+\/[a-z0-9-]+/.test(readme)) {
      fail(failures, "README.md links a specific project; the root README stays generic");
    }
  }
}

function trackedFiles(root, failures) {
  const result = spawnSync(
    "git",
    ["-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  if (result.error || result.status !== 0) {
    fail(failures, "git ls-files failed; run this from a Git clone with git on PATH");
    return [];
  }
  return result.stdout.split("\0").filter(Boolean);
}

function scanContent(relativePath, text, identity, failures) {
  const home = text.match(HOME_PATH);
  if (home) fail(failures, `${relativePath} contains a home directory path: ${home[0]}`);
  const shell = text.match(SHELL_PATH);
  if (shell) fail(failures, `${relativePath} contains a desktop or cloud folder path: ${shell[0]}`);
  for (const match of text.matchAll(EMAIL)) {
    if (!match[0].toLowerCase().endsWith(ALLOWED_EMAIL_SUFFIX)) {
      fail(failures, `${relativePath} contains an email address: ${match[0]}`);
    }
  }
  for (const pattern of identity) {
    const found = text.match(pattern);
    if (found) fail(failures, `${relativePath} contains a local machine or user name: ${found[0]}`);
  }
}

const root = parseRoot(process.argv.slice(2));
const failures = [];
const identity = identityPatterns();
const skillScriptsPrefix = join("skills", "jailbreak", "scripts");

checkRootFiles(root, failures);
checkSkill(root, failures);
checkProjects(root, failures);

const files = trackedFiles(root, failures);
for (const file of files) {
  const absolute = join(root, file);
  if (!existsSync(absolute)) continue;

  const info = statSync(absolute);
  if (info.size > MAX_BYTES) fail(failures, `tracked file is larger than 20 MB: ${file}`);

  const extension = extname(file).toLowerCase();
  const inDomains = relative(root, absolute).replace(/\\/g, "/").startsWith("domains/");
  if (inDomains && BINARY_EXTENSIONS.has(extension)) {
    fail(failures, `compiled or installable binary under domains/: ${file}; publish a guide or source instead`);
  }

  if (relative(root, absolute).replace(/\\/g, "/").startsWith(`${skillScriptsPrefix.replace(/\\/g, "/")}/`)) {
    continue;
  }
  const text = readFileSync(absolute, TEXT_EXTENSIONS.has(extension) ? "utf8" : "latin1");
  scanContent(file, text, identity, failures);
}

if (failures.length > 0) {
  console.error("FAIL");
  for (const failure of failures) console.error(` - ${failure}`);
  process.exit(1);
}

console.log("OK: repository checks passed");
