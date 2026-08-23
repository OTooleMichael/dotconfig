#!/bin/bash
# bitwarden-bootstrap.sh
# One-command setup for Bitwarden CLI on a new machine.
# Run: bash ~/.config/scripts/bitwarden-bootstrap.sh
# Then: bw-login (shell function provided)

set -eo pipefail

VAULT_SERVER="https://vault.utm-builder.com"
FOLDER_ID="8c4b3b91-9ebd-49c2-a07d-d3a6e073c836"

echo "=== Bitwarden Bootstrap ==="

# 1. Install bw CLI
if command -v bw &>/dev/null; then
  echo "[✓] Bitwarden CLI already installed: $(bw --version)"
else
  echo "[*] Installing Bitwarden CLI..."
  brew install bitwarden-cli
  echo "[✓] Installed: $(bw --version)"
fi

# 2. Configure server URL (idempotent)
echo "[*] Configuring server URL..."
bw config server "$VAULT_SERVER" 2>/dev/null || true
echo "[✓] Server: $VAULT_SERVER"

# 3. Add login helper to .zshrc (idempotent)
ZSHRC="$HOME/.zshrc"
MARKER="# --- Bitwarden Bootstrap ---"

if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
  echo "[✓] Shell helpers already added to .zshrc"
else
  cat >> "$ZSHRC" << 'ZSHEOF'

# --- Bitwarden Bootstrap ---
# Usage: bw-login  (interactive login)
#        bw-vault  (list all items in UTM Builder folder)
#        bw-get <name>  (get a specific item)

bw-login() {
  echo "Logging into $VAULT_SERVER ..."
  bw login --server "$VAULT_SERVER"
  echo ""
  echo "Session active: $(bw status --pretty | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
  echo ""
  echo "Run 'bw-vault' to list your vault items."
}

bw-vault() {
  bw list items --folderid "$FOLDER_ID" --response | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)['data']['data']
for i in sorted(d, key=lambda x: x['name'].lower()):
    login = i.get('login', {})
    user = login.get('username', '-')
    pw = login.get('password', '-')
    uris = [u.get('uri','') for u in login.get('uris',[])]
    uri = uris[0] if uris else ''
    itype = 'SecureNote' if i['type'] == 2 else 'Login'
    print(f'{i[\"name\"]:35s} [{itype:11s}] user={user:40s} uri={uri}')
"
}

bw-get() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "Usage: bw-get <item-name>"
    return 1
  fi
  bw list items --folderid "$FOLDER_ID" --response | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)['data']['data']
name = sys.argv[1]
matches = [i for i in d if name.lower() in i['name'].lower()]
if not matches:
    print(f'No items matching: {name}')
    sys.exit(1)
for i in matches:
    login = i.get('login', {})
    pw = login.get('password', '-')
    uris = [u.get('uri','') for u in login.get('uris',[])]
    uri = uris[0] if uris else ''
    notes = i.get('notes', '')[:200]
    print(f'=== {i[\"name\"]} ===')
    if pw and pw != '-': print(f'  Password: {pw}')
    if uri: print(f'  URI:    {uri}')
    if notes and notes != '-': print(f'  Notes:  {notes}')
" "$name"
}

bw-deploy-env() {
  # Copy a Secure Note's content to /opt/apps on the server
  local env_name="$1"
  local server="${2:-app.utm-builder.com}"
  if [ -z "$env_name" ]; then
    echo "Usage: bw-deploy-env <env-name> [server]"
    echo "  e.g.: bw-deploy-env utm-server"
    return 1
  fi
  local item_id=$(bw list items --folderid "$FOLDER_ID" --response | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)['data']['data']
name = sys.argv[1]
matches = [i for i in d if name.lower() in i['name'].lower() and i['type'] == 2]
if matches: print(matches[0]['id'])
" 2>/dev/null)
  if [ -z "$item_id" ]; then
    echo "No Secure Note matching: $env_name"
    return 1
  fi
  local content=$(bw get notes "$item_id" 2>/dev/null)
  echo "$content" | ssh "deploy@$server" "cat > /opt/apps/${env_name}.env"
  echo "Deployed to deploy@$server:/opt/apps/${env_name}.env"
}
ZSHEOF
  echo "[✓] Shell helpers added to .zshrc"
  echo "    Run: source ~/.zshrc"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps on this machine:"
echo "  1. source ~/.zshrc"
echo "  2. bw-login  (enter your Bitwarden credentials)"
echo "  3. bw-vault  (list all items)"
echo ""
echo "On a NEW machine, just run this script, then bw-login."
