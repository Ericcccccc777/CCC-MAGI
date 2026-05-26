#!/usr/bin/env bash
# check-prereqs.sh — verify CCC-Harness prerequisites are installed.
#
# Called by install-into.sh at start. Fails fast if a hard prereq is missing,
# warns on soft prereqs.
#
# Hard prereqs: git, bash 3.2+, jq
# Soft prereqs: python3 (used by some diagnostic scripts)

set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ERRORS=0

# --- git ---
if ! command -v git >/dev/null 2>&1; then
  echo "❌ git is not installed" >&2
  echo "   macOS: install Xcode Command Line Tools — run: xcode-select --install" >&2
  echo "   Linux: sudo apt install git  (or distro equivalent)" >&2
  ERRORS=$((ERRORS + 1))
fi

# --- bash 3.2+ ---
BASH_VER="${BASH_VERSION:-}"
if [ -z "$BASH_VER" ]; then
  echo "⚠️  Cannot detect bash version (\$BASH_VERSION empty)" >&2
fi

# --- jq ---
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required but not installed." >&2
  echo "" >&2
  echo "How to install on this system:" >&2
  echo "" >&2
  if command -v brew >/dev/null 2>&1; then
    echo "  macOS (Homebrew detected):" >&2
    echo "    brew install jq" >&2
  elif [ "$(uname)" = "Darwin" ]; then
    echo "  macOS (no Homebrew detected) — RECOMMENDED PATH:" >&2
    echo "" >&2
    echo "    # 1. Install Homebrew (one-time, ~5 min):" >&2
    echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
    echo "" >&2
    echo "    # 2. Add Homebrew to PATH (Apple Silicon):" >&2
    echo "    echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile" >&2
    echo "    eval \"\$(/opt/homebrew/bin/brew shellenv)\"" >&2
    echo "" >&2
    echo "    # 3. Install jq:" >&2
    echo "    brew install jq" >&2
    echo "" >&2
    echo "  macOS Alternative (skip Homebrew, faster):" >&2
    arch="$(uname -m)"
    if [ "$arch" = "arm64" ]; then
      echo "    curl -L -o /tmp/jq https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64" >&2
    else
      echo "    curl -L -o /tmp/jq https://github.com/jqlang/jq/releases/latest/download/jq-macos-amd64" >&2
    fi
    echo "    chmod +x /tmp/jq && sudo mv /tmp/jq /usr/local/bin/jq" >&2
  elif [ -f /etc/debian_version ]; then
    echo "  Debian / Ubuntu: sudo apt install jq" >&2
  elif [ -f /etc/redhat-release ]; then
    echo "  RHEL / CentOS / Fedora: sudo yum install jq  (or dnf install jq)" >&2
  elif [ -f /etc/arch-release ]; then
    echo "  Arch Linux: sudo pacman -S jq" >&2
  else
    echo "  Linux: install jq via your distro's package manager" >&2
  fi
  echo "" >&2
  echo "  After install, re-run the CCC-Harness installer." >&2
  ERRORS=$((ERRORS + 1))
fi

# --- python3 (soft) ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  python3 is not installed (used by some diagnostic scripts; not required for core install)" >&2
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "" >&2
  echo "❌ $ERRORS prerequisite check(s) failed. Fix the above and re-run." >&2
  exit 1
fi

echo "✓ All prerequisites met (jq $(jq --version 2>/dev/null | head -1), git $(git --version 2>/dev/null | awk '{print $3}'))"
exit 0
