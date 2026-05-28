#!/usr/bin/env node
// create-ccc-magi — npx entry point for CCC-MAGI v0.9.0 installation.
//
// Strategy: thin Node wrapper that clones CCC-MAGI from GitHub to a temp dir,
// then execs `bash install-into.sh <target>` to do the actual install. This
// keeps a single source of truth for install logic (the shell script).
//
// Why Node?
//   - npm provides the cross-platform distribution channel (`npx create-ccc-magi`)
//   - Node is on virtually every dev machine
//   - Bash for executing install-into.sh = standard on Mac/Linux + via Git Bash on Win
//
// Usage:
//   npx create-ccc-magi@latest           # install latest into current dir
//   npx create-ccc-magi@latest --dry-run # show what would happen
//   npx create-ccc-magi@latest --force   # overwrite existing files
//   npx create-ccc-magi@latest --ref v0.9.0  # pin specific harness version

import { execSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_URL = "https://github.com/Ericcccccc777/CCC-MAGI.git";

// ─── Args ─────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let dryRun = false;
let force = false;
let forceLoadBearing = false;
let ref = "main";
let help = false;

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--dry-run" || a === "-n") dryRun = true;
  else if (a === "--force" || a === "-f") force = true;
  else if (a === "--force-load-bearing") forceLoadBearing = true;
  else if (a === "--ref" || a === "-r") { ref = args[++i] || "main"; }
  else if (a === "--help" || a === "-h") help = true;
  else if (a === "--version") {
    // Read our own version from package.json
    const pkgPath = fileURLToPath(new URL("./package.json", import.meta.url));
    const pkg = JSON.parse(execSync(`cat "${pkgPath}"`).toString());
    console.log(pkg.version);
    process.exit(0);
  } else {
    console.error(`Unknown argument: ${a}`);
    console.error(`Try: create-ccc-magi --help`);
    process.exit(1);
  }
}

if (help) {
  console.log(`create-ccc-magi — Install CCC-MAGI v0.9.0 into current directory

USAGE
  npx create-ccc-magi@latest [options]

OPTIONS
  --dry-run, -n            Show what would be installed; don't write anything
  --force, -f              Overwrite existing CCC-MAGI files; bypass git-clean check
  --force-load-bearing     Also overwrite constitution.md / CLAUDE.md / AGENTS.md
  --ref, -r <tag>          Install specific harness version (default: main)
  --version                Print this installer's version and exit
  --help, -h               Show this help

WHAT IT DOES
  1. Verifies prerequisites: git, bash
  2. Clones https://github.com/Ericcccccc777/CCC-MAGI into a temp directory
  3. Executes 'bash install-into.sh <cwd>' from the clone
  4. Cleans up the temp directory
  5. Tells you to open Claude Code / Codex CLI in the target directory

WHAT HAPPENS NEXT (when you open Claude Code)
  Phase 1 — Environment check (~30s, conversational)
    MAGI Core detects what you have (jq, git, claude, codex CLIs).
    Anything missing → conversational install (brew / vendored binary / manual).

  Phase 2 — Project deployment (~3-15 min, conversational)
    Pick Simple (5 questions, smart defaults) or Pro (16 questions, full).
    Can upgrade Simple → Pro anytime later.

PLATFORM SUPPORT
  ✅ macOS (native)
  ✅ Linux (native)
  ✅ Windows + WSL2 (recommended)
  ⚠️  Windows + Git Bash (works for hooks; Tier 2)
  ❌ Windows native PowerShell only (need Git Bash or WSL)

REPO
  https://github.com/Ericcccccc777/CCC-MAGI
`);
  process.exit(0);
}

// ─── Helpers ──────────────────────────────────────────────────────────
function check(cmd, name) {
  try {
    execSync(`command -v ${cmd}`, { stdio: "pipe" });
    return true;
  } catch {
    console.error(`❌ Required tool not found: ${name}`);
    return false;
  }
}

function exit(msg, code = 1) {
  console.error(msg);
  process.exit(code);
}

function log(msg) {
  console.log(msg);
}

// ─── Prereq check ─────────────────────────────────────────────────────
log("🔍 Checking prerequisites...");

const hasGit = check("git", "git");
const hasBash = check("bash", "bash");

