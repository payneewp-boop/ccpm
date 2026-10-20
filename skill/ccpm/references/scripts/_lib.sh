#!/bin/bash
# Shared helpers for the status scripts. Sourced, not run:
#   . "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Prints, one per line, the dependencies of a task file that are not finished.
# A dependency counts as finished only when its own file says closed or
# completed. One whose file cannot be found is reported too: nothing shows it
# is done. A task is ready when this prints nothing.
#
# Reading only whether `depends_on` is empty left every task with a closed
# dependency blocked forever, so next, blocked, standup and epic-status all
# disagreed with the task files.
open_deps() {
  local task_file=$1 epic_dir deps dep dep_file dep_status
  epic_dir=$(dirname "$task_file")
  deps=$(grep -m1 '^depends_on:' "$task_file" \
    | sed 's/^depends_on:[[:space:]]*//; s/^\[//; s/\]//; s/,/ /g; s/"//g; s/'"'"'//g')
  for dep in $deps; do
    dep_file="$epic_dir/$dep.md"
    if [ -f "$dep_file" ]; then
      dep_status=$(grep -m1 '^status:' "$dep_file" | sed 's/^status:[[:space:]]*//; s/[[:space:]]*$//')
      case "$dep_status" in
        closed|completed) ;;
        *) echo "$dep" ;;
      esac
    else
      echo "$dep"
    fi
  done
}

# True when the file opens with a --- line and has a closing --- line after it.
has_frontmatter() {
  [ "$(head -n 1 "$1")" = "---" ] && tail -n +2 "$1" | grep -q '^---[[:space:]]*$'
}

# Writes a file's body (everything after its leading frontmatter block) to stdout.
# Only a --- on line 1 opens frontmatter, and only the first --- after it closes
# it, so a horizontal rule later in the body is kept.
strip_frontmatter() {
  awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$1"
}
