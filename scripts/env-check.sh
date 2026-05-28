#!/usr/bin/env bash
# env-check.sh — environment / dependency detector for CCC-MAGI
#
# Called by MAGI Core (via Bash tool) during the bootstrap S1 phase to detect
# what's installed. Outputs structured JSON that MAGI Core parses to guide
# the user through installation of any missing dependencies conversationally.
#
# USAGE:
#   env-check.sh                          # Detect + output JSON to stdout, exit 0
#   env-check.sh --finalize               # Detect; if all required deps OK, write env-check.json. Exit 0 on success, 1 if blockers remain.
#   env-check.sh --install-jq-vendored    # Download jq binary to .harness/bin/jq (no sudo needed)
#
# OUTPUT JSON SCHEMA:
#   {
#     "detected_at": "<iso>",
#     "platform": "darwin|linux|windows-wsl|windows-git-bash|unknown",
#     "shell": "bash <version>",
#     "required": {
#       "git":  {"installed": true,  "version": "2.39.5"},
#       "jq":   {"installed": false, "install_hints": [...]}
#     },
#     "ai_clis": {
#       "claude": {"installed": true,  "path": "..."},
#       "codex":  {"installed": true,  "path": "..."},
#       "gemini": {"installed": false}
#     },
#     "tier": "1-claude-codex|1-codex-claude|2-single-claude|2-single-codex|3-other|0-none",
#     "recommendation": "<human-readable>",
#     "all_required_ok": true|false,
#     "blockers": ["jq"]
#   }

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:.harness/bin:$PATH"

MODE="${1:-detect}"

# ─── Platform detection ────────────────────────────────────────────────
detect_platform() {
  case "$(uname -s)" in
    Darwin*) echo "darwin" ;;
    Linux*)
      # WSL?
      if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "windows-wsl"
      else
        echo "linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows-git-bash" ;;
    *) echo "unknown" ;;
  esac
}

PLATFORM=$(detect_platform)

# ─── Helpers ───────────────────────────────────────────────────────────
detect_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local path version
    path="$(command -v "$name")"
    version="$("$name" --version 2>/dev/null | head -1 | sed 's/"/\\"/g' || echo "unknown")"
    printf '{"installed":true,"path":"%s","version":"%s"}' "$path" "$version"
  else
    printf '{"installed":false}'
  fi
}

# Install hints for jq, per platform
jq_install_hints() {
  case "$PLATFORM" in
    darwin)
      if command -v brew >/dev/null 2>&1; then
        cat <<'EOF'
[
  {"method":"brew","cmd":"brew install jq","sudo":false,"speed":"~10s"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s"}
]
EOF
      else
        cat <<'EOF'
[
  {"method":"brew","cmd":"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && brew install jq","sudo":false,"speed":"~5min"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s","recommended":true}
]
EOF
      fi
      ;;
    linux|windows-wsl)
      if [ -f /etc/debian_version ]; then
        cat <<'EOF'
[
  {"method":"apt","cmd":"sudo apt install -y jq","sudo":true,"speed":"~10s"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s"}
]
EOF
      elif [ -f /etc/redhat-release ]; then
        cat <<'EOF'
[
  {"method":"yum","cmd":"sudo yum install -y jq","sudo":true,"speed":"~15s"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s"}
]
EOF
      elif [ -f /etc/arch-release ]; then
        cat <<'EOF'
[
  {"method":"pacman","cmd":"sudo pacman -S --noconfirm jq","sudo":true,"speed":"~10s"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s"}
]
EOF
      else
        cat <<'EOF'
[
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s","recommended":true}
]
EOF
      fi
      ;;
    windows-git-bash)
      cat <<'EOF'
[
  {"method":"scoop","cmd":"scoop install jq","sudo":false,"speed":"~15s","precondition":"requires Scoop package manager"},
  {"method":"chocolatey","cmd":"choco install jq -y","sudo":true,"speed":"~30s","precondition":"requires Chocolatey package manager"},
  {"method":"vendored","cmd":".harness/scripts/env-check.sh --install-jq-vendored","sudo":false,"speed":"~5s","recommended":true}
]
EOF
      ;;
    *)
      echo '[{"method":"manual","cmd":"Install jq from https://jqlang.github.io/jq/download/","sudo":false}]'
      ;;
  esac
}

# ─── Vendored jq install ───────────────────────────────────────────────
install_jq_vendored() {
  local arch url
  arch="$(uname -m)"
  case "$PLATFORM-$arch" in
    darwin-arm64)         url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64" ;;
    darwin-x86_64)        url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-amd64" ;;
    linux-x86_64|windows-wsl-x86_64) url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" ;;
    linux-aarch64|windows-wsl-aarch64) url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64" ;;
    windows-git-bash-*)   url="https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe" ;;
    *) echo "Unsupported platform/arch combo: $PLATFORM-$arch" >&2; exit 1 ;;
  esac

  mkdir -p .harness/bin
  TARGET=".harness/bin/jq"
  [ "$PLATFORM" = "windows-git-bash" ] && TARGET=".harness/bin/jq.exe"

  echo "Downloading jq from: $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$TARGET" || { echo "Download failed"; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$TARGET" || { echo "Download failed"; exit 1; }
  else
    echo "Neither curl nor wget found" >&2
    exit 1
  fi
  chmod +x "$TARGET" 2>/dev/null || true

  echo "✓ jq installed to $TARGET"
  echo "  Verify: $TARGET --version"
}