if (!hasGit) {
  exit(`
git is required to fetch CCC-MAGI from GitHub.

Install:
  macOS:           xcode-select --install
  Debian/Ubuntu:   sudo apt install git
  RHEL/CentOS:     sudo yum install git
  Windows:         winget install Git.Git  (recommended — includes Git Bash)
                   OR enable WSL2 and use Linux git

After install, retry: npx create-ccc-magi@latest
`);
}

if (!hasBash) {
  exit(`
bash is required to execute the install script.

  macOS/Linux:     bash is bundled by default
  Windows native:  install Git for Windows (includes Git Bash) — winget install Git.Git
                   OR use WSL2: wsl --install -d Ubuntu

After install, retry: npx create-ccc-magi@latest
`);
}

log("  ✓ git, bash present");

// ─── Target directory ─────────────────────────────────────────────────
const target = resolve(process.cwd());
log(`📂 Install target: ${target}`);

// ─── Git-clean check (unless --force) ─────────────────────────────────
if (!force && !dryRun) {
  try {
    const isRepo = spawnSync("git", ["-C", target, "rev-parse", "--is-inside-work-tree"], {
      stdio: "pipe",
    });
    if (isRepo.status === 0) {
      const status = spawnSync("git", ["-C", target, "status", "--porcelain"], { stdio: "pipe" });
      const dirty = (status.stdout?.toString() || "").trim();
      if (dirty) {
        console.error(`
⚠️  Working tree at ${target} has uncommitted changes.

CCC-MAGI installs files into your project; doing this on a dirty tree mixes
harness changes with your in-progress edits. Recommended:

  cd "${target}"
  git status         # review what's uncommitted
  git stash          # set aside, install, then git stash pop
  # — or —
  git commit -am "wip" # commit, then install

Or override with --force to install anyway.
`);
        process.exit(1);
      }
    } else {
      console.warn(`
⚠️  ${target} is not a git repository.

CCC-MAGI expects to live inside a git repo (most hooks check git state, the
\`/resume\` skill uses branch names, etc.). Strongly recommend running:

  cd "${target}"
  git init

before installing. Or override with --force to install anyway.
`);
      process.exit(1);
    }
  } catch (e) {
    // Couldn't determine; warn but proceed
    console.warn(`  ⚠ git status check failed (${e.message}); proceeding`);
  }
}

// ─── Clone CCC-MAGI to temp dir ───────────────────────────────────────
log(`📥 Cloning CCC-MAGI (ref: ${ref}) to temp...`);

const tempDir = mkdtempSync(join(tmpdir(), "ccc-magi-install-"));
const cloneArgs = ["clone", "--depth", "1", "--branch", ref, REPO_URL, tempDir];

const cloneResult = spawnSync("git", cloneArgs, { stdio: "inherit" });
if (cloneResult.status !== 0) {
  // Cleanup
  try { rmSync(tempDir, { recursive: true, force: true }); } catch {}
  exit(`
git clone failed.

Common causes:
  - Network issue / behind corporate proxy
  - Invalid --ref value (must be a valid branch or tag)
  - GitHub temporarily unreachable

Retry: npx create-ccc-magi@latest
Or pin a known-good version: npx create-ccc-magi@latest --ref v0.9.0
`);
}

log(`  ✓ Cloned to ${tempDir}`);

// ─── Execute install-into.sh ──────────────────────────────────────────
const installScript = join(tempDir, "install-into.sh");
if (!existsSync(installScript)) {
  try { rmSync(tempDir, { recursive: true, force: true }); } catch {}
  exit(`
Expected install script not found in the clone: ${installScript}

This is a bug in the CCC-MAGI repo at ref '${ref}'. Try --ref main or
report at: https://github.com/Ericcccccc777/CCC-MAGI/issues
`);
}

log(`🛠️  Running install-into.sh...`);
log(``);

// Build install-into.sh args
const installArgs = [installScript, target];
if (dryRun) installArgs.push("--dry-run");
if (force) installArgs.push("--force");
if (forceLoadBearing) installArgs.push("--force-load-bearing");

const installResult = spawnSync("bash", installArgs, { stdio: "inherit" });

// ─── Cleanup temp dir ─────────────────────────────────────────────────
try {
  rmSync(tempDir, { recursive: true, force: true });
  log(``);
  log(`  ✓ Cleaned up temp clone`);
} catch (e) {
  console.warn(`  ⚠ Temp dir cleanup failed (${e.message}); leftover at ${tempDir}`);
}

// ─── Exit with install script's code ──────────────────────────────────
process.exit(installResult.status ?? 1);
