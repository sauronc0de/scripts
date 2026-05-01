# Scripts Guidelines

## Rules
- Prefer Bash (sh) for orchestration and C++ for logic over other languages
- Keep scripts thin

## Conventions

### Naming
- Use `snake_case` for tool names, files, and flags
- Project-specific scripts must use the `${PROJECT_NAME}_` prefix.
  - A script is project-specific when it encodes this repository's build, run, release, cleanup, simulation, paths, project metadata, or other `checkpp`-only workflow assumptions.
  - Example: use `checkpp_simulate.sh` instead of `simulate.sh` for a simulator wrapper that belongs to this project.
- Portable or reusable scripts must keep a generic name without the project prefix.
  - A script is portable/reusable when it can run unchanged in another repository or environment and does not depend on `checkpp` project state, paths, build presets, release metadata, or conventions.
  - Example: keep `tree_view.sh` instead of `checkpp_tree_view.sh` for a generic ASCII tree printer.

### Review expectations
- During script reviews, classify each executable script as either project-specific or portable/reusable before applying the prefix rule.
- Flag a missing `${PROJECT_NAME}_` prefix only for project-specific executable scripts.
- Flag an unnecessary `${PROJECT_NAME}_` prefix when a script is portable/reusable and has no project-specific dependency.
- Non-entrypoint support files such as sourced config fragments may use descriptive generic names when they are not intended to be executed directly.

### Structure
- Scripts → `scripts/`

### Mandatory Flags
- `--help` / `-h`:
  - At least this fields: SYNOPSIS, DESCRIPTION, OPTIONS, EXAMPLES, IMPLEMENTATION.
  - Template format:
```bash
 SYNOPSIS
    ${SCRIPT_NAME} [-hv] [-o[file]] args ...
 DESCRIPTION
    This is a script template
    to start any good shell script.

 OPTIONS
    -o [file], --output=[file]    Set log file (default=/dev/null)
                                  use DEFAULT keyword to autoname file
                                  The default value is /dev/null.
    -t, --timelog                 Add timestamp to log ("+%y/%m/%d@%H:%M:%S")
    -x, --ignorelock              Ignore if lock file exists
    -h, --help                    Print this help
    -v, --version                 Print script information

 EXAMPLES
    ${SCRIPT_NAME} -o DEFAULT arg1 arg2

 IMPLEMENTATION
    version         0.0.4
    project         project_name
```
   - On IMPLEMENTATION the field of project only should exist for non portable/reusable, project specific, scripts. For portable scripts the field shall not exist.
- `--short-help`:
  - One line (≤160 chars): description + example (+ key dependency if critical)

- `--version` / `-v`:
  - Displays the current version of the command/tool.

### I/O
- stdout = results, stderr = errors
- Support piping, avoid interactive prompts

### Args
- Prefer flags (`--input`, `--output`)
- Provide defaults, fail clearly on invalid input

### Defaults
- Declare all default values as macros/constants in an init section for easy editing.

```bash
DEFAULT_SECONDS=5
DEFAULT_MESSAGE="Loading"
```
- Reuse the existing environment variables instead of defining new ones:
   - `${WORKSPACE_DIR}`: Root directory of the project.
   - `${PROJECT_NAME}`: Project name.

### Exit codes
- `0` = success, non-zero = error

### General
- Minimize dependencies
- Idempotent behavior
- Optional `--verbose` for logs
