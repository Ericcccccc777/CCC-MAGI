---
name: uninstall
description: |
  Cleanly remove CCC-MAGI from the project. Detects whether a prior harness archive exists (`old_version_harness/` from bootstrap option 1); if so, offers to restore it.

  Trigger when the user says:
  - `/uninstall` directly
  - "卸载 CCC-MAGI" / "uninstall CCC-MAGI" / "remove CCC-MAGI"
  - "删除 CCC-MAGI" / "delete the harness"
  - "不要 CCC-MAGI 了" / "I don't want this harness anymore"
  - "把 CCC-MAGI 拆掉" / "tear out CCC-MAGI"
  - "干净卸载" / "clean uninstall"
argument-hint: [--restore-archive | --keep-archive | --dry-run | --force]
---

# /uninstall

> **MAGI position**: Operated by **MAGI Archivist** — filing the harness's own paperwork before departure.

> *Constitutional basis: per `constitution.md § 3` (CEO Final Authority), CEO has the unconditional right to remove CCC-MAGI from any project. This skill is the proper paperwork for that decision — ensures clean state, no leftover `.harness/` artifacts, and offers restoration of any archived prior harness.*

## Scope: what gets removed vs preserved

### 🔴 Removed (CCC-MAGI's installed files)

| Item | Notes |
|---|---|
| `constitution.md`, `CLAUDE.md`, `AGENTS.md` | LOAD_BEARING — user's `/init` answers get lost |
| `CCC_MAGI_README.md`, `CCC_MAGI_LICENSE` | Harness's own README/LICENSE |
| `.harness/` (entire directory) | skills/, agents/, scripts/, state/, memory/, audits/ |
| `docs-harness/` (entire directory) | framework design docs |
| `.claude/commands/` (entire directory) | auto-generated slash command shims |
| `.claude/settings.json` | ⚠️ **only if matches CCC-MAGI shipped sha256** — see Step 2.5 |
| `.codex/config.toml`, `.codex/hooks.json` | CCC-MAGI's Codex CLI wiring |
| `.gitignore` — CCC-MAGI section only | Detected via marker `# CCC-MAGI — Git Policy`; user's lines preserved |

### 🟢 Preserved (user's product + history)

