#!/usr/bin/env bash

###############################################################################
# snake_func.sh
#
# Rename files and directories to snake_case.
#
# Usage:
#   snake [-h] [-r] [-p] [-o] <path>
#
# Options:
#   -h, --help         Show help and exit
#   -r, --recursive    Process directory contents recursively
#   -p, --period       Preserve periods instead of replacing them
#   -o, --overwrite    Overwrite existing targets instead of adding _N suffixes
#
# This file is intended to be sourced from a shell rc file:
#   source /path/to/snake_func.sh
###############################################################################

###############################################################################
# Help text
#
# Printed by `snake -h` and `snake --help`.
###############################################################################
_SNAKE_HELP="Usage: snake [OPTIONS] [path]

Convert filenames and directory names to snake_case format.

Options:
  -h, --help         Show this help message and exit
  -r, --recursive    Process directories recursively
  -p, --period       Preserve periods (don't replace with underscores)
  -o, --overwrite    Overwrite existing targets instead of adding _N suffixes

Arguments:
  path               File or directory path to rename
                     (default: the current directory)


Behavior:
  When the target filename already exists, appends _N suffix where N is an
  incrementing number (e.g., file_1.txt, file_2.txt) to prevent overwriting.
  Use -o/--overwrite to replace existing target files instead of adding a
  suffix. When the target is an existing directory, the source is moved inside
  it under its transformed snake_case name.
  Skips renaming if the transformed name matches the original filename.
  If path is omitted, or is . or ./, the entries in the current directory are
  processed. Add -r to process subdirectories as well.

Examples:
  snake myfile.txt                    # Rename a file
  snake my directory/                 # Rename a directory
  snake -r my directory/              # Rename files recursively
  snake -p subject.status.date/       # Preserve periods in directory name
  snake -o myfile.txt                 # Overwrite an existing target file
  snake -r -p -o my directory/        # Recursive, preserve periods, overwrite
  snake .                             # Process the current directory
  snake -r                            # Process the current directory recursively

The snake function converts spaces, special characters, and mixed case
names to snake_case format for consistent naming across systems.

By default, periods are replaced with underscores, except for the period
separating the filename and extension. Use -p/--period to preserve all
periods in names.
"

###############################################################################
# snake_transform
#
# Convert an arbitrary string to snake_case.
#
# Parameters:
#   $1: input string
#   $2: replace_periods (1=replace periods with underscores, 0=preserve them)
#
# Returns:
#   The transformed string on stdout.
###############################################################################
snake_transform() {
  local input="$1"
  local replace_periods="${2:-0}"
  local result
  local period_marker=$'\001'
  local bracket_marker=$'\002'

  # Convert to lowercase
  result="$(echo "$input" | tr '[:upper:]' '[:lower:]')"

  # Replace spaces with underscores first so word boundaries are preserved.
  result="${result// /_}"

  # Handle periods according to the caller's preference. When periods are
  # preserved they are hidden behind a marker that cannot occur in a filename,
  # so later separator collapsing does not turn them into underscores.
  if [ "$replace_periods" = "1" ]; then
    result="${result//./$period_marker}"
  else
    result="${result//./_}"
  fi

  # Replace the remaining supported punctuation with underscores.
  result="${result//,/_}"
  result="${result//!/_}"
  result="${result//=/_}"
  result="${result//\\/_}"
  result="${result//|/_}"
  result="${result//·/_}"

  # Brackets are word separators. Replace them with a temporary marker first
  # so brackets next to preserved periods can be handled cleanly.
  result="${result//\[/$bracket_marker}"
  result="${result//\]/$bracket_marker}"
  result="${result//\(/$bracket_marker}"
  result="${result//\)/$bracket_marker}"
  result="${result//\{/$bracket_marker}"
  result="${result//\}/$bracket_marker}"
  result="${result//</$bracket_marker}"
  result="${result//>/$bracket_marker}"

  # When periods are preserved, a bracket directly beside a period should not
  # leave an extra underscore on the other side of that period.
  if [ "$replace_periods" = "1" ]; then
    result="${result//$bracket_marker$period_marker/$period_marker}"
    result="${result//$period_marker$bracket_marker/$period_marker}"
  fi

  # Remaining brackets become ordinary word separators.
  result="${result//$bracket_marker/_}"

  # Treat hyphens as word separators in snake_case.
  result="${result//-/_}"

  # Apostrophes are removed outright rather than turned into separators.
  result="${result//\'/}"
  result="${result//’/}"

  # Collapse runs of underscores into a single underscore.
  result="$(echo "$result" | tr -s '_')"

  # Restore preserved periods and collapse repeated periods.
  if [ "$replace_periods" = "1" ]; then
    result="$(echo "$result" | tr -s '\001')"
    result="${result//$period_marker/.}"
  fi

  # Strip trailing separators or other non-alphanumeric characters.
  result="$(echo "$result" | sed -E 's/[^[:alnum:]]*$//')"

  echo "$result"
}

###############################################################################
# generate_unique_name
#
# Produce a non-colliding filename in the target directory by appending an
# incrementing _N suffix before the extension.
#
# Parameters:
#   $1: directory path
#   $2: desired filename
#   $3: has_extension (true when the _N suffix belongs before the extension)
#   $4: optional source path; a target that is the same file is not a collision
#
# Returns:
#   The unique filename on stdout. If no collision exists, $2 is returned.
###############################################################################
generate_unique_name() {
  local dirpath="$1"
  local desired_name="$2"
  local has_extension="${3:-false}"
  local source_path="${4:-}"
  local stem="$desired_name" ext="" counter
  local target_path="${dirpath}/${desired_name}"

  # If the target does not exist, or it is the source file itself (which
  # happens with case-only renames on case-insensitive filesystems), use the
  # desired name as-is.
  if [ ! -e "$target_path" ] || { [ -n "$source_path" ] && [ "$target_path" -ef "$source_path" ]; }; then
    echo "$desired_name"
    return
  fi

  # Split off a real extension so the suffix is inserted before it. Directories
  # and extensionless files keep their whole name as the stem.
  if [ "$has_extension" = true ]; then
    stem="${desired_name%.*}"
    ext="${desired_name##*.}"
  fi

  # Count upward from 1 until an unused name is found.
  counter=1
  while [ -e "$target_path" ]; do
    if [ "$has_extension" = true ]; then
      desired_name="${stem}_${counter}.${ext}"
    else
      desired_name="${stem}_${counter}"
    fi
    target_path="${dirpath}/${desired_name}"
    counter=$((counter + 1))
  done

  echo "$desired_name"
}

###############################################################################
# snake
#
# Main entry point. Parses options, transforms the supplied name, optionally
# resolves collisions, renames the path, and recurses when requested.
#
# Parameters:
#   Options followed by an optional file or directory path. A missing path,
#   "." or "./" processes entries in the current directory.
#
# Returns:
#   0 on success or when no rename is needed, 1 on invalid options.
###############################################################################
snake() {
  # Defaults; all flags are boolean strings used in comparisons below.
  local recursive=false
  local preserve_periods=false
  local overwrite=false
  # Do not name this variable "path": in zsh, "path" is tied to PATH.
  local target=""

  # zsh treats unmatched globs as errors by default. Null-glob makes the
  # directory loops below behave like bash when a directory is empty.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions nullglob
  fi

  #############################################################################
  # Option parsing
  #
  # Options may appear in any order before the path. Unknown options fail with
  # a usage message rather than being treated as paths.
  #############################################################################
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      echo "$_SNAKE_HELP"
      return 0
      ;;
    -r | --recursive)
      recursive=true
      shift
      ;;
    -p | --period)
      preserve_periods=true
      shift
      ;;
    -o | --overwrite)
      overwrite=true
      shift
      ;;
    -*)
      echo "Usage: snake [-r|--recursive] [-p|--period] [-o|--overwrite] <path>" >&2
      return 1
      ;;
    *)
      target="$1"
      shift
      ;;
    esac
  done

  # A missing path means "process the current directory".
  if [ -z "$target" ]; then
    target="."
  fi

  #############################################################################
  # Current-directory mode
  #
  # `snake .`, `snake ./`, and flag-only invocations such as `snake -r` process
  # the entries inside the current directory instead of trying to rename the
  # "." path itself. Without -r only immediate entries are handled; with -r
  # each entry is processed recursively.
  #############################################################################
  if [ "$target" = "." ] || [ "$target" = "./" ]; then
    local -a current_args=()
    if [ "$recursive" = true ]; then
      current_args+=(-r)
    fi
    if [ "$preserve_periods" = true ]; then
      current_args+=(-p)
    fi
    if [ "$overwrite" = true ]; then
      current_args+=(-o)
    fi

    for entry in ./*; do
      [ -e "$entry" ] && snake "${current_args[@]}" "$entry"
    done
    return 0
  fi

  #############################################################################
  # Validate the target
  #
  # Fail clearly instead of attempting a move that cannot succeed.
  #############################################################################
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    echo "snake: path not found: $target" >&2
    return 1
  fi

  #############################################################################
  # Split the path
  #
  # dirpath is where the rename happens; name is the final path component.
  # Leading and trailing whitespace is removed from name before transforming.
  #############################################################################
  local dirpath
  dirpath="$(dirname "$target")"
  local name
  name="$(basename "$target")"
  name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  #############################################################################
  # Separate base name and extension
  #
  # Only regular files are split. Directories and other path types are treated
  # as a single base name. Extensions are always transformed with periods
  # replaced, since a period inside an extension has no structural meaning.
  #############################################################################
  local base ext new_base new_ext
  local has_extension=false
  if [ -f "$target" ] && [[ "$name" == *.* ]] && [ -n "${name##*.}" ]; then
    base="${name%.*}"
    ext="${name##*.}"
    ext="$(echo "$ext" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "$ext" ]; then
      has_extension=true
      new_ext="$(snake_transform "$ext" 0)"
    else
      # A trailing period is not a real extension; treat the whole name as base.
      base="$name"
      new_ext=""
    fi
  else
    base="$name"
    ext=""
    new_ext=""
  fi

  #############################################################################
  # Transform the base name
  #
  # -p changes whether periods inside the base are preserved or replaced.
  #############################################################################
  if [ "$preserve_periods" = true ]; then
    new_base="$(snake_transform "$base" 1)"
  else
    new_base="$(snake_transform "$base" 0)"
  fi

  #############################################################################
  # Rebuild the target name
  #
  # Only names with a real extension get the transformed extension appended.
  # Directories and extensionless files use the transformed base by itself.
  #############################################################################
  local new_name
  if [ "$has_extension" = true ]; then
    new_name="${new_base}.${new_ext}"
  else
    new_name="${new_base}"
  fi

  #############################################################################
  # No-op check
  #
  # If the transformed name already matches the original, there is nothing to
  # rename and recursion can stop for this path.
  #############################################################################
  local original_name
  original_name="$(basename "$target")"
  if [ "$new_name" = "$original_name" ]; then
    return 0
  fi

  #############################################################################
  # Collision handling
  #
  # Default: ask generate_unique_name for a free name with an _N suffix.
  # With -o: keep the desired name and let the move replace or merge onto it.
  #############################################################################
  local final_name
  if [ "$overwrite" = true ]; then
    final_name="$new_name"
  else
    final_name="$(generate_unique_name "$dirpath" "$new_name" "$has_extension" "$target")"
  fi
  new_name="$final_name"
  local new_path="${dirpath}/${new_name}"
  local dest_path="$new_path"

  # When overwriting into an existing directory, a plain mv would place the
  # source inside under its original name. Descend using the transformed name
  # instead, so the moved entry always keeps its snake_case name. A case-only
  # target on a case-insensitive filesystem is the source itself, so do not
  # descend into it.
  if [ "$overwrite" = true ]; then
    while [ -d "$dest_path" ] && ! [ "$dest_path" -ef "$target" ]; do
      dest_path="${dest_path}/${new_name}"
    done
  fi

  #############################################################################
  # Rename
  #
  # Absolute paths are compared so a difference in spelling does not trigger a
  # pointless move. mv -f is used only when overwriting so the default mode
  # keeps its existing, conservative behavior.
  #############################################################################
  local abs_path abs_dest_path
  abs_path="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"
  abs_dest_path="$(cd "$(dirname "$dest_path")" 2>/dev/null && pwd)/$(basename "$dest_path")"

  if [ "$abs_path" != "$abs_dest_path" ]; then
    if [ "$overwrite" = true ]; then
      mv -f "$target" "$dest_path"
    else
      mv "$target" "$dest_path"
    fi
    echo "Renamed '$target' to '$dest_path'"
    target="$dest_path"
  fi

  #############################################################################
  # Recursion
  #
  # When -r is active and the result is a directory, process each entry. All
  # active flags are forwarded so -p and -o also apply below the top level.
  #############################################################################
  if [ "$recursive" = true ] && [ -d "$target" ]; then
    local -a recurse_args=(-r)
    if [ "$preserve_periods" = true ]; then
      recurse_args+=(-p)
    fi
    if [ "$overwrite" = true ]; then
      recurse_args+=(-o)
    fi

    for entry in "$target"/*; do
      [ -e "$entry" ] && snake "${recurse_args[@]}" "$entry"
    done
  fi
}
