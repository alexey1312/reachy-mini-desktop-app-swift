#!/bin/bash
# Bring the repowise index back in step with HEAD, detached so a commit never waits on it.
#
# The hook `repowise hook install` writes bails out when .repowise/ is missing
# ([ -d "$ROOT/.repowise" ] || exit 0), which is exactly the state a fresh worktree is in —
# so the first run here has to be `init`, the command that seeds a linked worktree from its
# base checkout. `update` only ever catches up an index that already exists.
#
# --wait runs it in the foreground: Conductor's setup script has to block, or the workspace
# is declared ready while the index is still being seeded.
set -euo pipefail

wait_for_it=false
[ "${1:-}" = "--wait" ] && wait_for_it=true

command -v repowise >/dev/null 2>&1 || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT"

# Not under .repowise/: seeding a worktree replaces that whole directory with a copy of the
# base checkout's, so a log opened there ends up writing to a deleted inode and the lock is
# either inherited from the base or lost mid-run. The git dir is per-worktree, untouched by
# repowise, and goes away when the worktree does.
GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
LOG="$GIT_DIR/repowise-sync.log"
LOCK="$GIT_DIR/repowise-sync.lock"

# mkdir is the atomic test-and-set: two commits in a row would otherwise put two writers on
# wiki.db. A run killed before its trap leaves the directory behind, and a lock nobody holds
# would disable syncing for good — silently — so an old one is taken over rather than obeyed.
acquire_lock() {
  mkdir "$LOCK" 2>/dev/null && return 0
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ] || return 1
  echo "--- stale lock from $(date -r "$LOCK" 2>/dev/null), taking over ---" >>"$LOG"
  rmdir "$LOCK" 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null
}

sync_index() {
  acquire_lock || {
    echo "--- sync already running, skipped at $(date) ---" >>"$LOG"
    return 0
  }
  # An EXIT trap is not enough: run from hk, this function reaches its end — the log shows
  # the final line — and the trap still does not fire. A standalone repro of the same shape
  # does fire, so the reason was never pinned down. The lock is therefore released by hand
  # below, and the trap only covers a kill.
  trap 'rmdir "$LOCK" 2>/dev/null || true' HUP INT TERM

  {
    echo "--- repowise sync at $(date) for $(git rev-parse --short HEAD 2>/dev/null) ---"
    if [ -f .repowise/state.json ]; then
      repowise update
    else
      repowise init --yes --no-prose
    fi
    # init and update write .claude/CLAUDE.md unconditionally — hardcoded path, no opt-out —
    # and Claude Code loads that path in every session. The MCP server states its own purpose
    # on connect, so the 70-line page is not worth the standing context.
    rm -f .claude/CLAUDE.md
    echo "--- sync finished at $(date) ---"
  } >>"$LOG" 2>&1 || echo "--- sync failed at $(date) ---" >>"$LOG"

  rmdir "$LOCK" 2>/dev/null || true
}

if [ "$wait_for_it" = true ]; then
  sync_index
else
  sync_index &
fi