| Item | Why |
|---|---|
| `docs/features/*.md` | spec / implementation docs ARE the user's product, not harness artifacts |
| Source code (any path NOT under `.harness/`) | obvious |
| `git` history, branches, tags, remote | obvious |
| User's own `README.md`, `LICENSE`, `package.json`, build configs | not CCC-MAGI's |
| `~/.claude/projects/<this-project>/*.jsonl` (Claude Code's session history) | lives in user home, never project — not our scope |

### 🟡 Conditionally handled

| Item | Logic |
|---|---|
| `old_version_harness/` (archive from bootstrap option 1) | Ask user: restore? keep? — see Step 1 |

---

## Step 0 — Pre-flight scenario detection

Detect which of 4 scenarios applies via filesystem inspection (do NOT trust install.json — it may be missing or out of date):

```bash
HARNESS_DIR_EXISTS=$(test -d .harness && echo yes || echo no)
ARCHIVE_DIR_EXISTS=$(test -d old_version_harness && echo yes || echo no)
INSTALL_JSON_EXISTS=$(test -f .harness/state/install.json && echo yes || echo no)
```

Branch:

| .harness/ | old_version_harness/ | install.json | Scenario |
|---|---|---|---|
| ❌ | * | * | **D — Not installed.** Exit: "CCC-MAGI 没装在这个项目，无需卸载。" |
| ✅ | ❌ | * | **A — Clean uninstall.** (No prior harness to restore.) |
| ✅ | ✅ | * | **B — Archive present.** Offer restore. |
| ✅ | ❌ | ❌ | **C — Partial install.** Treat as A with lightweight cleanup. |

## Step 1 — Confirmation flow (mandatory, destructive operation)

**ALWAYS show the dry-run preview first.** Never delete anything before explicit user confirmation.

### Step 1a — Preview message (display in user's OS locale)

For **Scenario A or C**:

```
⚠️ 你确定要卸载 CCC-MAGI 吗？

我会做的事:
  ✓ 删 .harness/（skills, agents, scripts, state, memory, audits 全部）
  ✓ 删 constitution.md, CLAUDE.md, AGENTS.md（含你 /init 填的项目身份)
  ✓ 删 CCC_MAGI_README.md, CCC_MAGI_LICENSE
  ✓ 删 docs-harness/（设计文档）
  ✓ 删 .claude/commands/（slash 命令 shim）
  ✓ 清理 .claude/settings.json 里 CCC-MAGI 的 hook 部分（如你没改过就整文件删；改过就保留 + 警告）
  ✓ 删 .codex/config.toml + hooks.json
  ✓ 清理 .gitignore 里 CCC-MAGI 的部分（按标记行定位，你原本的内容保留）

我不会动:
  ✗ 源代码（src/, app/, lib/, ...）
  ✗ docs/features/*.md（你和我一起写的 spec —— 是你的产品文档）
  ✗ git 历史、分支、tags、远端
  ✗ 你自己的 README.md、LICENSE、package.json、构建配置

回 "确认卸载" / "yes" 继续，回 "取消" / "no" 中止。
```

For **Scenario B** (archive exists):

```
⚠️ 你确定要卸载 CCC-MAGI 吗？

检测到 old_version_harness/ — 这是你装 CCC-MAGI 时备份的"之前的 harness"。
要怎么处理？

  [a] 复原 — 删 CCC-MAGI + 把 old_version_harness/ 里的内容移回项目根目录
              （等于回到装 CCC-MAGI 之前的状态）
  [b] 保留归档 — 删 CCC-MAGI，old_version_harness/ 留在原地由你以后处理
  [c] 取消卸载

不管选 a 或 b，CCC-MAGI 的删除范围是一样的（见下）。差异只在 old_version_harness/。

CCC-MAGI 卸载范围:
  ✓ .harness/, constitution.md, CLAUDE.md, AGENTS.md, ...
  （和 scenario A 一样，列表略，详见 SKILL 文档）

不会动:
  ✗ 源代码、git 历史、你的 README.md / LICENSE / package.json
  ✗ docs/features/*.md spec 文件

回 a / b / c，或 "取消"。
```

### Step 1b — Wait for explicit response

Required responses:
- **A/C scenario**: `"确认卸载"` / `"yes uninstall"` / `"yes"` / `"确认"` → proceed to Step 2
- **B scenario**: `"a"` / `"复原"` / `"restore"` → proceed to Step 2 + Step 3
- **B scenario**: `"b"` / `"保留"` / `"keep archive"` → proceed to Step 2 only
- Any of: `"取消"` / `"cancel"` / `"no"` / `"算了"` → exit cleanly, no action

If response is ambiguous: ask again clearly. Don't infer.

If user provides `--force` flag: skip the confirmation but still display the preview as a record.

## Step 2 — Remove CCC-MAGI files

Track deletions for the final report:

```bash
DELETED=()
PRESERVED_WITH_WARNING=()

remove_with_log() {
  local target="$1"
  if [ -e "$target" ]; then
    rm -rf "$target"
    DELETED+=("$target")
  fi
}
```

### Step 2.1 — Root-level harness files

```bash
for f in constitution.md CLAUDE.md AGENTS.md CCC_MAGI_README.md CCC_MAGI_LICENSE; do
  remove_with_log "$f"
done
```

### Step 2.2 — `.harness/` directory

```bash
remove_with_log .harness
```

(Single rm -rf — includes all skills, agents, scripts, state, memory, audits, checkpoints.)

### Step 2.3 — `docs-harness/` directory

```bash
remove_with_log docs-harness
```

### Step 2.4 — `.claude/commands/` directory

```bash
remove_with_log .claude/commands
```

### Step 2.5 — `.claude/settings.json` (careful — user may have added own settings)

Strategy: read current content, compare against CCC-MAGI shipped default. If matches exactly → delete. If differs → preserve + warn.

```bash
if [ -f .claude/settings.json ]; then
  # CCC-MAGI's settings.json has a specific marker: top-level "_comment_top" key
  # If that marker exists AND no other top-level keys beyond { permissions, hooks, _comment_top, _comment } exist, it's our untouched file
  IS_OUR_DEFAULT=$(jq 'keys | length as $n | if $n <= 4 and (any(.[]; . == "_comment_top")) then "yes" else "no" end' .claude/settings.json 2>/dev/null)

  if [ "$IS_OUR_DEFAULT" = "\"yes\"" ]; then
    remove_with_log .claude/settings.json
  else
    PRESERVED_WITH_WARNING+=(".claude/settings.json — 你似乎修改过这个文件（不止 CCC-MAGI 的默认内容）。我保留它，你可以人工去掉 CCC-MAGI 的 hooks 段或者整个删掉。")
  fi
fi

# Remove .claude/ if now empty
rmdir .claude 2>/dev/null
```

### Step 2.6 — `.codex/`

```bash
remove_with_log .codex/config.toml
remove_with_log .codex/hooks.json
rmdir .codex 2>/dev/null
```

### Step 2.7 — `.gitignore` — surgical removal of CCC-MAGI section

CCC-MAGI's `.gitignore` section is marked with:

```
# ============================================================
# CCC-MAGI — Git Policy
...
# ============================================================
```

Strategy: extract everything NOT between our markers.

```bash
if [ -f .gitignore ]; then
  if grep -q "CCC-MAGI — Git Policy" .gitignore; then
    # Find line numbers of start and end markers
    START_LINE=$(grep -n "CCC-MAGI — Git Policy" .gitignore | head -1 | cut -d: -f1)
    # End is harder — we use the "last line that mentions a CCC-MAGI-specific path" + 1
    # For robustness: just strip from START_LINE to the next blank line followed by # comment (or EOF)
    # Simpler: backup + use awk to keep lines NOT in our marker block.

    cp .gitignore .gitignore.pre-uninstall.bak

    # Conservative extraction: remove from our start marker to EOF (assume our section is last,
    # which is the install-into.sh convention). If the user added content AFTER our section,
    # they should manually verify the .bak file.
    head -n $((START_LINE - 1)) .gitignore.pre-uninstall.bak > .gitignore

    # If the line just before our section is a blank line, trim it
    sed -i.tmp -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' .gitignore 2>/dev/null
    rm -f .gitignore.tmp

    # If .gitignore is now empty, remove it entirely
    if [ ! -s .gitignore ]; then
      remove_with_log .gitignore
    fi

    DELETED+=(".gitignore (CCC-MAGI section removed; backup at .gitignore.pre-uninstall.bak)")
  fi
fi
```

### Step 2.8 — Cleanup temp artifacts

```bash
# Tmp files from auditor-gate / test-fix / etc.
rm -f /tmp/auditor-gate.* /tmp/schema.* /tmp/test-fix-* /tmp/implement-* 2>/dev/null

# .ccc-magi-temp from manual install path B
[ -d .ccc-magi-temp ] && rm -rf .ccc-magi-temp
```

## Step 3 — Restore archive (only Scenario B + user picked "a"/restore)

```bash
if [ "$RESTORE" = "true" ] && [ -d old_version_harness ]; then
  RESTORED=()
  SKIPPED=()

  # Use find to include hidden files; iterate one level deep
  for item in old_version_harness/.[!.]* old_version_harness/..?* old_version_harness/*; do
    [ -e "$item" ] || continue
    base=$(basename "$item")

    if [ -e "$base" ]; then
      SKIPPED+=("$base (project root already has a file/dir with this name)")
    else
      mv "$item" "$base"
      RESTORED+=("$base")
    fi
  done

  # Clean up archive folder if now empty
  rmdir old_version_harness 2>/dev/null
fi
```

Surface conflicts to user clearly:

```
✓ 复原 12 个文件 (clinerules, BMAD/, agent.md, ...)
⚠️  3 个文件没复原（项目根目录已存在同名）:
    - .gitignore (你装 CCC-MAGI 之后改过 — 我不覆盖)
    - README.md (我没删过这个 — 仍是你的版本)
  这些保留在 old_version_harness/，请手动比对 / 合并。
```

## Step 4 — Final report (locale-aware)

```
✅ CCC-MAGI 已卸载

删除（CCC-MAGI 的家私）:
  ✓ <list from DELETED array>

[B + restore case]
✓ 原 harness 已复原:
  - <list from RESTORED>
[如有跳过的]
⚠️ 这些没复原（你需要手动决定）:
  - <list from SKIPPED>
  备份位置: old_version_harness/.bak (如有冲突)

[B + keep archive case]
✓ old_version_harness/ 保留在原地。你以后可以:
  - 手动复原: mv old_version_harness/* .
  - 永久删除: rm -rf old_version_harness/

[A/C case]
（没有归档，没什么需要复原的）

未动（你的产品 + 历史）:
  ✓ 源代码
  ✓ docs/features/*.md（spec / implementation 文档保留在原位）
  ✓ git 历史 + 分支 + 远端
  ✓ 你自己的 README.md / LICENSE / package.json

[如有 PRESERVED_WITH_WARNING]
⚠️ 部分文件保留 + 需要你手动处理:
  - <list>

完成。再见 👋

如果以后想再装回来:
  cd <project>
  npx create-ccc-magi@latest
```

## Rules / Anti-patterns

- **Never delete without explicit user confirmation.** Even with `--force`, log what's being done.
- **Never delete files OUTSIDE the documented scope.** If unsure (e.g., `.claude/settings.json` was modified), **preserve + warn** — never silently overwrite.
- **Never modify git state.** No git commits, no git reset, no git rm. Untracked files just become regular files again.
- **Never touch the user's home directory.** `~/.claude/projects/*` is Claude Code's session storage — not in our scope.
- **Never block.** If a file can't be deleted (permissions, in use), surface clearly and continue with the rest.

## Edge cases

| Symptom | Response |
|---|---|
| User says "uninstall" but already uninstalled (no `.harness/`) | Exit: "CCC-MAGI 没装在这个项目" |
| User says "uninstall" mid-feature workflow | Warn: "你有 in-progress feature <X>. 卸载会丢失 checkpoint 和 audit 记录。确定吗?" |
| `.harness/` exists but contents corrupted (e.g., partial install gone wrong) | Treat as Scenario C, light cleanup, surface that things look weird |
| User has `.gitignore` that doesn't have our marker (manually merged?) | Don't touch `.gitignore`; surface to user that we couldn't safely remove our section |
| `old_version_harness/` exists but is empty | Just `rmdir` it, no restore prompt |
| `.claude/settings.json` is a symlink | Don't follow — refuse to delete symlinks |

## Completion criteria

- All CCC-MAGI shipped files removed (or preserved with warning if user-modified)
- Scenario B: archive either restored or explicitly kept per user choice
- Final report shows complete list of what happened (DELETED + RESTORED + SKIPPED + PRESERVED_WITH_WARNING)
- Skill exits without invoking any other skill — this is a terminal operation
- User's source code, docs/features/*.md, git state, and home directory untouched
