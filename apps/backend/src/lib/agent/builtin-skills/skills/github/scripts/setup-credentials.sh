#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENAB_CREDENTIALS_DIR:-}" ]]; then
  NUPHOS_TOKEN=$(cat "$OPENAB_CREDENTIALS_DIR/NUPHOS_TOKEN" 2>/dev/null || true)
  export NUPHOS_TOKEN
fi

usage() {
  cat >&2 <<EOF
Usage: setup-credentials.sh <teamId> <installationId> [repoDir]

  teamId          Nuphos team id (24-char hex)
  installationId  Numeric GitHub App installation id (from
                  GET /teams/<teamId>/github-installations)

  repoDir         Optional. Configure this repository's human author and App bot committer.

Environment:
  GH_CONFIG_DIR     Optional. Defaults to \$XDG_CONFIG_HOME/gh or \$HOME/.config/gh.
  GIT_CONFIG_GLOBAL Optional. Respected by git when supplied.
  NUPHOS_TOKEN       Required. Already exported in the Nuphos agent sandbox.
  NUPHOS_BACKEND_URL Required. Base URL of the Nuphos backend API; defaults to https://api.nuphos.ai.

Mints a fresh GitHub App installation token (≤1 h) and configures \`gh\`
auth so any subsequent tool call can run \`gh\` / \`gh api\` without
worrying about env vars. Installs \`gh\` first if it isn't on PATH.

For raw curl in another shell, retrieve the token with: \`gh auth token\`.
EOF
  exit 1
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then usage; fi

team_id="$1"
installation_id="$2"
repo_dir="${3:-}"

if [ -n "$repo_dir" ]; then
  git -C "$repo_dir" rev-parse --git-dir >/dev/null
fi

if ! [[ "$team_id" =~ ^[0-9a-fA-F]{24}$ ]]; then
  echo "invalid teamId: expected a 24-char hex Nuphos team id, got '$team_id'" >&2
  exit 1
fi

if ! [[ "$installation_id" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid installationId: expected a numeric GitHub App installation id, got '$installation_id'" >&2
  exit 1
fi

if [ -z "${NUPHOS_TOKEN:-}" ]; then
  echo "NUPHOS_TOKEN is not set in this sandbox" >&2
  exit 1
fi


# Make sure `gh` exists; idempotent.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v gh >/dev/null 2>&1; then
  bash "$script_dir/install.sh"
  # install.sh's PATH export only lived in its own subshell; pick it up here
  # so the gh auth call below can find the binary in the fallback location.
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "gh is still not on PATH after install.sh; check installer output above." >&2
  exit 1
fi

token_response="$(curl -fsSL \
  --connect-timeout 10 \
  --max-time 30 \
  --retry 2 \
  --retry-delay 1 \
  --retry-all-errors \
  -H "Authorization: Bearer $NUPHOS_TOKEN" \
  "${NUPHOS_BACKEND_URL:-https://api.nuphos.ai}/teams/$team_id/github-installations/$installation_id/token")"

token="$(printf '%s' "$token_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data["token"])
')"
expires_at="$(printf '%s' "$token_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("expiresAt", ""))
')"
account_login="$(printf '%s' "$token_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("accountLogin", ""))
')"

if [ -z "$token" ]; then
  echo "Nuphos backend returned no token" >&2
  exit 1
fi

# Even gh auth login --insecure-storage can change the shared keychain's active
# token. Write the session config directly; never invoke the login/switch flow.
umask 077
export GH_CONFIG_DIR="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}"
mkdir -p "$GH_CONFIG_DIR"
chmod 700 "$GH_CONFIG_DIR"
printf '%s' "$token_response" | python3 "$script_dir/write-auth.py" "$GH_CONFIG_DIR"

# Wire up git's credential helper so `gh repo clone` and plain `git push`
# authenticate without the agent putting the token into command-line URLs.
gh auth setup-git --hostname github.com

echo "GitHub installation token loaded for $account_login (installation $installation_id)"
echo "Expires at: $expires_at"
echo
echo "Use \`gh ...\` or \`gh api /repos/...\` directly. \`gh repo clone owner/repo\` and \`git push\` also work."
echo "Re-run this script if you get 401."

# Resolve identity only for a write workflow; read-only setup needs no author.
if [ -n "$repo_dir" ]; then
  app_slug="$(printf '%s' "$token_response" | python3 -c '
import json, re, sys
slug = json.load(sys.stdin).get("appSlug")
if not isinstance(slug, str) or not re.fullmatch(r"[A-Za-z0-9-]+", slug):
    sys.exit("Missing or invalid appSlug from backend; cannot configure commit identity")
print(slug)
')"
  author_identity="$(printf '%s' "$token_response" | python3 -c '
import json, re, sys
author = json.load(sys.stdin).get("commitAuthor") or {}
name, email = author.get("name"), author.get("email")
if not isinstance(name, str) or not name.strip() or re.search(r"[\x00-\x1f\x7f<>]", name):
    sys.exit("Missing or invalid Nuphos actor name; cannot configure commit author")
if not isinstance(email, str) or not re.fullmatch(r"[^\s<>@\x00-\x1f\x7f]+@[^\s<>@\x00-\x1f\x7f]+", email):
    sys.exit("Missing or invalid Nuphos actor email; cannot configure commit author")
print(name.strip())
print(email)
')"
  bot_json="$(gh api --hostname github.com "users/${app_slug}[bot]")"
  bot_identity="$(printf '%s' "$bot_json" | python3 -c '
import json, sys
bot = json.load(sys.stdin)
login, user_id = bot.get("login"), bot.get("id")
if bot.get("type") != "Bot" or login != sys.argv[1] or type(user_id) is not int or user_id <= 0:
    sys.exit("GitHub did not return the expected App bot; commit identity unchanged")
print(login)
print(f"{user_id}+{login}@users.noreply.github.com")
' "${app_slug}[bot]")"
  bot_name="${bot_identity%%$'\n'*}"
  bot_email="${bot_identity#*$'\n'}"
  author_name="${author_identity%%$'\n'*}"
  author_email="${author_identity#*$'\n'}"
  git -C "$repo_dir" config --local author.name "$author_name"
  git -C "$repo_dir" config --local author.email "$author_email"
  git -C "$repo_dir" config --local committer.name "$bot_name"
  git -C "$repo_dir" config --local committer.email "$bot_email"
  echo "Repository author: $author_name <$author_email>"
  echo "Repository committer: $bot_name <$bot_email>"
fi
