#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_CONFIG="${RELEASE_CONFIG:-${WORKSPACE_DIR}/config/release.config.sh}"
VERSION="0.0.0"

release_die() {
  printf '\033[31mRelease failed: %s\033[0m\n' "$1" >&2
  exit 1
}

release_log() {
  printf '%s\n' "$1"
}

if [ ! -r "$RELEASE_CONFIG" ]; then
  release_die "Missing release config: ${RELEASE_CONFIG}"
fi

# shellcheck source=/dev/null
source "$RELEASE_CONFIG"

: "${RELEASE_PROJECT_NAME:?Missing RELEASE_PROJECT_NAME}"
: "${RELEASE_REMOTE:=origin}"
: "${RELEASE_PRESET:=release}"
: "${RELEASE_VERSION_SOURCE:=CMakeLists.txt}"
: "${RELEASE_PROJECT_ROOT:=$WORKSPACE_DIR}"

release_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || release_die "Required command not found: $1"
}

release_project_version() {
  local version_file
  local version

  version_file="${RELEASE_PROJECT_ROOT}/${RELEASE_VERSION_SOURCE}"
  version="$(sed -nE "s/^project\\(${RELEASE_PROJECT_NAME} VERSION ([0-9]+\\.[0-9]+\\.[0-9]+).*$/\\1/p" "$version_file")"

  if [ -z "$version" ]; then
    release_die "Failed to detect the project version from ${version_file}"
  fi

  printf '%s\n' "$version"
}

release_tag() {
  printf 'v%s\n' "$(release_project_version)"
}

release_current_branch() {
  git branch --show-current
}

release_default_branch() {
  local remote_head
  remote_head="$(git symbolic-ref --quiet --short "refs/remotes/${RELEASE_REMOTE}/HEAD" 2>/dev/null || true)"

  if [ -n "$remote_head" ]; then
    printf '%s\n' "${remote_head#${RELEASE_REMOTE}/}"
  else
    printf '%s\n' "main"
  fi
}

release_previous_release_ref() {
  local tag="$1"
  : "$tag"

  git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null \
    || git rev-list --max-parents=0 HEAD
}

release_strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

release_assert_no_warning_lines() {
  local path="$1"
  local warnings_file

  [ -r "$path" ] || release_die "failed to open file: $path"

  warnings_file="$(mktemp)"
  if grep -iE '\bwarning\b' "$path" > "$warnings_file"; then
    printf 'warning(s) found in build log:\n' >&2
    head -n 20 "$warnings_file" >&2
    rm -f "$warnings_file"
    return 1
  fi

  rm -f "$warnings_file"
}

release_verify_checker_output() {
  local path="$1"
  local errors
  local warnings

  [ -r "$path" ] || release_die "failed to open file: $path"

  errors="$(release_strip_ansi < "$path" | sed -nE 's/.*Errors:[[:space:]]*([0-9]+).*/\1/p' | tail -n 1)"
  warnings="$(release_strip_ansi < "$path" | sed -nE 's/.*Warnings:[[:space:]]*([0-9]+).*/\1/p' | tail -n 1)"

  if [ -z "$errors" ] || [ -z "$warnings" ]; then
    printf 'could not parse checker summary\n' >&2
    return 1
  fi

  if [ "$errors" != "0" ] || [ "$warnings" != "0" ]; then
    printf 'checker reported errors=%s warnings=%s\n' "$errors" "$warnings" >&2
    return 1
  fi
}

release_assert_clean_tree() {
  if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
    release_die "Working tree must be clean before releasing"
  fi
}

release_run_logged() {
  local log_file="$1"
  shift

  : > "$log_file"

  set +e
  "$@" 2>&1 | tee "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  return "$status"
}

release_append_section() {
  local notes_path="$1"
  local title="$2"
  shift 2

  [ "$#" -gt 0 ] || return 0

  printf '## %s\n\n' "$title" >> "$notes_path"

  local item
  for item in "$@"; do
    printf -- '- %s\n' "$item" >> "$notes_path"
  done

  printf '\n' >> "$notes_path"
}

release_notes_intro() {
  if declare -F release_config_notes_intro >/dev/null 2>&1; then
    release_config_notes_intro
    return 0
  fi

  printf 'Release generated from %s at %s.\n' "$RELEASE_DEFAULT_BRANCH" "$(git rev-parse --short HEAD)"
}

release_build_release_notes_fallback() {
  local notes_path="$1"
  local previous_ref="$2"
  local notes_head="$3"
  local commit_count="$4"
  local tag="$5"
  local subject
  local -a features=()
  local -a fixes=()
  local -a docs=()
  local -a chores=()
  local -a others=()

  cat > "$notes_path" <<EOF
# ${tag}

$(release_notes_intro)

## Overview

- ${commit_count} commit(s) since ${previous_ref}

EOF

  if [ "$commit_count" -eq 0 ]; then
    printf '## Changes\n\n- No changes\n' >> "$notes_path"
    return 0
  fi

  while IFS= read -r subject; do
    [ -n "$subject" ] || continue

    case "$subject" in
      feat:*|add:*) features+=("${subject#*: }") ;;
      fix:*|bugfix:*) fixes+=("${subject#*: }") ;;
      docs:*) docs+=("${subject#*: }") ;;
      chore:*|refactor:*|build:*|ci:*|test:*) chores+=("${subject#*: }") ;;
      *) others+=("$subject") ;;
    esac
  done < <(git log --no-merges --pretty=format:'%s' "${previous_ref}..${notes_head}")

  release_append_section "$notes_path" "Features" "${features[@]}"
  release_append_section "$notes_path" "Fixes" "${fixes[@]}"
  release_append_section "$notes_path" "Documentation" "${docs[@]}"
  release_append_section "$notes_path" "Maintenance" "${chores[@]}"
  release_append_section "$notes_path" "Other Changes" "${others[@]}"
}

