#!/usr/bin/env bash

# Help text for the snake function
_SNAKE_HELP="Usage: snake [OPTIONS] <path>

Convert filenames and directory names to snake_case format.

Options:
  -h, --help         Show this help message and exit
  -r, --recursive    Process directories recursively
  -p, --period       Preserve periods (don't replace with underscores)

Arguments:
  path               File or directory path to rename

Examples:
  snake myfile.txt                    # Rename a file
  snake my directory/                 # Rename files in a directory (non-recursive)
  snake -r my directory/              # Rename files recursively
  snake -p subject.status.date/       # Preserve periods in directory name

The snake function converts spaces, special characters, and mixed case
names to snake_case format for consistent naming across systems.

By default, periods are replaced with underscores, except for the period
separating the filename and extension. Use -p/--period to preserve all
periods in names.
"

# Transform a string to snake_case
# Parameters:
#   $1: input string
#   $2: whether to replace periods (1=yes, 0=no, default=0)
snake_transform() {
  local input="$1"
  local replace_periods="${2:-0}"
  local result
  
  # Convert to lowercase
  result="$(echo "$input" | tr '[:upper:]' '[:lower:]')"
  
  # Replace all special characters with underscores
  result="${result// /_}"
  if [ "$replace_periods" = "1" ]; then
    # When preserving periods: replace periods with underscores, collapse, then convert back
    result="${result//./_}"
    # Collapse multiple underscores
    result="$(echo "$result" | tr -s '_')"
    # Convert underscores back to periods (single _ -> single .)
    result="${result//_/\\.}"
  else
    # Replace periods with underscores (default behavior)
    result="${result//./_}"
  fi
  result="${result//,/_}"
  result="${result//!/_}"
  result="${result//|/_}"
  result="${result//·/_}"
  result="$(echo "$result" | sed "s/[\'’]//g")"
  
  # Collapse multiple underscores or hyphens into single characters
  result="$(echo "$result" | tr -s '_-')"
  
  # Remove trailing non-alphanumeric characters
  result="$(echo "$result" | sed -E 's/[^[:alnum:]]*$//')"
  
  echo "$result"
}

snake() {
  local recursive=false
  local preserve_periods=false
  local path

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        echo "$_SNAKE_HELP"
        return 0
        ;;
      -r|--recursive)
        recursive=true
        shift
        ;;
      -p|--period)
        preserve_periods=true
        shift
        ;;
      -*)
        echo "Usage: snake [-r|--recursive] [-p|--period] <path>" >&2
        return 1
        ;;
      *)
        path="$1"
        shift
        ;;
    esac
  done

  # Extract parent directory and base name
  local dirpath
  dirpath="$(dirname "$path")"
  local name
  name="$(basename "$path")"

  # Normalize name: trim whitespace
  name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Extract base and extension if file
  local base ext new_base new_ext
  if [ -f "$path" ]; then
    base="${name%.*}"
    ext="${name##*.}"
    # Trim whitespace from extension
    ext="$(echo "$ext" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # Transform extension to snake_case
    # Always replace periods in extension (the extension itself can't contain meaningful periods)
    new_ext="$(snake_transform "$ext" 0)"
  else
    base="$name"
    ext=""
    new_ext=""
  fi

  # Transform base to snake_case
  if [ "$preserve_periods" = true ]; then
    # Preserve all periods in the name
    new_base="$(snake_transform "$base" 1)"
  else
    # Replace periods with underscores (default behavior)
    new_base="$(snake_transform "$base" 0)"
  fi

  local new_name
  if [ -f "$path" ]; then
    new_name="${new_base}.${new_ext}"
  else
    new_name="${new_base}"
  fi

  local new_path="${dirpath}/${new_name}"

  # Only rename if the new name differs
  if [ "$path" != "$new_path" ]; then
    mv "$path" "$new_path"
    echo "Renamed '$path' to '$new_path'"
    path="$new_path"
  fi

  # Recurse into directories if -r flag is set
  if [ "$recursive" = true ] && [ -d "$path" ]; then
    for entry in "$path"/*; do
      [ -e "$entry" ] && snake -r "$entry"
    done
  fi
}
