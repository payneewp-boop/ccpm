#!/bin/bash
# Tests for the helper scripts under skill/ccpm/references/scripts. Plain bash,
# nothing to install:   bash tests/scripts.test.sh
# Each case is a defect from a Codex code review (2026-10-20), reproduced first.

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skill/ccpm/references/scripts" && pwd)"
pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS  $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL  $1"; [ -n "$2" ] && echo "      $2"; }
check() { # name, condition-exit-code, detail
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi
}

project() { # builds a throwaway project in $P: one closed task, a chain after it
  P=$(mktemp -d); cd "$P" || exit 1
  mkdir -p .claude/epics/e .claude/prds .claude/rules
  printf -- '---\nname: e\nstatus: in-progress\nprogress: 0%%\n---\n# Epic\n' > .claude/epics/e/epic.md
  task() { printf -- '---\nname: %s\nstatus: %s\ndepends_on: [%s]\nparallel: false\n---\n# t\n' "$2" "$3" "$4" > ".claude/epics/e/$1.md"; }
  task 001 "First" closed ""
  task 002 "Second" open "001"
  task 003 "Third" open "002"
}

# --- dependency state ---------------------------------------------------------
project
out=$(bash "$SCRIPTS/next.sh"); echo "$out" | grep -q "#002 - Second"
check "next: a task whose only dependency is closed is ready" $? "$out"
echo "$out" | grep -q "#003"; [ $? -ne 0 ]
check "next: a task behind an open dependency is not ready" $? "$out"

out=$(bash "$SCRIPTS/blocked.sh"); echo "$out" | grep -q "Task #003"
check "blocked: lists the task waiting on an open dependency" $? "$out"
echo "$out" | grep -q "Waiting for: #002"
check "blocked: names the dependency that is still open" $? "$out"
echo "$out" | grep -q "Task #002"; [ $? -ne 0 ]
check "blocked: does not list a task whose dependencies are all closed" $? "$out"

out=$(bash "$SCRIPTS/epic-status.sh" e); echo "$out" | grep -q "Available: 1" && echo "$out" | grep -q "Blocked: 1"
check "epic-status: counts 1 available and 1 blocked" $? "$out"

out=$(bash "$SCRIPTS/standup.sh"); echo "$out" | grep -q "#002 - Second"
check "standup: offers the task whose dependency is closed" $? "$out"

# a dependency nobody can find is not shown to be done
printf -- '---\nname: Orphan\nstatus: open\ndepends_on: [999]\n---\n' > .claude/epics/e/004.md
out=$(bash "$SCRIPTS/next.sh"); echo "$out" | grep -q "#004"; [ $? -ne 0 ]
check "next: a dependency with no task file keeps its task blocked" $? "$out"

# --- validate.sh --------------------------------------------------------------
out=$(bash "$SCRIPTS/validate.sh"); rc=$?
check "validate: a healthy project exits 0" $rc "rc=$rc"

rm -f .claude/epics/e/004.md; printf '# Notes\n\n---\n\njust a horizontal rule\n' > .claude/prds/rule.md
out=$(bash "$SCRIPTS/validate.sh"); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "Missing frontmatter: rule.md"
check "validate: a --- in the body is not frontmatter, and the run fails" $? "rc=$rc"
rm -f .claude/prds/rule.md

printf -- '---\nname: Dangling\nstatus: open\ndepends_on: [777]\n---\n' > .claude/epics/e/005.md
out=$(bash "$SCRIPTS/validate.sh"); rc=$?
check "validate: a warning alone does not fail the run" $rc "rc=$rc"
cd /; rm -rf "$P"

P=$(mktemp -d); cd "$P"
bash "$SCRIPTS/validate.sh" >/dev/null; rc=$?
[ $rc -ne 0 ]; check "validate: a missing .claude directory exits nonzero" $? "rc=$rc"
cd /; rm -rf "$P"

# --- frontmatter stripping ------------------------------------------------------
. "$SCRIPTS/_lib.sh"
f=$(mktemp); printf -- '---\nname: x\n---\n# Body\n\ntext\n---\nafter the rule\n' > "$f"
[ "$(strip_frontmatter "$f")" = "$(printf '# Body\n\ntext\n---\nafter the rule')" ]
check "strip_frontmatter: keeps the body, including a later ---" $? "$(strip_frontmatter "$f")"
printf -- '---\nname: x\n---\n' > "$f"; [ -z "$(strip_frontmatter "$f")" ]
check "strip_frontmatter: a file that is only frontmatter has an empty body" $?
printf '# No frontmatter\n---\nstill here\n' > "$f"
[ "$(strip_frontmatter "$f")" = "$(printf '# No frontmatter\n---\nstill here')" ]
check "strip_frontmatter: leaves a file with no frontmatter alone" $?
rm -f "$f"

# --- init.sh ------------------------------------------------------------------
P=$(mktemp -d); cd "$P"; mkdir bin
cat > bin/gh <<'GH'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "extension list") echo "yahsan2/gh-sub-issue"; exit 0 ;;
  "--version "*) echo "gh version 0"; exit 0 ;;
esac
[ "$1" = "--version" ] && { echo "gh version 0"; exit 0; }
exit 0
GH
chmod +x bin/gh
mkdir proj; cd proj; touch .claude          # a file where the directory must go
out=$(PATH="$P/bin:$PATH" bash "$SCRIPTS/init.sh" 2>&1); rc=$?
[ $rc -ne 0 ] && ! echo "$out" | grep -q "Initialization Complete"
check "init: failing to create .claude stops with an error, not 'Complete'" $? "rc=$rc"
cd "$P"; rm -rf proj; mkdir proj; cd proj
out=$(PATH="$P/bin:$PATH" bash "$SCRIPTS/init.sh" 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q "Initialization Complete"
check "init: a clean run still completes" $? "rc=$rc"
cd /; rm -rf "$P"

echo ""; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