release_extract_md_block() {
  awk '
    /^```md[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { exit }
    in_block { print }
  '
}

release_generate_release_notes_with_ai() {
  local notes_path="$1"
  local previous_ref="$2"
  local notes_head="$3"
  local commit_count="$4"
  local tag="$5"
  local commit_log
  local code_fence='```'
  local prompt
  local ai_output
  local markdown_block

  command -v opencode >/dev/null 2>&1 || return 1

  if [ "$commit_count" -eq 0 ]; then
    release_build_release_notes_fallback "$notes_path" "$previous_ref" "$notes_head" "$commit_count" "$tag"
    return 0
  fi

  commit_log="$(git log --no-merges --pretty=format:'- %h %s' "${previous_ref}..${notes_head}")"

  prompt=$(cat <<EOF
Create release notes for ${RELEASE_PROJECT_NAME}.

Compare commits from ${previous_ref} to ${notes_head}.
Return ONLY one fenced markdown block using this exact fence style:

${code_fence}md
...
${code_fence}

Rules:
- group related commits together
- rewrite raw commit messages into clear user-facing release notes
- avoid mentioning internal noise unless it matters for users
- keep the output concise but useful
- include Overview, Highlights, and Notable Fixes sections when applicable
- if there are no meaningful changes for a section, omit that section

Commits:
${commit_log}
EOF
)

  ai_output="$(opencode run "$prompt")" || return 1
  markdown_block="$(printf '%s\n' "$ai_output" | release_extract_md_block)"

  [ -n "$markdown_block" ] || return 1

  printf '%s\n' "$markdown_block" > "$notes_path"
}

