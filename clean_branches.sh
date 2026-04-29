#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.0.0"

usage() {
  cat <<EOF
SYNOPSIS
    $0 [--help|-h] [--version|-v]
DESCRIPTION
    Delete merged local and remote branches while skipping protected branches
    and the current branch.
===============================================================
OPTIONS
    -h, --help                    Print this help.
    -v, --version                 Print the tool version.
===============================================================
PARAMETERS
    none                          This command does not accept positional
                                  parameters or extra options.
===============================================================
EXAMPLES
    $0
===============================================================
DEPENDENCIES
    git with push access to the configured remote
===============================================================
IMPLEMENTATION
    version         ${VERSION}
EOF
}

short_help() {
  printf '%s\n' "Delete merged local/remote branches except protected ones; example: $0; dependency: git push access."
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--short-help" ]; then
  short_help
  exit 0
fi

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
  printf '%s\n' "${VERSION}"
  exit 0
fi

if [ "$#" -gt 0 ]; then
  printf 'This command does not accept positional arguments.\n' >&2
  usage >&2
  exit 1
fi

REMOTE="origin"
PROTECTED_BRANCHES=("main" "master" "develop" "staging")

echo "🔄 Fetching latest remote info..."
git fetch "$REMOTE" --prune

remote_head="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)"
DEFAULT_BRANCH="${remote_head#${REMOTE}/}"

if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "❌ Could not detect the default branch from $REMOTE/HEAD"
  exit 1
fi

echo "✅ Default branch detected: $DEFAULT_BRANCH"

is_protected_branch() {
  local branch="$1"

  [[ "$branch" == "$DEFAULT_BRANCH" ]] && return 0

  for protected in "${PROTECTED_BRANCHES[@]}"; do
    [[ "$branch" == "$protected" ]] && return 0
  done

  return 1
}

echo
echo "🧹 Checking merged local branches..."
git branch --merged "$REMOTE/$DEFAULT_BRANCH" | while IFS= read -r branch; do
  branch="$(echo "$branch" | sed 's/^[* ]*//;s/[[:space:]]*$//')"
  [[ -z "$branch" ]] && continue

  if is_protected_branch "$branch"; then
    echo "⏭️  Skipping protected local branch: $branch"
    continue
  fi

  if [[ "$(git branch --show-current)" == "$branch" ]]; then
    echo "⏭️  Skipping current local branch: $branch"
    continue
  fi

  echo "✅ Deleting local branch: $branch"
  git branch -d "$branch"
done

echo
echo "🧹 Checking merged remote branches..."
git branch -r --merged "$REMOTE/$DEFAULT_BRANCH" | while IFS= read -r remote_branch; do
  remote_branch="$(echo "$remote_branch" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$remote_branch" ]] && continue
  [[ "$remote_branch" == "$REMOTE/HEAD"*"->"* ]] && continue
  [[ "$remote_branch" != "$REMOTE/"* ]] && continue

  branch="${remote_branch#${REMOTE}/}"

  if is_protected_branch "$branch"; then
    echo "⏭️  Skipping protected remote branch: $branch"
    continue
  fi

  echo "✅ Deleting remote branch: $branch"
  git push "$REMOTE" --delete "$branch"
done

echo
echo "🎉 Cleanup complete."
