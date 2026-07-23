#!/data/data/com.termux/files/usr/bin/bash
# install.sh - makes sure logins and AI functions are loaded by ~/.bashrc
# Idempotent: can be run multiple times without duplicating entries.

set -eu

# Dependencies required by the AI functions (gemini.sh) that are absent from the default Termux build.
# grep/sed/bash are in the base; curl and jq must be installed.
ensure_deps() {
  local missing=""
  for _dep in curl jq; do
    command -v "$_dep" >/dev/null 2>&1 || missing="$missing $_dep"
  done

  if [ -n "$missing" ]; then
    echo "ai-features: missing dependencies:$missing - installing..."
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y $missing
    elif command -v apt >/dev/null 2>&1; then
      apt update && apt install -y $missing
    else
      echo "ai-features: no package manager found (pkg/apt). Install manually:$missing" >&2
      return 1
    fi
  else
    echo "ai-features: dependencies (curl, jq) already installed."
  fi
}

ensure_deps

BASHRC="$HOME/.bashrc"
MARKER="# >>> ai-features (auto) >>>"
MARKER_END="# <<< ai-features (auto) <<<"

read -r -d '' BLOCK <<'EOF' || true
# >>> ai-features (auto) >>>
# Logins / API keys
[ -r "$HOME/logins.sh" ] && . "$HOME/logins.sh"

# AI functions - all scripts from ~/ai-features (skipping install.sh)
if [ -d "$HOME/ai-features" ]; then
  for _ai_script in "$HOME/ai-features"/*.sh; do
    [ "$(basename "$_ai_script")" = "install.sh" ] && continue
    [ -r "$_ai_script" ] && . "$_ai_script"
  done
  unset _ai_script
fi
# <<< ai-features (auto) <<<
EOF

touch "$BASHRC"

if grep -qF "$MARKER" "$BASHRC"; then
  echo "ai-features: entry already exists in $BASHRC (updating)."
  # Remove the existing block between the markers
  tmp="$(mktemp)"
  sed "/$MARKER/,/$MARKER_END/d" "$BASHRC" > "$tmp"
  mv "$tmp" "$BASHRC"
fi

# Add the (fresh) block at the end
printf '\n%s\n' "$BLOCK" >> "$BASHRC"
echo "ai-features: added/refreshed loading in $BASHRC"
echo "Run:  source ~/.bashrc"
