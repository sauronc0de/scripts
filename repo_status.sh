#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_COMMIT_COUNT=20
VERSION="0.0.0"

usage() {
  cat <<EOF
SYNOPSIS
    $0 [--help|-h] [--version|-v] [--commits|-n <count>]
DESCRIPTION
    Report branch, worktree, ref, graph, and pull request status for the
    current repository.
===============================================================
OPTIONS
    -h, --help                    Print this help.
    -v, --version                 Print the tool version.
    -n, --commits <count>         Show <count> commits in the recent git graph
                                  (default: ${DEFAULT_COMMIT_COUNT}).
===============================================================
PARAMETERS
    none                          This command does not accept positional
                                  parameters or extra options.
===============================================================
EXAMPLES
    $0
    $0 --commits 5
    $0 -n 50
===============================================================
DEPENDENCIES
    git, gh (optional for GitHub PR status details)
===============================================================
IMPLEMENTATION
    version         ${VERSION}
EOF
}

short_help() {
  printf '%s\n' "Repo/worktree/PR summary; commits: -n/--commits N; ex: $0 -n 5; deps: git, gh optional."
}

heading() {
  printf '\n== %s ==\n' "$1"
}

note() {
  printf '  - %s\n' "$1"
}

warn() {
  printf '  ! %s\n' "$1"
}

repo_cmd() {
  git -C "${WORKSPACE_DIR}" "$@"
}

current_branch_name() {
  local branch
  branch="$(repo_cmd branch --show-current)"
  if [ -n "${branch}" ]; then
    printf '%s\n' "${branch}"
    return 0
  fi

  printf 'detached at %s\n' "$(repo_cmd rev-parse --short HEAD)"
}

default_branch_name() {
  local remote_head
  remote_head="$(repo_cmd symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "${remote_head}" ]; then
    printf '%s\n' "${remote_head#origin/}"
  else
    printf 'main\n'
  fi
}

print_worktrees() {
  local line path branch head detached
  path=""
  branch=""
  head=""
  detached="no"

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      worktree\ *)
        path="${line#worktree }"
        branch=""
        head=""
        detached="no"
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      HEAD\ *)
        head="${line#HEAD }"
        ;;
      detached)
        detached="yes"
        ;;
      '')
        if [ -n "${path}" ]; then
          if [ -n "${branch}" ]; then
            note "${path} | branch=${branch} | head=${head}"
          else
            note "${path} | detached=${detached} | head=${head}"
          fi
        fi
        path=""
        branch=""
        head=""
        detached="no"
        ;;
    esac
  done < <(repo_cmd worktree list --porcelain && printf '\n')
}

print_unmerged_branches() {
  local default_branch current_branch count=0 branch
  default_branch="$(default_branch_name)"
  current_branch="$(current_branch_name)"

  while IFS= read -r branch; do
    [ -n "${branch}" ] || continue
    [ "${branch}" = "${default_branch}" ] && continue
    count=$((count + 1))
    note "${branch}"
  done < <(repo_cmd for-each-ref --format='%(refname:short)' --no-merged "refs/heads/${default_branch}" refs/heads)

  if [ "${count}" -eq 0 ]; then
    note "All local branches are merged into ${default_branch}."
  else
    note "Summary: ${count} local branch(es) are still open relative to ${default_branch}."
  fi
}

gh_available() {
  command -v gh >/dev/null 2>&1
}

gh_repo_ready() {
  gh_available && gh repo view >/dev/null 2>&1
}

open_pr_for_branch() {
  local branch="$1"
  gh pr list --head "${branch}" --state open --json number,title,url --limit 1 --jq 'if length == 0 then "" else "#" + (.[0].number|tostring) + " " + .[0].title + " " + .[0].url end' 2>/dev/null || true
}

print_worktrees_without_pr() {
  local default_branch branch has_entries="no" line path inspected_count=0
  default_branch="$(default_branch_name)"
  path=""
  branch=""

  if ! gh_repo_ready; then
    warn "gh PR lookup unavailable; install/authenticate gh or ensure repo access to list PRs."
    return 0
  fi

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      worktree\ *)
        path="${line#worktree }"
        branch=""
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      '')
        if [ -n "${path}" ] && [ -n "${branch}" ] && [ "${branch}" != "${default_branch}" ]; then
          local pr_output
          inspected_count=$((inspected_count + 1))
          pr_output="$(open_pr_for_branch "${branch}")"
          if [ -z "${pr_output}" ]; then
            has_entries="yes"
            note "${path} | branch=${branch} | no open PR found"
          fi
        fi
        path=""
        branch=""
        ;;
    esac
  done < <(repo_cmd worktree list --porcelain && printf '\n')

  if [ "${inspected_count}" -eq 0 ]; then
    note "No non-${default_branch} worktrees are currently open."
  elif [ "${has_entries}" = "no" ]; then
    note "Every non-${default_branch} worktree has an open PR."
  fi
}

