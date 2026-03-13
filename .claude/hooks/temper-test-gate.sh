#!/usr/bin/env bash
# temper-test-gate.sh — Stop hook
#
# When Claude finishes a response, checks whether .temper.md files were
# modified during the session and reminds about running tests if they
# haven't been run yet.
#
# Uses the transcript to detect if temper test was run after edits.

set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Check if any .temper.md files were edited/written in recent transcript
TEMPER_EDITED=false
if grep -q '\.temper\.md' "$TRANSCRIPT_PATH" 2>/dev/null; then
  if grep -qE '"tool_name"\s*:\s*"(Edit|Write)"' "$TRANSCRIPT_PATH" 2>/dev/null; then
    # Check if the Edit/Write was on a .temper.md file
    if grep -A5 '"Edit"\|"Write"' "$TRANSCRIPT_PATH" | grep -q '\.temper\.md' 2>/dev/null; then
      TEMPER_EDITED=true
    fi
  fi
fi

if [[ "$TEMPER_EDITED" != "true" ]]; then
  exit 0
fi

# Check if temper test was run after the edits
TESTS_RAN=false
if grep -q 'temper test' "$TRANSCRIPT_PATH" 2>/dev/null; then
  TESTS_RAN=true
fi

if [[ "$TESTS_RAN" != "true" ]]; then
  cat << 'EOF'
REMINDER: .temper.md files were modified but tests haven't been run yet.

The Temper compiler is the source of truth — run tests to verify:
  temper test -b js

The compiler catches type errors, but tests verify:
  - SQL escaping produces correct output
  - SafeIdentifier validation rejects malicious inputs
  - Changeset pipelines behave correctly end-to-end
  - Edge cases (NaN, empty strings, Bobby Tables) are handled
EOF
fi

exit 0