# ─── Mode dispatch ─────────────────────────────────────────────────────
case "$MODE" in
  --install-jq-vendored)
    install_jq_vendored
    exit 0
    ;;
  detect|--finalize)
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 [--finalize | --install-jq-vendored]" >&2
    exit 1
    ;;
esac

# ─── Build detection JSON ──────────────────────────────────────────────
GIT_INFO=$(detect_tool git)
JQ_INFO=$(detect_tool jq)
CLAUDE_INFO=$(detect_tool claude)
CODEX_INFO=$(detect_tool codex)
GEMINI_INFO=$(detect_tool gemini)

# Bash version (just for info)
BASH_VER="${BASH_VERSION:-unknown}"
SHELL_DESC="bash $BASH_VER"

# Determine tier
HAS_CLAUDE=$(printf '%s' "$CLAUDE_INFO" | grep -q '"installed":true' && echo yes || echo no)
HAS_CODEX=$(printf '%s' "$CODEX_INFO" | grep -q '"installed":true' && echo yes || echo no)
HAS_GEMINI=$(printf '%s' "$GEMINI_INFO" | grep -q '"installed":true' && echo yes || echo no)

if [ "$HAS_CLAUDE" = "yes" ] && [ "$HAS_CODEX" = "yes" ]; then
  TIER="1-claude-codex"
  RECOMMENDATION="Tier 1 ideal: Claude writes code, Codex audits. Cross-model bias cancellation active."
elif [ "$HAS_CLAUDE" = "yes" ]; then
  TIER="2-single-claude"
  RECOMMENDATION="Tier 2: Claude only. Audit will use fresh-context Claude (same model, weaker bias cancellation). Install Codex for Tier 1."
elif [ "$HAS_CODEX" = "yes" ]; then
  TIER="2-single-codex"
  RECOMMENDATION="Tier 2: Codex only. Audit will use fresh-context Codex. Install Claude for Tier 1."
elif [ "$HAS_GEMINI" = "yes" ]; then
  TIER="3-other"
  RECOMMENDATION="Tier 3: Gemini detected but untested. Install Claude or Codex for Tier 1 support."
else
  TIER="0-none"
  RECOMMENDATION="No supported AI CLI detected. This is unusual — you must have at least one (Claude/Codex) to be talking to MAGI Core right now. Check PATH."
fi

# Determine blockers (jq is the only true required blocker)
JQ_OK=$(printf '%s' "$JQ_INFO" | grep -q '"installed":true' && echo yes || echo no)
GIT_OK=$(printf '%s' "$GIT_INFO" | grep -q '"installed":true' && echo yes || echo no)

BLOCKERS="["
ALL_OK="true"
if [ "$GIT_OK" = "no" ]; then
  BLOCKERS="${BLOCKERS}\"git\","
  ALL_OK="false"
fi
if [ "$JQ_OK" = "no" ]; then
  BLOCKERS="${BLOCKERS}\"jq\","
  ALL_OK="false"
fi
BLOCKERS="${BLOCKERS%,}]"  # strip trailing comma

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build JQ install hints if needed
JQ_HINTS="[]"
if [ "$JQ_OK" = "no" ]; then
  JQ_HINTS=$(jq_install_hints)
fi

# ─── Assemble output JSON ──────────────────────────────────────────────
OUTPUT=$(cat <<EOF
{
  "detected_at": "$NOW",
  "platform": "$PLATFORM",
  "shell": "$SHELL_DESC",
  "required": {
    "git": $GIT_INFO,
    "jq":  $JQ_INFO
  },
  "jq_install_hints": $JQ_HINTS,
  "ai_clis": {
    "claude": $CLAUDE_INFO,
    "codex":  $CODEX_INFO,
    "gemini": $GEMINI_INFO
  },
  "tier": "$TIER",
  "recommendation": "$RECOMMENDATION",
  "all_required_ok": $ALL_OK,
  "blockers": $BLOCKERS
}
EOF
)

# Pretty-print if jq available (recursive bootstrap problem: if jq isn't installed yet, we just output raw)
if command -v jq >/dev/null 2>&1; then
  echo "$OUTPUT" | jq .
else
  echo "$OUTPUT"
fi

# ─── Finalize mode: write env-check.json if all required deps OK ──────
if [ "$MODE" = "--finalize" ]; then
  if [ "$ALL_OK" != "true" ]; then
    echo "" >&2
    echo "✗ Cannot finalize — blockers remain: $BLOCKERS" >&2
    echo "  Install the missing dependency, then re-run env-check.sh --finalize" >&2
    exit 1
  fi

  mkdir -p .harness/state
  echo "$OUTPUT" > .harness/state/env-check.json
  echo "" >&2
  echo "✓ Environment check finalized: .harness/state/env-check.json" >&2
  echo "  Phase 1 complete. Next: project deployment via /init" >&2
fi

exit 0
