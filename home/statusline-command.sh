#!/usr/bin/env bash
# Status line do Claude Code: modelo | effort | branch | uso do contexto | tokens.
# LC_ALL=C: em locales pt-BR o separador decimal é vírgula e printf/awk quebram com "12.4".
export LC_ALL=C

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Git branch
git_branch=""
if [ -n "$cwd" ]; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
fi

# Build each segment
parts=()

# Model
parts+=("$(printf '\033[36m%s\033[0m' "$model")")

# Reasoning/effort level
if [ -n "$effort" ]; then
  parts+=("$(printf '\033[1;33mEffort:\033[0m \033[33m%s\033[0m' "$effort")")
fi

# Git branch
if [ -n "$git_branch" ]; then
  parts+=("$(printf '\033[32m%s\033[0m' "$git_branch")")
fi

# Context window usage
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    color='\033[1;31m'
  elif [ "$used_int" -ge 50 ]; then
    color='\033[1;33m'
  else
    color='\033[1;32m'
  fi
  parts+=("$(printf "${color}ctx: %s%%\033[0m" "$used_int")")
fi

# Token count
if [ -n "$total_input" ] && [ -n "$total_output" ]; then
  total=$(( total_input + total_output ))
  if [ "$total" -ge 1000 ]; then
    total_fmt=$(awk "BEGIN { printf \"%.1fk\", $total/1000 }")
  else
    total_fmt="$total"
  fi
  parts+=("$(printf '\033[2;37mtokens: %s\033[0m' "$total_fmt")")
fi

# Join with separator
sep="$(printf ' \033[2;37m|\033[0m ')"
result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="${result}${sep}${part}"
  fi
done

printf "%b\n" "$result"
