#!/bin/sh

if ! command -v jq > /dev/null 2>&1; then
  printf "\033[0;31m[statusline] jq not found.\033[0m Install it: "
  if command -v apt-get > /dev/null 2>&1; then
    printf "sudo apt-get install jq"
  elif command -v brew > /dev/null 2>&1; then
    printf "brew install jq"
  elif command -v dnf > /dev/null 2>&1; then
    printf "sudo dnf install jq"
  elif command -v pacman > /dev/null 2>&1; then
    printf "sudo pacman -S jq"
  else
    printf "https://jqlang.org/download"
  fi
  exit 0
fi

input=$(cat)
echo "$input" > /tmp/statusline-debug.json
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')

# used_percentage and remaining_percentage are null until the first API response.
# jq outputs the literal string "null" for JSON null values without // empty.
# Use // empty to convert null -> empty string, signalling no data yet.
used=$(echo "$input" | jq -r 'if (.context_window.used_percentage | type) == "number" then .context_window.used_percentage else empty end')
remaining=$(echo "$input" | jq -r 'if (.context_window.remaining_percentage | type) == "number" then .context_window.remaining_percentage else empty end')

if [ -n "$used" ] && [ -n "$remaining" ]; then
  ctx_str=$(printf "ctx: %.0f%% used / %.0f%% left" "$used" "$remaining")
elif [ -n "$used" ]; then
  ctx_str=$(printf "ctx: %.0f%% used" "$used")
elif [ -n "$remaining" ]; then
  ctx_str=$(printf "ctx: %.0f%% left" "$remaining")
else
  ctx_str="ctx: waiting..."
fi

printf "\033[0;36m%s\033[0m  \033[0;33m%s\033[0m  \033[0;32m%s\033[0m" "$cwd" "$model" "$ctx_str"
