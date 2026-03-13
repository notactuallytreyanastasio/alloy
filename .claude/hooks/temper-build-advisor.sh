#!/usr/bin/env bash
# temper-build-advisor.sh — PostToolUse hook for Bash
#
# After temper build/test commands, analyzes output and provides
# guidance on common failures and next steps.
#
# Exit 0 = context for Claude
# Exit 2 = block (ask Claude to fix something)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only activate for temper commands
if [[ ! "$COMMAND" == *temper* ]]; then
  exit 0
fi

# Get the tool output (may be truncated)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty')
if [[ -z "$OUTPUT" ]]; then
  OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // empty')
fi

ADVICE=""

# ─── BUILD FAILURES ───
if [[ "$COMMAND" == *"temper build"* ]] || [[ "$COMMAND" == *"temper test"* ]]; then

  # Check for stale artifact issues
  if echo "$OUTPUT" | grep -qi "error\|failed\|exception"; then

    # Common: stale temper.out artifacts
    if echo "$OUTPUT" | grep -qi "cannot find\|not found\|undefined\|resolution"; then
      ADVICE="${ADVICE}
HINT: This may be a stale artifact issue. Try: rm -rf temper.out && temper build
The temper.out/ directory can contain stale compiled output from previous builds."
    fi

    # Common: ### header breaking code blocks
    if echo "$OUTPUT" | grep -qi "unexpected token\|parse error\|syntax error"; then
      ADVICE="${ADVICE}
HINT: Parse errors in .temper.md files are often caused by:
1. '### ' headers inside class bodies — use '// comment' instead
2. Missing 4-space indentation on code lines
3. Stale temper.out/ — try rm -rf temper.out first
Read the file around the error line to check for these issues."
    fi

    # Common: nullable narrowing
    if echo "$OUTPUT" | grep -qi "type.*null\|cannot call.*null\|not assignable"; then
      ADVICE="${ADVICE}
HINT: Temper nightly 0.6.1-dev does not narrow nullable types on field access.
Assign nullable fields to local variables before null-checking:
  let lv = obj.field;
  if (lv != null) { /* use lv here */ }"
    fi

    # Common: when expression Void type
    if echo "$OUTPUT" | grep -qi "void.*not assignable\|expected.*got.*void"; then
      ADVICE="${ADVICE}
HINT: 'when' expressions with semicolons inside arms produce Void type.
Use if-else chains with explicit 'return' instead of 'when' for value-producing expressions."
    fi

    # Common: overload annotation missing
    if echo "$OUTPUT" | grep -qi "overload\|duplicate\|already defined"; then
      ADVICE="${ADVICE}
HINT: Method overloading requires @overload(\"methodName\") annotation on each overload.
Example:
    @overload(\"append\")
    public appendString(value: String): Void { ... }"
    fi

    # Common: cross-module import failure
    if echo "$OUTPUT" | grep -qi "import.*not found\|cannot resolve\|unknown symbol"; then
      ADVICE="${ADVICE}
HINT: Cross-module imports between sibling directories fail because @I stages run in parallel.
All source files should be flat in src/ — files in the same directory share scope automatically.
No explicit imports are needed between files in the same module."
    fi
  fi

  # ─── TEST RESULTS ───
  if [[ "$COMMAND" == *"temper test"* ]]; then
    # Extract pass/fail counts if present
    if echo "$OUTPUT" | grep -qiE '[0-9]+ passing'; then
      PASSING=$(echo "$OUTPUT" | grep -oiE '[0-9]+ passing' | head -1)
      ADVICE="${ADVICE}
Tests: ${PASSING}"
    fi
    if echo "$OUTPUT" | grep -qiE '[0-9]+ failing'; then
      FAILING=$(echo "$OUTPUT" | grep -oiE '[0-9]+ failing' | head -1)
      ADVICE="${ADVICE}
Tests: ${FAILING}
IMPORTANT: Fix failing tests before proceeding. The compiler output is the source of truth."
    fi
  fi
fi

# ─── BUILD SUCCESS REMINDER ───
if [[ "$COMMAND" == *"temper build"* ]] && ! echo "$OUTPUT" | grep -qi "error\|failed"; then
  if [[ "$COMMAND" != *"temper test"* ]]; then
    ADVICE="${ADVICE}
Build succeeded. Remember to also run tests: temper test -b js
The compiler catching errors is good, but tests verify behavior across backends."
  fi
fi

if [[ -n "$ADVICE" ]]; then
  echo "$ADVICE"
fi

exit 0
