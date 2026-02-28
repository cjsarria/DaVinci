#!/usr/bin/env bash
set -euo pipefail

# anti_cursor.sh
# Purpose:
# - Inspect repo for any Cursor attribution signals (author/committer, trailers).
# - Optionally rewrite history (destructive) to remove Cursor signals + normalize identity.
# - Optionally delete stray remote refs that could keep Cursor counted.
# - Optionally "cache-bust" with a tiny commit to nudge GitHub sidebar to refresh.
#
# Usage:
#   ./scripts_local/anti_cursor.sh inspect
#   ./scripts_local/anti_cursor.sh inspect --remote-scan
#   ./scripts_local/anti_cursor.sh fix --push
#   ./scripts_local/anti_cursor.sh cachebust --push
#   ./scripts_local/anti_cursor.sh fix --push --cachebust
#
# Notes:
# - "fix" rewrites history using git-filter-repo.
# - GitHub "Contributors" sidebar is cached. cachebust is the practical way to force refresh.
# - Requires: git. For fix: git-filter-repo installed.

CANON_NAME="Carlos Cano"
CANON_EMAIL="cjcs777@gmail.com"
DEFAULT_REMOTE_URL="https://github.com/cjsarria/DaVinci.git"
DEFAULT_BRANCH="main"

CMD="${1:-}"
shift || true

PUSH=0
REMOTE_URL="$DEFAULT_REMOTE_URL"
BRANCH="$DEFAULT_BRANCH"
REMOTE_SCAN=0
CACHEBUST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1; shift ;;
    --remote) REMOTE_URL="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --remote-scan) REMOTE_SCAN=1; shift ;;
    --cachebust) CACHEBUST=1; shift ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

need_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repo."
}

has_filter_repo() {
  git filter-repo --help >/dev/null 2>&1
}

print_header() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

grep_cursor_signals() {
  # Print matching lines if any; return 0 if matches found, 1 if none.
  git log --all --format="%h | %an <%ae> | %cn <%ce> | %s%n%b" | \
    grep -inE "cursor|cursoragent@cursor\.com|co-authored-by:|made-with:" >/dev/null 2>&1
}

print_cursor_matches() {
  git log --all --format="%h | %an <%ae> | %cn <%ce> | %s%n%b" | \
    grep -inE "cursor|cursoragent@cursor\.com|co-authored-by:|made-with:" | head -200 || true
}

ensure_origin() {
  if git remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  git remote add origin "$REMOTE_URL"
}

fetch_all() {
  ensure_origin
  git fetch origin --prune --tags >/dev/null 2>&1 || true
}

inspect_remote_truth() {
  print_header "Remote truth check (origin/$BRANCH)"
  fetch_all

  set +e
  git log "origin/$BRANCH" --format="%h | %an <%ae> | %cn <%ce> | %s%n%b" | \
    grep -inE "cursor|cursoragent@cursor\.com|co-authored-by:|made-with:" | head -50
  RC=$?
  set -e

  if [[ $RC -ne 0 ]]; then
    echo "origin/$BRANCH clean ✅ (no cursor/coauthor/madewith found)"
  else
    echo "origin/$BRANCH still contains cursor signals ❌ (see above)"
  fi

  print_header "Remote refs (heads + tags) — GitHub may count these"
  echo "Heads:"
  git ls-remote --heads origin || true
  echo
  echo "Tags:"
  git ls-remote --tags origin || true
}

inspect() {
  need_repo
  print_header "Repo + identity"
  echo "PWD: $(pwd)"
  echo "Branch: $(git branch --show-current 2>/dev/null || echo "(detached)")"
  echo "Origin: $(git remote get-url origin 2>/dev/null || echo "(none)")"
  echo "Git user.name:  $(git config user.name || echo "(unset)")"
  echo "Git user.email: $(git config user.email || echo "(unset)")"

  print_header "Fetch (refresh remote refs)"
  fetch_all
  echo "Fetched."

  print_header "Contributors across ALL refs (local view)"
  git shortlog -sne --all || true

  print_header "Scan for Cursor signals (local history)"
  if grep_cursor_signals; then
    echo "Cursor-related signals detected (showing up to 200 lines):"
    print_cursor_matches
  else
    echo "No Cursor signals found in commit messages or metadata (local scan). ✅"
  fi

  print_header "Scan for non-canonical author emails"
  echo "Expected canonical: ${CANON_NAME} <${CANON_EMAIL}>"
  git log --all --format="%an <%ae>" | sort | uniq -c | sort -nr | head -50

  if [[ $REMOTE_SCAN -eq 1 ]]; then
    inspect_remote_truth
  fi

  echo
  echo "Inspect complete."
}

