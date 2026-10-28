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

# Check if target filename already exists and generate unique name
# Parameters:
#   $1: base name (path including directory)
#   $2: desired filename
#   $3: preserve_periods (1=yes, 0=no)
# Returns: unique filename via echo
generate_unique_name() {
  local dirpath="$1"
  local desired_name="$2"
  local preserve_periods="$3"
  local base_name ext counter
  local target_path="${dirpath}/${desired_name}"
  
  # If target doesn't exist, return the desired name
  if [ ! -e "$target_path" ]; then
    echo "$desired_name"
    return
  fi
  
  # Extract base name and extension
  base_name="${desired_name%.*}"
  ext="${desired_name##*.}"
  
  # If no extension (directory or file without extension)
  if [ "$base_name" = "$desired_name" ]; then
    ext=""
  else
    # Check if it's really an extension or just a period in the name
    # If the filename has only one dot and it's at the end, treat as no extension
    local dot_count
    dot_count="$(echo "$desired_name" | tr -cd '.' | wc -c)"
    if [ "$dot_count" -eq 1 ] && [ "${desired_name: -1}" = "." ]; then
      ext=""
    fi
  fi
  
  counter=1
  while [ -e "$target_path" ]; do
    if [ -n "$ext" ] && [ "$ext" != "$desired_name" ]; then
      # File with extension
      desired_name="${base_name}_${counter}.${ext}"
    else
      # Directory or file without extension
      desired_name="${desired_name}_${counter}"
    fi
    target_path="${dirpath}/${desired_name}"
    counter=$((counter + 1))
  done
  
  echo "$desired_name"
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

  # If the transformed name is the same as original, skip further processing
  local original_name="$(basename "$path")"
  if [ "$new_name" = "$original_name" ]; then
    return 0
  fi

  # Check if target already exists and add counter suffix if needed
  local final_name
  final_name="$(generate_unique_name "$dirpath" "$new_name" "$preserve_periods")"
  
  # If the final name differs from new_name, update it
  if [ "$final_name" != "$new_name" ]; then
    new_name="$final_name"
  fi

  local new_path="${dirpath}/${new_name}"

  # Resolve to absolute paths for comparison
  local abs_path abs_new_path
  abs_path="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
  abs_new_path="$(cd "$(dirname "$new_path")" 2>/dev/null && pwd)/$(basename "$new_path")"

  # Only rename if the new name differs from the original path
  if [ "$abs_path" != "$abs_new_path" ]; then
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
