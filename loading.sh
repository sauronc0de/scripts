#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="0.2.0"
DEFAULT_SECONDS=5
DEFAULT_MESSAGE="Loading"
VERSION="0.0.0"

supports_color() {
  [ "${CLICOLOR_FORCE:-0}" != "0" ] && return 0
  [ -t 1 ] || return 1
  [ -z "${NO_COLOR:-}" ] || return 1
  case "${TERM:-}" in
    ''|dumb) return 1 ;;
  esac
  command -v tput >/dev/null 2>&1 || return 1
  [ "$(tput colors 2>/dev/null || printf '0')" -ge 8 ]
}

disable_color() {
  COLOR_RESET=""
  COLOR_ACCENT=""
  COLOR_BAR=""
  COLOR_DIM=""
  COLOR_TEXT=""
}

enable_color() {
  COLOR_RESET=$'\033[0m'
  COLOR_ACCENT=$'\033[38;5;45m'
  COLOR_BAR=$'\033[38;5;111m'
  COLOR_DIM=$'\033[2m'
  COLOR_TEXT=$'\033[97m'
}

disable_color

if supports_color; then
  enable_color
fi

usage() {
  cat <<EOF
SYNOPSIS
    ${SCRIPT_NAME} [--seconds N] [--message TEXT] [--help|-h] [--version|-v]
DESCRIPTION
    Render a modern CLI-style loading animation with a spinner, colored progress
    bar, and elapsed feedback for a short demo run.

    Colors are enabled automatically only when stdout looks like a color-capable
    terminal. Set NO_COLOR=1 to force plain output.

OPTIONS
    --seconds N                   Animation duration in seconds (default: ${DEFAULT_SECONDS})
    --message TEXT                Prefix label for the animation (default: ${DEFAULT_MESSAGE})
    -h, --help                    Print this help
    -v, --version                 Print the tool version

EXAMPLES
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --seconds 5 --message "Preparing workspace"
    NO_COLOR=1 ${SCRIPT_NAME}

IMPLEMENTATION
    version         ${VERSION}
EOF
}

short_help() {
  printf '%s\n' "Show a loading animation with automatic color detection; example: ${SCRIPT_NAME} --seconds 5 --message 'Preparing workspace'."
}

print_version() {
  printf '%s\n' "${VERSION}"
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

restore_terminal() {
  if [ -t 1 ]; then
    printf '\033[?25h' >&2 || true
  fi
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

seconds="${DEFAULT_SECONDS}"
message="${DEFAULT_MESSAGE}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --short-help)
      short_help
      exit 0
      ;;
    --version|-v)
      print_version
      exit 0
      ;;
    --seconds)
      shift
      [ "$#" -gt 0 ] || { err "--seconds requires a value"; exit 2; }
      seconds="$1"
      ;;
    --seconds=*)
      seconds="${1#*=}"
      ;;
    --message)
      shift
      [ "$#" -gt 0 ] || { err "--message requires a value"; exit 2; }
      message="$1"
      ;;
    --message=*)
      message="${1#*=}"
      ;;
    --*)
      err "Unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      err "Unexpected positional argument: $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ! is_positive_integer "${seconds}"; then
  err "--seconds must be a positive integer"
  exit 2
fi

frames=("⠁" "⠃" "⠇" "⠧" "⠷" "⠿" "⠷" "⠯" "⠮" "⠟" "⠻" "⠽")
width=24
steps=$(( seconds * 10 ))

trap restore_terminal EXIT INT TERM

if [ -t 1 ]; then
  printf '\033[?25l' >&2
fi

for ((step = 0; step <= steps; step++)); do
  frame="${frames[$(( step % ${#frames[@]} ))]}"
  percent=$(( step * 100 / steps ))
  filled=$(( step * width / steps ))
  empty=$(( width - filled ))

  bar_filled=""
  bar_empty=""
  for ((i = 0; i < filled; i++)); do
    bar_filled+="█"
  done
  for ((i = 0; i < empty; i++)); do
    bar_empty+="░"
  done

  printf '\r%s%s%s %s%-18s%s [%s%s%s%s%s] %s%3d%%%s %s%ss%s' \
    "${COLOR_ACCENT}" "${frame}" "${COLOR_RESET}" \
    "${COLOR_TEXT}" "${message}" "${COLOR_RESET}" \
    "${COLOR_BAR}" "${bar_filled}" "${COLOR_DIM}" "${bar_empty}" "${COLOR_RESET}" \
    "${COLOR_TEXT}" "${percent}" "${COLOR_RESET}" \
    "${COLOR_DIM}" "${seconds}" "${COLOR_RESET}"

  if [ "${step}" -lt "${steps}" ]; then
    sleep 0.1
  fi
done

printf '\n%sDone.%s\n' "${COLOR_ACCENT}" "${COLOR_RESET}"
