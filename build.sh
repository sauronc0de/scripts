#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.0.0"

usage() {
  cat <<EOF
SYNOPSIS
    $0 [--help|-h] [--version|-v] TARGET PRESET
DESCRIPTION
    Build a CMake target with the selected preset and save the full log to
    build/PRESET/build.log.
===============================================================
OPTIONS
    -h, --help                    Print this help.
    -v, --version                 Print the tool version.
===============================================================
PARAMETERS
    TARGET                        Build target name. Use all to build the
                                  preset default target.
                                  Example: all
    PRESET                        CMake preset used for configure/build output.
                                  Example: release
===============================================================
EXAMPLES
    $0 all release
    $0 all develop
    $0 app_name develop
===============================================================
DEPENDENCIES
    cmake, nproc, tee, grep
===============================================================
IMPLEMENTATION
    version         ${VERSION}
EOF
}

short_help() {
  printf '%s\n' "Build a CMake target and log output; example: $0 all release; dependencies: cmake and nproc."
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

if [ "$#" -ne 2 ]; then
  printf 'Expected exactly 2 arguments: TARGET PRESET.\n' >&2
  usage >&2
  exit 1
fi

target="$1"
preset="$2"

JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"

build_dir="build/${preset}"
mkdir -p "${build_dir}"
log_file="${build_dir}/build.log"

{
echo "Build project"
echo "Date: $(date)"
echo "CMake preset: ${preset}"
echo "Target: ${target}"
echo "Parallel jobs: ${JOBS}"

echo "Configuring (cmake --preset ${preset}) ..."
cmake --preset "${preset}" || exit 1

echo "Building target '${target}' ..."
build_cmd=(cmake --build --preset "${preset}" -j"${JOBS}")
if [ "${target}" != "all" ]; then
  build_cmd+=(--target "${target}")
fi

if command -v /usr/bin/time >/dev/null 2>&1; then
  /usr/bin/time -f "elapsed: %E | user: %U | sys: %S | maxrss: %M KB" "${build_cmd[@]}" || exit 1
else
  SECONDS=0
  "${build_cmd[@]}" || exit 1
  echo "elapsed: ${SECONDS}s"
fi

echo "Build completed successfully"

} > >(tee "${log_file}") 2>&1

first_error_line="$(grep -Einm1 '(^|[^[:alnum:]_-])(fatal error:|error:)' "${log_file}" | cut -d: -f1 || true)"
if [ -n "${first_error_line}" ]; then
  echo "First error at ${log_file}:${first_error_line}"
fi