fix_history() {
  need_repo
  print_header "Pre-flight"
  git status --porcelain | grep -q . && die "Working tree not clean. Commit/stash first."
  echo "Working tree clean."

  if ! has_filter_repo; then
    print_header "git-filter-repo missing"
    echo "Install it, then rerun:"
    echo "  brew install git-filter-repo"
    echo "or: pipx install git-filter-repo"
    exit 1
  fi

  # Lock identity (repo scope)
  git config user.name "$CANON_NAME"
  git config user.email "$CANON_EMAIL"
  git config user.useConfigOnly true

  BACKUP_REF="backup/pre-anti-cursor-$(date +%Y%m%d-%H%M%S)"
  git branch "$BACKUP_REF"
  echo "Backup branch created: $BACKUP_REF"

  print_header "Rewrite history: normalize identity + strip Cursor trailers"
  git filter-repo --force \
    --name-callback "return b\"$CANON_NAME\"" \
    --email-callback "return b\"$CANON_EMAIL\"" \
    --message-callback '
import re
msg = message.decode("utf-8", errors="ignore")

# Strip Cursor co-author + signatures
msg = re.sub(r"(?im)^\s*Co-authored-by:\s*Cursor\s*<cursoragent@cursor\.com>\s*\n?", "", msg)
msg = re.sub(r"(?im)^\s*Made-with:\s*Cursor\s*\n?", "", msg)
msg = re.sub(r"(?im)^\s*Co-authored-by:.*cursoragent@cursor\.com\s*\n?", "", msg)

# Clean trailing excessive blank lines
msg = re.sub(r"\n{3,}\Z", "\n\n", msg)
return msg.encode("utf-8")
'

  # filter-repo may remove origin
  print_header "Re-add origin if removed"
  ensure_origin
  echo "Origin: $(git remote get-url origin)"

  print_header "Verify after rewrite (local)"
  git shortlog -sne --all
  if grep_cursor_signals; then
    echo "Cursor signals STILL present ❌ (showing matches):"
    print_cursor_matches
    die "Rewrite did not fully remove Cursor signals."
  else
    echo "No Cursor signals found after rewrite ✅"
  fi

  if [[ $PUSH -eq 1 ]]; then
    print_header "Push rewritten history (DESTRUCTIVE)"
    fetch_all
    git push --force origin "$BRANCH"
    echo "Pushed rewritten history to origin/$BRANCH."
  else
    echo
    echo "Push skipped. To push rewritten history:"
    echo "  $0 fix --push --branch $BRANCH"
  fi

  echo
  echo "Backup branch kept locally: $BACKUP_REF"
}

cache_bust_commit() {
  need_repo
  print_header "Cache-bust (to force GitHub Contributors refresh)"
  # We only do this if local history is clean.
  if grep_cursor_signals; then
    die "Local history still has Cursor signals. Run: $0 fix --push --cachebust"
  fi

  # Create a harmless file under .github/ to avoid polluting package sources
  mkdir -p .github
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "cache-bust: $ts" > .github/.contributors-cache-bust

  git add .github/.contributors-cache-bust
  git commit -m "chore: contributors cache bust" --no-gpg-sign

  if [[ $PUSH -eq 1 ]]; then
    ensure_origin
    git push origin "$BRANCH"
    echo "Pushed cache-bust commit to origin/$BRANCH."
  else
    echo "Cache-bust commit created locally. Push with:"
    echo "  git push origin $BRANCH"
  fi
}

case "$CMD" in
  inspect)
    inspect
    ;;
  fix)
    fix_history
    if [[ $CACHEBUST -eq 1 ]]; then
      cache_bust_commit
    fi
    ;;
  cachebust)
    cache_bust_commit
    ;;
  *)
    echo "Usage:"
    echo "  $0 inspect [--remote-scan]"
    echo "  $0 fix [--push] [--cachebust] [--remote <url>] [--branch <name>]"
    echo "  $0 cachebust [--push] [--branch <name>]"
    exit 2
    ;;
esac