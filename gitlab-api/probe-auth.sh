#!/usr/bin/env bash
# Probes how the sandbox proxy authenticates gitlab.com, from inside a sandbox.
#
# Prints HTTP status codes only, never response bodies, so nothing about the
# account leaks into the output. It never writes: the push checks target
# gitlab-org/cli, which your token can't push to, so an authenticated request
# gets 403 ("not allowed to push") and an unauthenticated one gets 401.
#
#   API /user:            200 = authenticated, 401 = not
#   git receive-pack:     403 = authenticated, 401 = not
#
# Usage (inside the sandbox): bash probe-auth.sh
set -u

S="${GITLAB_TOKEN:-}"
ME=https://gitlab.com/api/v4/user
RP='https://gitlab.com/gitlab-org/cli.git/info/refs?service=git-receive-pack'
REPO=https://gitlab.com/gitlab-org/cli.git

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
row() { printf '%-52s %s\n' "$1" "$2"; }
basic() { printf '%s' "$1" | base64 | tr -d '\n'; }

echo "== environment"
if [ -z "$S" ]; then row "GITLAB_TOKEN" "unset"
elif [ "$S" = proxy-managed ]; then row "GITLAB_TOKEN" "proxy-managed (sentinel)"
else row "GITLAB_TOKEN" "set, NOT the sentinel (real token in the sandbox?)"; fi
if command -v glab >/dev/null; then
  row "glab" "$(glab --version 2>/dev/null | head -n1)"
  glab auth status >/dev/null 2>&1; row "glab auth status exit" "$?"
else row "glab" "not installed"; fi
row "git credential helper for gitlab.com" \
  "$(git config --get-urlmatch credential.helper https://gitlab.com/ 2>/dev/null || echo none)"
row "insteadOf rewrites for gitlab.com" \
  "$(git config --get-regexp '^url\..*gitlab\.com.*insteadof$' | wc -l | tr -d ' ')"

echo "== API (200 = authenticated)"
row "no auth header (does the proxy inject on its own?)" "$(code "$ME")"
row "PRIVATE-TOKEN: <sentinel>" "$(code -H "PRIVATE-TOKEN: $S" "$ME")"
row "Authorization: Bearer <sentinel>" "$(code -H "Authorization: Bearer $S" "$ME")"
row "PRIVATE-TOKEN: bogus (does the proxy overwrite it?)" "$(code -H 'PRIVATE-TOKEN: bogus' "$ME")"
row "Authorization: Bearer bogus" "$(code -H 'Authorization: Bearer bogus' "$ME")"

echo "== git over HTTPS (403 = authenticated, 401 = not)"
row "no auth header" "$(code "$RP")"
row "Basic oauth2:<sentinel>" "$(code -H "Authorization: Basic $(basic "oauth2:$S")" "$RP")"
row "Basic oauth2:bogus" "$(code -H "Authorization: Basic $(basic oauth2:bogus)" "$RP")"
row "PRIVATE-TOKEN: <sentinel>, no Basic" "$(code -H "PRIVATE-TOKEN: $S" "$RP")"
row "Bearer <sentinel>, no Basic" "$(code -H "Authorization: Bearer $S" "$RP")"

echo "== git end to end (push --dry-run, never writes)"
gitpush() {
  out=$(GIT_TERMINAL_PROMPT=0 git "$@" push --dry-run "$REPO" HEAD:refs/heads/probe 2>&1)
  case "$out" in
    *"not allowed to push"*) echo "authenticated (403)" ;;
    *"Authentication failed"*|*"could not read Username"*|*401*) echo "NOT authenticated" ;;
    *) echo "other: $(printf '%s' "$out" | tail -n1)" ;;
  esac
}
tmp=$(mktemp -d); git -C "$tmp" init -q && git -C "$tmp" -c user.name=p -c user.email=p@p.invalid commit -q --allow-empty -m probe
cd "$tmp"
row "via the configured credential helper" "$(gitpush)"
row "via an env-only helper (no glab)" \
  "$(gitpush -c credential.helper= -c 'credential.helper=!f() { echo username=oauth2; echo "password=$GITLAB_TOKEN"; }; f')"
cd / && rm -rf "$tmp"
