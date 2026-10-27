#!/usr/bin/env bash

snake() {
  local path="$1"

  # Extract parent directory and base name
  local dirpath
  dirpath="$(dirname "$path")"
  local name
  name="$(basename "$path")"

  # Normalize name: trim whitespace
  name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Extract base and extension if file
  local base ext new_base
  if [ -f "$path" ]; then
    base="${name%.*}"
    ext="${name##*.}"
  else
    base="$name"
    ext=""
  fi

  # Convert to lowercase, replace unwanted chars with underscores
  new_base="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
  new_base="${new_base// /_}"
  if [ ! -d "$path" ]; then
    new_base="${new_base//./_}"
  fi
  new_base="${new_base//,/_}"
  new_base="${new_base//!/_}"
  new_base="${new_base//|/_}"
  new_base="${new_base//·/_}"
  new_base="${new_base//-_/_}"
  new_base="${new_base//_-_/-}"
  new_base="$(echo "$new_base" | sed "s/[\'’]//g")"
  new_base="$(echo "$new_base" | tr -s '_-')" # collapse multiple _ or -
  new_base="$(echo "$new_base" | sed -E 's/[^[:alnum:]]*$//')"

  local new_name
  if [ -f "$path" ]; then
    new_name="${new_base}.${ext}"
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

  # Recurse into directories
  if [ -d "$path" ]; then
    for entry in "$path"/*; do
      [ -e "$entry" ] && snake "$entry"
    done
  fi
}