release_generate_release_notes() {
  local notes_path="$1"
  local previous_ref="$2"
  local notes_head="$3"
  local commit_count="$4"
  local tag="$5"

  if release_generate_release_notes_with_ai "$notes_path" "$previous_ref" "$notes_head" "$commit_count" "$tag"; then
    return 0
  fi

  release_log "Falling back to deterministic release notes generation"
  release_build_release_notes_fallback "$notes_path" "$previous_ref" "$notes_head" "$commit_count" "$tag"
}

release_copy_asset() {
  cp "$1" "$2"
}

release_package_assets() {
  local release_dir="$1"
  local artifact_dir="$2"
  local tag="$3"
  local -a release_assets=()
  local extra_assets_output

  mkdir -p "$artifact_dir"

  release_copy_asset "$RELEASE_PACKAGE_BINARY_PATH" "$artifact_dir/${RELEASE_PACKAGE_BINARY_ASSET_NAME}"
  release_assets+=("$artifact_dir/${RELEASE_PACKAGE_BINARY_ASSET_NAME}")

  if [ -n "${RELEASE_RULES_PATH:-}" ] && [ -f "$RELEASE_RULES_PATH" ]; then
    release_copy_asset "$RELEASE_RULES_PATH" "$artifact_dir/${RELEASE_RULES_ASSET_NAME}.yaml"
    release_assets+=("$artifact_dir/${RELEASE_RULES_ASSET_NAME}.yaml")
  fi

  if [ -n "${RELEASE_IGNORE_PATHS_PATH:-}" ] && [ -f "$RELEASE_IGNORE_PATHS_PATH" ]; then
    release_copy_asset "$RELEASE_IGNORE_PATHS_PATH" "$artifact_dir/${RELEASE_IGNORE_PATHS_ASSET_NAME}"
    release_assets+=("$artifact_dir/${RELEASE_IGNORE_PATHS_ASSET_NAME}")
  fi

  if declare -F release_config_package_extra_assets >/dev/null 2>&1; then
    extra_assets_output="$(release_config_package_extra_assets "$release_dir" "$artifact_dir" "$tag")"

    if [ -n "$extra_assets_output" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        release_assets+=("$line")
      done <<EOF
$extra_assets_output
EOF
    fi
  fi

  printf '%s\n' "${release_assets[@]}"
}

usage() {
  cat <<EOF
SYNOPSIS
    $0 [--help|-h] [--version|-v]

DESCRIPTION
    Run the ${RELEASE_PROJECT_NAME} release flow.

OPTIONS
    -h, --help                    Print this help.
    --short-help                  Print a one-line summary.
    -v, --version                 Print the project version.

PARAMETERS
    none                          This command does not accept positional arguments.

EXAMPLES
    $0

DEPENDENCIES
    git, gh, cmake, sha256sum, ${RELEASE_CONFIG}

IMPLEMENTATION
    version         ${VERSION}
EOF
}

short_help() {
  printf 'Run the %s release flow; example: %s; dependencies: git, gh, cmake, sha256sum.\n' "$RELEASE_PROJECT_NAME" "$0"
}

release_main() {
  local current_branch
  local tag
  local build_dir
  local release_dir
  local artifact_dir
  local notes_path
  local sha_path
  local build_log
  local checker_log
  local previous_ref
  local notes_head
  local commit_count
  local -a release_assets=()

  release_require_cmd git
  release_require_cmd cmake
  release_require_cmd gh
  release_require_cmd sha256sum

  if ! gh api user >/dev/null 2>&1; then
    release_die "GitHub auth not working. Please run 'gh auth login' to authenticate or add GH_TOKEN to the environment."
  fi

  cd "$RELEASE_PROJECT_ROOT"

  tag="$(release_tag)"
  current_branch="$(release_current_branch)"
  RELEASE_DEFAULT_BRANCH="$(release_default_branch)"

  if git ls-remote --exit-code --tags "$RELEASE_REMOTE" "refs/tags/${tag}" >/dev/null 2>&1; then
    release_die "Version ${tag} already pushed to ${RELEASE_REMOTE}"
  fi

  if [ "$current_branch" != "$RELEASE_DEFAULT_BRANCH" ]; then
    release_die "Release can only run from ${RELEASE_DEFAULT_BRANCH}; current branch is ${current_branch}"
  fi

  release_assert_clean_tree

  release_log "Pulling latest ${RELEASE_DEFAULT_BRANCH} from ${RELEASE_REMOTE}"
  git pull --ff-only "$RELEASE_REMOTE" "$RELEASE_DEFAULT_BRANCH"

  release_assert_clean_tree

  build_dir="${RELEASE_BUILD_DIR:-${RELEASE_PROJECT_ROOT}/build/${RELEASE_PRESET}}"
  release_dir="${RELEASE_RELEASE_DIR:-${build_dir}/release-${tag}}"
  artifact_dir="${RELEASE_ARTIFACT_DIR:-${release_dir}/assets}"
  notes_path="${RELEASE_NOTES_PATH:-${release_dir}/release-notes-${tag}.md}"
  sha_path="${RELEASE_SHA_PATH:-${release_dir}/SHA256SUMS}"
  build_log="${RELEASE_BUILD_LOG:-${release_dir}/build.log}"
  checker_log="${RELEASE_CHECKER_LOG:-${release_dir}/checker.log}"

  mkdir -p "$release_dir"

  release_log "Configuring release build on ${RELEASE_DEFAULT_BRANCH}"
  if ! release_run_logged "$build_log" cmake --preset "$RELEASE_PRESET"; then
    release_die "CMake configure failed (see ${build_log})"
  fi
  release_assert_no_warning_lines "$build_log" || release_die "Warnings found during configure (see ${build_log})"

  if ! release_run_logged "$build_log" cmake --build --preset "$RELEASE_PRESET" -j"$(nproc)"; then
    release_die "Build failed (see ${build_log})"
  fi
  release_assert_no_warning_lines "$build_log" || release_die "Warnings found during build (see ${build_log})"

  release_log "Preparing release ${tag} from version declared in ${RELEASE_VERSION_SOURCE}"

  [ -x "$RELEASE_PACKAGE_BINARY_PATH" ] || release_die "Built binary not found: ${RELEASE_PACKAGE_BINARY_PATH}"

  if declare -F release_config_run_checker >/dev/null 2>&1; then
    release_log "Running checker validation"

    if ! release_run_logged "$checker_log" release_config_run_checker "$checker_log"; then
      release_die "Checker execution failed (see ${checker_log})"
    fi

    release_verify_checker_output "$checker_log" || release_die "Checker reported warnings or errors (see ${checker_log})"
  fi

  if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    release_die "Tag already exists locally: ${tag}"
  fi

  previous_ref="$(release_previous_release_ref "$tag")"
  notes_head="$(git rev-parse HEAD 2>/dev/null || true)"
  commit_count="$(git rev-list --count "${previous_ref}..${notes_head}")"

  release_log "Packaging release artifacts"
  mapfile -t release_assets < <(release_package_assets "$release_dir" "$artifact_dir" "$tag")

  release_generate_release_notes "$notes_path" "$previous_ref" "$notes_head" "$commit_count" "$tag"

  sha256sum "${release_assets[@]}" > "$sha_path"

  release_log "Tagging release ${tag}"
  git tag -a "$tag" -m "Release ${tag}"
  git push "$RELEASE_REMOTE" "refs/tags/${tag}"

  release_log "Creating GitHub release ${tag}"
  gh release create "$tag" \
    --title "$tag" \
    --notes-file "$notes_path" \
    "${release_assets[@]}" \
    "$sha_path"

  release_log "Release completed: ${tag}"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --short-help)
    short_help
    exit 0
    ;;
  -v|--version)
    release_project_version
    exit 0
    ;;
  "")
    release_main
    ;;
  *)
    printf 'This command does not accept positional arguments.\n' >&2
    usage >&2
    exit 1
    ;;
esac
