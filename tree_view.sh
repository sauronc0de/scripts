#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="0.0.0"

ROOT_PATH="."
INCLUDE_HIDDEN=0
DIRS_ONLY=0
MAX_DEPTH=""

usage() {
  cat <<EOF
SYNOPSIS
  ${SCRIPT_NAME} [OPTIONS] [PATH]

DESCRIPTION
  Print a recursive, easy-to-read ASCII tree for PATH.

OPTIONS
  -a, --all            Include hidden files and folders.
  -d, --dirs-only      Show only directories.
  -L, --max-depth N    Limit recursion depth.
  -h, --help          Print this help.
  -v, --version       Print the tool version.

EXAMPLES
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} ~/projects/checkpp
  ${SCRIPT_NAME} -a -L 2 .

IMPLEMENTATION
  version             ${SCRIPT_NAME} ${VERSION}
EOF
}

short_help() {
  printf '%s\n' "Recursive ASCII tree for a path; options: -a, -d, -L N; example: $0 ."
}

print_version() {
  printf '%s\n' "${VERSION}"
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

resolve_path() {
  local input="$1"
  if [ -d "$input" ] || [ -f "$input" ]; then
    readlink -f "$input"
  else
    die "path not found: $input"
  fi
}

entry_name() {
  local entry="$1"
  local name
  name="$(basename "$entry")"

  if [ -L "$entry" ]; then
    printf '%s -> %s' "$name" "$(readlink "$entry")"
  else
    printf '%s' "$name"
  fi
}

list_children() {
  local dir="$1"
  local depth="$2"
  local -a find_args

  find_args=("$dir" -mindepth 1 -maxdepth 1)
  if [ "$INCLUDE_HIDDEN" -eq 0 ]; then
    find_args+=( ! -name '.*' )
  fi

  if [ -n "$MAX_DEPTH" ] && [ "$depth" -ge "$MAX_DEPTH" ]; then
    return 0
  fi

  find "${find_args[@]}" -print0 | sort -z
}

print_tree() {
  local root="$1"
  local prefix="$2"
  local depth="$3"
  local entry
  local -a children=()
  local index=0

  while IFS= read -r -d '' entry; do
    children+=("$entry")
  done < <(list_children "$root" "$depth")

  for entry in "${children[@]}"; do
    local is_last=0
    local branch='|-- '
    local next_prefix='|   '

    if [ "$index" -eq $(( ${#children[@]} - 1 )) ]; then
      is_last=1
      branch='`-- '
      next_prefix='    '
    fi

    if [ -d "$entry" ] && [ ! -L "$entry" ]; then
      printf '%s%s%s\n' "$prefix" "$branch" "$(entry_name "$entry")"
      print_tree "$entry" "$prefix$next_prefix" "$((depth + 1))"
    elif [ "$DIRS_ONLY" -eq 0 ]; then
      printf '%s%s%s\n' "$prefix" "$branch" "$(entry_name "$entry")"
    fi

    index=$((index + 1))
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a|--all)
      INCLUDE_HIDDEN=1
      ;;
    -d|--dirs-only)
      DIRS_ONLY=1
      ;;
    -L|--max-depth)
      shift
      [ "$#" -gt 0 ] || die "--max-depth requires a value"
      MAX_DEPTH="$1"
      case "$MAX_DEPTH" in
        ''|*[!0-9]*) die "--max-depth expects a non-negative integer" ;;
      esac
      ;;
    --max-depth=*)
      MAX_DEPTH="${1#*=}"
      case "$MAX_DEPTH" in
        ''|*[!0-9]*) die "--max-depth expects a non-negative integer" ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      print_version
      exit 0
      ;;
    --short-help)
      short_help
      exit 0
      ;;
    --)
      shift
      [ "$#" -eq 0 ] || ROOT_PATH="$1"
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      ROOT_PATH="$1"
      ;;
  esac
  shift
done

ROOT_PATH="$(resolve_path "$ROOT_PATH")"

printf '%s\n' "$ROOT_PATH"

if [ -d "$ROOT_PATH" ]; then
  print_tree "$ROOT_PATH" '' 0
fi