print_refs_for_head() {
  local tags branches
  tags="$(repo_cmd tag --points-at HEAD)"
  branches="$(repo_cmd for-each-ref --format='%(refname:short)' --points-at HEAD refs/heads refs/remotes)"

  if [ -n "${tags}" ]; then
    note "Tags:"
    while IFS= read -r line; do
      [ -n "${line}" ] && note "  ${line}"
    done <<< "${tags}"
  else
    note "Tags: none"
  fi

  if [ -n "${branches}" ]; then
    note "Branches:"
    while IFS= read -r line; do
      [ -n "${line}" ] && note "  ${line}"
    done <<< "${branches}"
  else
    note "Branches: none"
  fi
}

print_graph() {
  local commit_count="$1"
  repo_cmd log --graph --decorate --oneline --all -n "${commit_count}"
}

print_explanation() {
  local default_branch current_branch status_summary pr_summary behind ahead
  default_branch="$(default_branch_name)"
  current_branch="$(current_branch_name)"
  status_summary="$(repo_cmd status --short --branch)"
  read -r behind ahead < <(repo_cmd rev-list --left-right --count "${default_branch}...HEAD" 2>/dev/null || printf '0 0\n')

  note "Current branch: ${current_branch}"
  note "Default branch baseline: ${default_branch}"
  note "Divergence vs ${default_branch}: behind=${behind:-0}, ahead=${ahead:-0}"

  if printf '%s\n' "${status_summary}" | grep -qv '^##'; then
    note "Working tree has local modifications or untracked files."
  else
    note "Working tree is clean."
  fi

  if gh_repo_ready; then
    pr_summary="$(gh pr status 2>/dev/null || true)"
    if [ -n "${pr_summary}" ]; then
      note "gh pr status succeeded; see GitHub summary below."
      printf '%s\n' "${pr_summary}"
    else
      warn "gh is available but gh pr status returned no data."
    fi
  else
    warn "GitHub status not shown because gh is unavailable or not authenticated."
  fi
}

main() {
  local commit_count="${DEFAULT_COMMIT_COUNT}"

  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    return 0
  fi

  if [ "${1:-}" = "--short-help" ]; then
    short_help
    return 0
  fi

  if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    printf '%s\n' "${VERSION}"
    return 0
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n|--commits)
        if [ "$#" -lt 2 ]; then
          printf 'Missing value for %s.\n' "$1" >&2
          usage >&2
          return 1
        fi
        case "$2" in
          ''|*[!0-9]*)
            printf 'Invalid commit count: %s\n' "$2" >&2
            usage >&2
            return 1
            ;;
        esac
        if [ "$2" -lt 1 ]; then
          printf 'Invalid commit count: %s\n' "$2" >&2
          usage >&2
          return 1
        fi
        commit_count="$2"
        shift 2
        ;;
      --)
        shift
        if [ "$#" -gt 0 ]; then
          printf 'This command does not accept positional arguments.\n' >&2
          usage >&2
          return 1
        fi
        ;;
      -*)
        printf 'Unexpected option: %s\n' "$1" >&2
        usage >&2
        return 1
        ;;
      *)
        printf 'This command does not accept positional arguments.\n' >&2
        usage >&2
        return 1
        ;;
    esac
  done

  printf 'Repository status for %s\n' "${WORKSPACE_DIR}"
  printf 'Generated: %s\n' "$(date -Iseconds)"

  heading "Branch"
  note "Current branch: $(current_branch_name)"
  note "Current commit: $(repo_cmd rev-parse --short HEAD)"
  note "Tracking summary: $(repo_cmd status --short --branch | sed -n '1p')"

  heading "Worktrees"
  print_worktrees

  heading "Open branches not merged into $(default_branch_name)"
  print_unmerged_branches

  heading "Open worktrees without an associated PR"
  print_worktrees_without_pr

  heading "Refs pointing at HEAD"
  print_refs_for_head

  heading "Recent git graph"
  print_graph "${commit_count}"

  heading "Project status explanation"
  print_explanation
}

main "$@"
