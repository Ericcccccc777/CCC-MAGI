#!/usr/bin/env node
// create-ccc-harness
//
// Install CCC-Harness into the current working directory.
//
// USAGE:
//   npx create-ccc-harness@latest             # install into cwd
//   npx create-ccc-harness@latest --dry-run   # show what would be done; don't write files
//   npx create-ccc-harness@latest --force     # overwrite existing CCC-Harness files
//   npx create-ccc-harness@latest --ref <tag> # install a specific tag/branch (default: main)
//
// FLOW:
//   1. Sanity checks (git installed, working dir is a git repo, working tree clean)
//   2. Pre-install detection — warn if existing harness configs present (does NOT
//      run the AI-driven 3-option menu; that's the bootstrap's job AFTER files
//      are on disk. We just give the user a heads-up.)
//   3. Download CCC-Harness from GitHub
//   4. Move files to canonical locations
//   5. Set executable permissions on shell scripts
//   6. Print next-steps prompt (open Claude Code; AI will run bootstrap automatically)
//
// This is a Round-3 MVP stub. The git clone URL is a placeholder until the
// CCC-Harness repo is published. See `_TODO_PRE_PUBLISH` in package.json.

import { execSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, chmodSync, writeFileSync, copyFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { argv, cwd, exit, stderr, stdout } from "node:process";

// ─────────────────────────────────────────────────────────────────────
// Constants — UPDATE when publishing
// ─────────────────────────────────────────────────────────────────────

const HARNESS_REPO = "https://github.com/Ericcccccc777/CCC-Harness.git";
const DEFAULT_REF = "main";
const TEMP_DIR = ".ccc-harness-temp";

// File mapping: source path in harness repo → destination in user project
// Mirrors `outcome/skills/init/SKILL.md § Step 4 — File mappings`.
const FILE_MAPPINGS = [
  { src: "constitution.md", dst: "constitution.md", type: "file" },
  { src: "CLAUDE.md",       dst: "CLAUDE.md",       type: "file" },
  { src: "AGENTS.md",       dst: "AGENTS.md",       type: "file" },
  { src: "skills",          dst: ".harness/skills", type: "dir"  },
  { src: "agents",          dst: ".harness/agents", type: "dir"  },
  { src: "scripts",         dst: ".harness/scripts", type: "dir" },
  { src: "cli-configs/claude/settings.json", dst: ".claude/settings.json", type: "json-merge" },
  { src: "cli-configs/codex/config.toml",    dst: ".codex/config.toml",    type: "file" },
  { src: "cli-configs/codex/hooks.json",     dst: ".codex/hooks.json",     type: "json-merge" },
  { src: "docs-harness",    dst: "docs-harness",    type: "dir"  },
  // cli-configs/README.md MUST come AFTER the docs-harness dir mapping above.
  // The dir mapping uses renameSync to move the whole directory; if a file mapping
  // pre-created docs-harness/ first, the dir mapping would either skip (no --force)
  // or wipe the pre-staged file (with --force). Order matters.
  { src: "cli-configs/README.md",            dst: "docs-harness/cli-configs-README.md", type: "file" },
  { src: ".gitignore",      dst: ".gitignore",      type: "file", optional: true },
  { src: "README.md",       dst: "CCC_HARNESS_README.md", type: "file" }, // user's own README is preserved
  { src: "LICENSE",         dst: "CCC_HARNESS_LICENSE",   type: "file" }, // user's own LICENSE is preserved
];

// Existing harness detection patterns. Mirrors `outcome/scripts/standalone-bootstrap.md § Step A`.
// Lighter version — npx installer just gives a heads-up; AI-driven bootstrap does the real work.
const KNOWN_HARNESS_MARKERS = [
  ".bmad-core", "bmad-method", ".bmad",
  ".speckit", "speckit.yml", "speckit.yaml",
  ".openspec", ".superpowers", ".ruflo", ".claude-flow",
  ".cursorrules", ".cursor",
  ".clinerules",
  ".windsurfrules",
  ".aider.conf.yml",
  ".github/copilot-instructions.md",
];

// ─────────────────────────────────────────────────────────────────────
// CLI argument parsing (minimal — no external deps)
// ─────────────────────────────────────────────────────────────────────

function parseArgs() {
  const flags = { dryRun: false, force: false, ref: DEFAULT_REF, help: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") flags.dryRun = true;
    else if (a === "--force") flags.force = true;
    else if (a === "--ref") flags.ref = argv[++i] ?? DEFAULT_REF;
    else if (a === "--help" || a === "-h") flags.help = true;
    else {
      stderr.write(`Unknown argument: ${a}\n`);
      exit(1);
    }
  }
  return flags;
}

function printHelp() {
  stdout.write(`create-ccc-harness — install CCC-Harness into your project

Usage:
  npx create-ccc-harness@latest             Install into current directory
  npx create-ccc-harness@latest --dry-run   Show what would be done (no writes)
  npx create-ccc-harness@latest --force     Overwrite existing CCC-Harness files
  npx create-ccc-harness@latest --ref <tag> Install a specific git tag/branch (default: main)

After installation, open Claude Code (or your AI CLI) in this directory.
The AI will detect that CCC-Harness needs configuration and walk you through it.

Docs: ${HARNESS_REPO.replace(".git", "#readme")}
`);
}

// ─────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────

function log(msg) { stdout.write(msg + "\n"); }
function warn(msg) { stderr.write(`⚠️  ${msg}\n`); }
function fail(msg) { stderr.write(`❌ ${msg}\n`); exit(1); }
function ok(msg) { stdout.write(`✅ ${msg}\n`); }

function commandExists(cmd) {
  const result = spawnSync("which", [cmd], { stdio: "ignore" });
  return result.status === 0;
}

function isGitRepo(dir) {
  return existsSync(join(dir, ".git"));
}

function gitClean(dir) {
  const r = spawnSync("git", ["-C", dir, "status", "--porcelain"], { encoding: "utf8" });
  return r.status === 0 && r.stdout.trim() === "";
}

function detectExistingHarnesses(dir) {
  const found = [];
  for (const marker of KNOWN_HARNESS_MARKERS) {
    if (existsSync(join(dir, marker))) found.push(marker);
  }
  // Also check for CCC-Harness itself (re-install case)
  if (existsSync(join(dir, "constitution.md"))) found.push("constitution.md (likely CCC-Harness)");
  if (existsSync(join(dir, ".harness"))) found.push(".harness/ (likely CCC-Harness)");
  return found;
}

function exists(path) { return existsSync(path); }

function ensureDir(path) {
  if (!exists(path)) mkdirSync(path, { recursive: true });
}

function moveAll(srcDir, dstDir) {
  ensureDir(dstDir);
  for (const entry of readdirSync(srcDir)) {
    const src = join(srcDir, entry);
    const dst = join(dstDir, entry);
    if (exists(dst)) rmSync(dst, { recursive: true, force: true });
    renameSync(src, dst);
  }
}

function chmodExecutable(dir) {
  if (!exists(dir)) return;
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (path.endsWith(".sh")) {
      try { chmodSync(path, 0o755); } catch (e) { /* ignore */ }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// JSON merge for .claude/settings.json and .codex/hooks.json
//
// Why: if the user already has a settings.json (MCP perms, custom hooks),
// plain copy either skips (no --force → our bootstrap hook never wires up)
// or clobbers (--force → wipes user's perms). Merge instead.
//
// Rules:
//   1. Target absent → copy ours verbatim.
//   2. Target present →
//      a. Back up to <path>.pre-ccc-harness ONCE (skip if backup exists).
//      b. For each of our hook entries (identified by inner command string),
//         check if any of those commands already exist in the corresponding
//         event array; if all of ours-in-this-entry are already present,
//         skip (idempotent re-run). Otherwise append our entry.
//      c. permissions.allow array: union ours with user's (user order first,
//         ours appended if not already present).
//      d. Preserve all other user keys untouched.
//      e. Write merged JSON with 2-space indent.
//
// Returns one of: "created" (target didn't exist), "merged-backedup" (first
// merge into pre-existing user file), "merged" (subsequent re-merge).
// Throws on parse error / write error.
// ─────────────────────────────────────────────────────────────────────

function mergeJsonSettings(srcPath, dstPath) {
  if (!exists(dstPath)) {
    ensureDir(join(dstPath, ".."));
    copyFileSync(srcPath, dstPath);
    return "created";
  }

  let userJson, ourJson;
  try {
    userJson = JSON.parse(readFileSync(dstPath, "utf8"));
  } catch (e) {
    throw new Error(`${dstPath} exists but is not valid JSON: ${e.message}`);
  }
  try {
    ourJson = JSON.parse(readFileSync(srcPath, "utf8"));
  } catch (e) {
    throw new Error(`Source ${srcPath} is not valid JSON: ${e.message}`);
  }

  // Back up ONCE.
  const backup = `${dstPath}.pre-ccc-harness`;
  let backedUp = false;
  if (!exists(backup)) {
    copyFileSync(dstPath, backup);
    backedUp = true;
  }

  // Collect command strings from an event-level entries array.
  // Shape: [ { hooks: [ { command: "..." }, ... ], ... }, ... ]
  function commandsInEventArray(arr) {
    const cmds = [];
    if (!Array.isArray(arr)) return cmds;
    for (const entry of arr) {
      const inner = (entry && entry.hooks) || [];
      if (!Array.isArray(inner)) continue;
      for (const h of inner) {
        if (h && typeof h.command === "string") cmds.push(h.command);
      }
    }
    return cmds;
  }

  // Merge a single event (e.g. UserPromptSubmit): keep user entries as-is,
  // append our entries unless all of their inner commands already exist in user.
  function mergeEvent(eventName) {
    const userRaw = (userJson.hooks && userJson.hooks[eventName]);
    const ourRaw  = (ourJson.hooks  && ourJson.hooks[eventName]);
    const userArr = Array.isArray(userRaw) ? userRaw : [];
    const ourArr  = Array.isArray(ourRaw)  ? ourRaw  : [];
    const userCmds = new Set(commandsInEventArray(userArr));
    const merged = [...userArr];
    for (const ourEntry of ourArr) {
      const inner = (ourEntry && ourEntry.hooks) || [];
      const ourEntryCmds = inner
        .filter(h => h && typeof h.command === "string")
        .map(h => h.command);
      if (ourEntryCmds.length > 0 && ourEntryCmds.every(c => userCmds.has(c))) {
        // All commands in this entry already present → idempotent skip.
        continue;
      }
      merged.push(ourEntry);
    }
    return merged;
  }

  // Build merged hooks object — only override keys whose VALUES are arrays.
  // Documentation keys like `_comment` (string value) are NOT events and must
  // be preserved verbatim; the unfiltered Object.keys + Set approach would
  // silently overwrite them with [].
  const userHooks = userJson.hooks || {};
  const ourHooks  = ourJson.hooks  || {};
  const eventNames = new Set([
    ...Object.keys(userHooks).filter(k => Array.isArray(userHooks[k])),
    ...Object.keys(ourHooks).filter(k => Array.isArray(ourHooks[k])),
  ]);
  const mergedHooks = { ...userHooks };
  for (const ev of eventNames) {
    mergedHooks[ev] = mergeEvent(ev);
  }

  // Build merged permissions.allow (only if either side has one).
  const userPerms = (userJson.permissions && userJson.permissions.allow) || null;
  const ourPerms  = (ourJson.permissions  && ourJson.permissions.allow)  || null;
  let mergedAllow = null;
  if (userPerms || ourPerms) {
    const userAllow = Array.isArray(userPerms) ? userPerms : [];
    const ourAllow  = Array.isArray(ourPerms)  ? ourPerms  : [];
    const seen = new Set(userAllow);
    mergedAllow = [...userAllow];
    for (const p of ourAllow) {
      if (!seen.has(p)) {
        mergedAllow.push(p);
        seen.add(p);
      }
    }
  }

  // Assemble merged JSON: clone user, override hooks + permissions.allow.
  const merged = { ...userJson, hooks: mergedHooks };
  if (mergedAllow !== null) {
    merged.permissions = { ...(userJson.permissions || {}), allow: mergedAllow };
  }

  writeFileSync(dstPath, JSON.stringify(merged, null, 2) + "\n");
  return backedUp ? "merged-backedup" : "merged";
}

// ─────────────────────────────────────────────────────────────────────
// Main install flow
// ─────────────────────────────────────────────────────────────────────

function main() {
  const flags = parseArgs();
  if (flags.help) { printHelp(); exit(0); }

  const targetDir = resolve(cwd());
  log(`\n📦 create-ccc-harness — installing into: ${targetDir}\n`);

  // ── Sanity checks ───────────────────────────────────────────────
  if (!commandExists("git")) {
    fail("git is not installed. Install git and re-run.");
  }
  if (!isGitRepo(targetDir)) {
    warn("Current directory is not a git repository.");
    warn("CCC-Harness expects a git repo (for diff-based hooks, commit-stage gates, etc.).");
    warn("Run `git init` first, OR continue anyway with --force (some features won't work).");
    if (!flags.force) {
      fail("Aborting. Use --force to install anyway.");
    }
  } else if (!gitClean(targetDir)) {
    warn("Working tree has uncommitted changes.");
    warn("This is risky — installation overwrites files. Recommend committing or stashing first.");
    if (!flags.force) {
      fail("Aborting. Commit/stash your changes, OR use --force.");
    }
  }

  // ── Pre-install detection ──────────────────────────────────────
  const existing = detectExistingHarnesses(targetDir);
  if (existing.length > 0) {
    log("");
    warn("Detected possible existing harness configs in this project:");
    for (const m of existing) log(`    • ${m}`);
    log("");
    log("CCC-Harness can handle existing configs gracefully — the AI-driven bootstrap");
    log("will run after install and ask you what to do (archive / overwrite / decline).");
    log("");
    log("This installer just gets the files on disk. The smart 3-option menu happens");
    log("inside Claude Code after install. See:");
    log("  .harness/scripts/standalone-bootstrap.md");
    log("");
  }

  // ── Dry run? ────────────────────────────────────────────────────
  if (flags.dryRun) {
    log("📋 DRY RUN — files that would be installed:");
    for (const m of FILE_MAPPINGS) {
      const status = m.optional ? " (optional)" : "";
      log(`    ${m.src.padEnd(36)} → ${m.dst}${status}`);
    }
    log("\n(No files modified.)");
    exit(0);
  }

  // ── Clone the harness ──────────────────────────────────────────
  const tempPath = join(targetDir, TEMP_DIR);
  if (exists(tempPath)) {
    log(`Cleaning up stale ${TEMP_DIR}/ from a previous run...`);
    rmSync(tempPath, { recursive: true, force: true });
  }

  log(`Downloading CCC-Harness from ${HARNESS_REPO} (ref: ${flags.ref})...`);
  const cloneResult = spawnSync("git", [
    "clone", "--depth", "1",
    "--branch", flags.ref,
    HARNESS_REPO, tempPath,
  ], { stdio: "inherit" });

  if (cloneResult.status !== 0) {
    fail(`git clone failed (exit ${cloneResult.status}). Check the repo URL: ${HARNESS_REPO}`);
  }
  ok("Downloaded.");

  // Strip the cloned repo's .git so we don't end up with a nested repo
  rmSync(join(tempPath, ".git"), { recursive: true, force: true });

  // ── Move files to canonical locations ──────────────────────────
  // Load-bearing files carry the Bootstrap Status Check block + other entry-point logic.
  // If we skip these due to a name collision (e.g., macOS case-insensitive FS treating
  // `claude.md` and `CLAUDE.md` as the same file), the harness simply doesn't work.
  // Strategy: back up the user's file to <name>.pre-ccc-harness, then install ours.
  const LOAD_BEARING = ["constitution.md", "CLAUDE.md", "AGENTS.md"];
  const SIGNATURES = {
    "CLAUDE.md": "Bootstrap Status Check",
    "constitution.md": "SLOT REGISTRY",
    "AGENTS.md": "external auditor model",
  };

  function backupExisting(dstPath) {
    let backup = `${dstPath}.pre-ccc-harness`;
    if (exists(backup)) {
      const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, -5);
      backup = `${dstPath}.pre-ccc-harness.${ts}`;
    }
    renameSync(dstPath, backup);
    return backup;
  }

  log("\nPlacing files...");
  let backedUpCount = 0;
  for (const m of FILE_MAPPINGS) {
    const src = join(tempPath, m.src);
    const dst = join(targetDir, m.dst);

    if (!exists(src)) {
      if (m.optional) {
        log(`  ${m.src} — not in repo (optional, skipping)`);
        continue;
      }
      warn(`  ${m.src} — expected but not found in repo. Skipping.`);
      continue;
    }

    // Special handling: load-bearing files always install, with backup
    if (LOAD_BEARING.includes(m.dst) && exists(dst)) {
      const sig = SIGNATURES[m.dst];
      let isOurVersion = false;
      if (sig) {
        try {
          const content = readFileSync(dst, "utf8");
          isOurVersion = content.includes(sig);
        } catch { /* ignore */ }
      }
      if (isOurVersion) {
        log(`  ↻ ${m.src.padEnd(36)} → ${m.dst}  (existing CCC-Harness version; reinstalling fresh)`);
        rmSync(dst, { force: true });
        renameSync(src, dst);
      } else {
        const backupPath = backupExisting(dst);
        const backupName = basename(backupPath);
        log(`  ⚠ ${m.src.padEnd(36)} → ${m.dst}  (user file backed up to ${backupName})`);
        renameSync(src, dst);
        backedUpCount++;
      }
      continue;
    }

    // JSON merge: settings.json / hooks.json — never plain-overwrite, never skip.
    // Always merge ours into user's (creates target if absent; preserves user content if present).
    if (m.type === "json-merge") {
      try {
        const result = mergeJsonSettings(src, dst);
        if (result === "created") {
          log(`  ${m.src.padEnd(36)} → ${m.dst}  (new)`);
        } else if (result === "merged-backedup") {
          log(`  ⊕ ${m.src.padEnd(36)} → ${m.dst}  (merged; user file backed up to ${basename(dst)}.pre-ccc-harness)`);
          backedUpCount++;
        } else {
          log(`  ⊕ ${m.src.padEnd(36)} → ${m.dst}  (re-merged; idempotent)`);
        }
      } catch (e) {
        warn(`  ${m.dst} — JSON merge failed: ${e.message}. Skipping.`);
      }
      continue;
    }

    // Non-load-bearing: preserve existing unless --force
    if (exists(dst) && !flags.force) {
      warn(`  ${m.dst} — already exists at destination; preserving (use --force to overwrite)`);
      continue;
    }

    ensureDir(join(dst, ".."));
    if (m.type === "dir") {
      if (exists(dst)) rmSync(dst, { recursive: true, force: true });
      renameSync(src, dst);
    } else {
      renameSync(src, dst);
    }
    log(`  ${m.src.padEnd(36)} → ${m.dst}`);
  }
  if (backedUpCount > 0) {
    log(`\n  ⚠ ${backedUpCount} user file(s) had pre-existing content and were backed up with .pre-ccc-harness suffix.`);
    log(`     The bootstrap flow (inside Claude Code) will ask what to do with the user content.`);
  }

  // ── Set executable on shell scripts ────────────────────────────
  const scriptsDir = join(targetDir, ".harness", "scripts");
  if (exists(scriptsDir)) {
    chmodExecutable(scriptsDir);
    ok("Shell scripts chmod +x'd");
  }

  // ── Clean up ────────────────────────────────────────────────────
  if (exists(tempPath)) rmSync(tempPath, { recursive: true, force: true });
  ok("Temp directory cleaned up");

  // ── Next steps ──────────────────────────────────────────────────
  log("\n────────────────────────────────────────────────────────────────");
  log("✅ CCC-Harness installed.");
  log("────────────────────────────────────────────────────────────────");
  log("");
  log("Next steps:");
  log("");
  log("  1. Open Claude Code (or your AI CLI) in this directory:");
  log("       claude");
  log("");
  log("  2. The AI will detect that CCC-Harness needs configuration");
  log("     (because .harness/state/install.json doesn't exist yet)");
  log("     and walk you through the bootstrap flow:");
  log("       - Scan for any existing harness configs");
  log("       - Present 3-option menu (archive / overwrite / decline)");
  log("       - If you proceed, run /init to fill 16 project-specific questions");
  log("");
  log("  3. Read the docs as needed:");
  log("       - CCC_HARNESS_README.md         (overview)");
  log("       - constitution.md               (project identity placeholder)");
  log("       - CLAUDE.md                     (workflow rules)");
  log("       - docs-harness/adoption-playbook.md  (full install walkthrough)");
  log("");
  log("Questions / issues: " + HARNESS_REPO.replace(".git", "/issues"));
  log("");
}

main();
