#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="0.0.0"

ROOTS=()
RECURSIVE=1
VERBOSE=0
COLOR_MODE=auto
USE_COLOR=0

set_color() {
    if [ "$COLOR_MODE" = "always" ] || { [ "$COLOR_MODE" = "auto" ] && [ -t 1 ]; }; then
        USE_COLOR=1
        C_RESET='\033[0m'
        C_LABEL='\033[1;36m'
        C_SEPARATOR='\033[90m'
        C_TOOL='\033[1;32m'
        C_INFO='\033[1;34m'
        C_ERROR='\033[1;31m'
    else
        USE_COLOR=0
        C_RESET=''
        C_LABEL=''
        C_SEPARATOR=''
        C_TOOL=''
        C_INFO=''
        C_ERROR=''
    fi
}

color_text() {
    color="$1"
    text="$2"

    if [ "$USE_COLOR" -eq 1 ]; then
        printf '%b%s%b' "$color" "$text" "$C_RESET"
    else
        printf '%s' "$text"
    fi
}

print_padded() {
    color="$1"
    text="$2"
    width="$3"
    padding=$((width - ${#text}))

    color_text "$color" "$text"
    while [ "$padding" -gt 0 ]; do
        printf ' '
        padding=$((padding - 1))
    done
}

print_tool_row() {
    name="$1"
    description="$2"

    print_padded "$C_TOOL" "$name" 25
    printf ' | %s\n' "$description"
}

usage() {
    cat <<EOF
 SYNOPSIS
    ${SCRIPT_NAME} [-hv] [--root DIR] [--no-recursive]

 DESCRIPTION
    Lists --short-help from executable scripts and binaries.

    Default scan path:
      ${SCRIPT_DIR}

 OPTIONS
    --root DIR          Scan this directory instead of defaults
    --color             Force color output
    --no-color          Disable color output
    -r, --recursive     Scan recursively (default)
    --no-recursive      Disable recursive scanning
    --verbose           Print diagnostics to stderr
    -h, --help          Print this help
    -v, --version       Print version

 EXAMPLES
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --no-recursive
    ${SCRIPT_NAME} --root ./scripts

IMPLEMENTATION
    version         ${VERSION}
EOF
}

log() {
    [ "$VERBOSE" -eq 1 ] && printf '%s %s\n' "$(color_text "$C_INFO" '[INFO]')" "$*" >&2
}

err() {
    printf '%s %s\n' "$(color_text "$C_ERROR" '[ERROR]')" "$*" >&2
}

set_color

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            shift
            [ "$#" -gt 0 ] || { err "--root requires a value"; exit 2; }
            ROOTS+=("$1")
            ;;
        --root=*)
            ROOTS+=("${1#*=}")
            ;;
        --color)
            COLOR_MODE=always
            set_color
            ;;
        --no-color)
            COLOR_MODE=never
            set_color
            ;;
        -r|--recursive)
            RECURSIVE=1
            ;;
        --no-recursive)
            RECURSIVE=0
            ;;
        --verbose)
            VERBOSE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            printf '%s\n' "$VERSION"
            exit 0
            ;;
        --short-help)
            printf 'List scripts recursively by default; example: %s --no-recursive --root ./scripts.\n' "$SCRIPT_NAME"
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            exit 2
            ;;
    esac
    shift
done

set_color

if [ "${#ROOTS[@]}" -eq 0 ]; then
    ROOTS=("$SCRIPT_DIR")
fi

self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"

run_tool() {
    tool="$1"
    display_name="$2"

    tool_path="$(readlink -f "$tool" 2>/dev/null || printf '%s\n' "$tool")"

    [ "$tool_path" = "$self_path" ] && return 0
    [ -x "$tool" ] || return 0
    [ -f "$tool" ] || return 0

    # 1. Try --short-help
    output="$("$tool" --short-help 2>/dev/null)"
    if [ $? -eq 0 ] && [ -n "$output" ]; then
        output="$(printf '%s\n' "$output" | head -n 1 | sed 's/[[:space:]]\+/ /g')"
        print_tool_row "$display_name" "$output"
        return 0
    fi

    # 2. Fallback to --help (first line)
    output="$("$tool" --help 2>/dev/null | head -n 1)"
    if [ -n "$output" ]; then
        output="$(printf '%s\n' "$output" | sed 's/[[:space:]]\+/ /g')"
        print_tool_row "$display_name" "$output"
        return 0
    fi

    # 3. Final fallback → just list it
    print_tool_row "$display_name" "(no help available)"
}

tmp_scan="$(mktemp)"
tmp_unique="$(mktemp)"
trap 'rm -f "$tmp_scan" "$tmp_unique"' EXIT

declare -A SEEN_ABS
declare -A BASENAME_COUNT

for root in "${ROOTS[@]}"; do
    if [ ! -d "$root" ]; then
        log "Skipping missing directory: $root"
        continue
    fi

    log "Scanning: $root"

    if [ "$RECURSIVE" -eq 1 ]; then
        while IFS= read -r tool; do
            tool_path="$(readlink -f "$tool" 2>/dev/null || printf '%s\n' "$tool")"
            [ "$tool_path" = "$self_path" ] && continue
            [ -n "${SEEN_ABS[$tool_path]+x}" ] && continue
            SEEN_ABS["$tool_path"]=1
            printf '%s\t%s\n' "$tool_path" "$root" >> "$tmp_unique"
            printf '%s\n' "$tool_path" >> "$tmp_scan"
        done < <(find "$root" -type f -executable)
    else
        while IFS= read -r tool; do
            tool_path="$(readlink -f "$tool" 2>/dev/null || printf '%s\n' "$tool")"
            [ "$tool_path" = "$self_path" ] && continue
            [ -n "${SEEN_ABS[$tool_path]+x}" ] && continue
            SEEN_ABS["$tool_path"]=1
            printf '%s\t%s\n' "$tool_path" "$root" >> "$tmp_unique"
            printf '%s\n' "$tool_path" >> "$tmp_scan"
        done < <(find "$root" -maxdepth 1 -type f -executable)
    fi
done

if [ ! -s "$tmp_scan" ]; then
    err "No executable files found."
    exit 1
fi

while IFS=$'\t' read -r tool_path scan_root; do
    base_name="$(basename "$tool_path")"
    BASENAME_COUNT["$base_name"]=$(( ${BASENAME_COUNT["$base_name"]:-0} + 1 ))
done < "$tmp_unique"

printf '\n'
print_padded "$C_LABEL" "TOOL" 25
printf ' %s %s\n' "$(color_text "$C_SEPARATOR" '|')" "$(color_text "$C_LABEL" 'DESCRIPTION')"
color_text "$C_SEPARATOR" '--------------------------+----------------------------------------------'
printf '\n'

while IFS=$'\t' read -r tool_path scan_root; do
    base_name="$(basename "$tool_path")"
    display_name="$base_name"

    if [ "${BASENAME_COUNT[$base_name]}" -gt 1 ]; then
        case "$tool_path" in
            "$scan_root"/*)
                display_name="${tool_path#"$scan_root"/}"
                ;;
            *)
                display_name="$tool_path"
                ;;
        esac
    fi

    run_tool "$tool_path" "$display_name"
done < "$tmp_unique"

printf '\n'
