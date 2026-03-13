#!/usr/bin/env bash
# temper-literate-check.sh — PreToolUse hook for Edit|Write on .temper.md files
#
# Validates that content written to .temper.md files follows Temper's literate
# programming conventions and avoids known parser pitfalls.
#
# Exit 0 = allow (stdout = context for Claude)
# Exit 2 = block (stderr = feedback to Claude)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check .temper.md files
if [[ ! "$FILE_PATH" == *.temper.md ]]; then
  exit 0
fi

# Get the content being written
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" == "Write" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
else
  exit 0
fi

WARNINGS=""
ERRORS=""

# ─── CHECK 1: No backtick-fenced code blocks for Temper code ───
# Temper uses 4-space indentation, not backtick fences. Backtick fences
# are only for documentation examples (```sql, ```bash etc).
if echo "$CONTENT" | grep -qE '^\s*```temper'; then
  ERRORS="${ERRORS}
BLOCKED: Do not use backtick-fenced code blocks (\`\`\`temper) for Temper code.
Temper literate markdown uses 4+ space indentation for code blocks.
Backtick fences are only for non-Temper examples in prose (e.g. \`\`\`sql)."
fi

# ─── CHECK 2: ### headers inside class/interface bodies ───
# The parser treats ### as ending the code block. Use // comments instead.
# Heuristic: if a ### appears after an opening brace without a closing one,
# it's likely inside a class body.
if echo "$CONTENT" | grep -qE '^    .*\{' && echo "$CONTENT" | grep -qE '^### '; then
  # More precise check: look for ### between indented code lines
  IN_CODE=false
  BRACE_DEPTH=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]{4,} ]]; then
      IN_CODE=true
      OPENS=$(echo "$line" | tr -cd '{' | wc -c)
      CLOSES=$(echo "$line" | tr -cd '}' | wc -c)
      BRACE_DEPTH=$((BRACE_DEPTH + OPENS - CLOSES))
    elif [[ "$line" =~ ^###\  ]] && [[ "$BRACE_DEPTH" -gt 0 ]]; then
      ERRORS="${ERRORS}
BLOCKED: Found '### ' markdown header while inside a class/interface body (brace depth: ${BRACE_DEPTH}).
This breaks code block continuity in the Temper parser.
Use '// comment' inside code blocks instead of '### heading'."
      break
    elif [[ ! "$line" =~ ^[[:space:]]{4,} ]] && [[ ! "$line" =~ ^$ ]]; then
      if [[ "$BRACE_DEPTH" -le 0 ]]; then
        IN_CODE=false
      fi
    fi
  done <<< "$CONTENT"
fi

# ─── CHECK 3: when expressions with semicolons → Void type ───
# Semicolons inside when arms produce Void. Use if-else with explicit return.
if echo "$CONTENT" | grep -qE '^\s{4,}.*when\b.*\{' ; then
  if echo "$CONTENT" | grep -qE '^\s{8,}.*=>\s*\{[^}]*;'; then
    WARNINGS="${WARNINGS}
WARNING: Possible 'when' expression with semicolons inside arms.
In nightly 0.6.1-dev, semicolons inside when arms produce Void type.
Consider using if-else chains with explicit 'return' instead."
  fi
fi

# ─── CHECK 4: Nullable field narrowing ───
# Direct null checks on fields don't narrow. Must assign to local first.
if echo "$CONTENT" | grep -qE '^\s{4,}if\s*\(\s*[a-zA-Z_]+\.[a-zA-Z_]+\s*!=\s*null\s*\)'; then
  WARNINGS="${WARNINGS}
WARNING: Nullable field check detected (e.g. 'if (obj.field != null)').
Temper nightly 0.6.1-dev does not narrow nullable types on field access.
Assign to a local variable first:
  let lv = obj.field;
  if (lv != null) { /* lv is narrowed here */ }"
fi

# ─── CHECK 5: Test files should have tests ───
if [[ "$FILE_PATH" == *_test.temper.md ]]; then
  if ! echo "$CONTENT" | grep -q 'test('; then
    WARNINGS="${WARNINGS}
WARNING: Test file '$(basename "$FILE_PATH")' does not contain any test() calls.
Test files should contain test(\"description\") { ... } blocks."
  fi
  # Check that asserts have failure messages
  if echo "$CONTENT" | grep -qE 'assert\([^)]+\)\s*;'; then
    WARNINGS="${WARNINGS}
WARNING: Found assert() without a failure message block.
Use: assert(condition) { \"descriptive failure message: \${context}\" };
The message block helps diagnose test failures across 6+ backends."
  fi
fi

# ─── CHECK 6: Prose before code blocks (literate programming) ───
# A .temper.md file should start with a # heading and have prose.
if [[ "$TOOL_NAME" == "Write" ]]; then
  FIRST_LINE=$(echo "$CONTENT" | head -1)
  if [[ ! "$FIRST_LINE" =~ ^#\  ]]; then
    WARNINGS="${WARNINGS}
WARNING: Temper literate markdown files should start with a '# Title' heading.
The first line of a .temper.md file is the module/file title."
  fi
  # Check for code blocks without any preceding prose
  LINES_BEFORE_FIRST_CODE=$(echo "$CONTENT" | awk '/^    [^ ]/{print NR; exit}')
  if [[ -n "$LINES_BEFORE_FIRST_CODE" ]] && [[ "$LINES_BEFORE_FIRST_CODE" -le 2 ]]; then
    WARNINGS="${WARNINGS}
WARNING: Code block starts very early (line ${LINES_BEFORE_FIRST_CODE}) with little/no prose.
Literate programming: explain WHAT and WHY before showing code.
Each code section should have a prose paragraph explaining its purpose."
  fi
fi

# ─── CHECK 7: Security anti-patterns ───
# Catch direct string interpolation in SQL contexts
if echo "$CONTENT" | grep -qE 'appendSafe\(\s*"[^"]*\$\{'; then
  ERRORS="${ERRORS}
BLOCKED: Found string interpolation inside appendSafe().
appendSafe() is for hardcoded SQL keywords only. Never interpolate variables into it.
Use the typed append methods (appendString, appendInt32, etc.) or SafeIdentifier.sqlValue."
fi

# Catch raw String where SafeIdentifier should be used for SQL identifiers
if echo "$CONTENT" | grep -qE 'appendSafe\(\s*\w+\s*\)' | grep -vqE 'appendSafe\(\s*(f|fd|jc|orc|lm|np)\.' 2>/dev/null; then
  # Only warn, don't block — could be a safe local variable
  if echo "$CONTENT" | grep -qE 'appendSafe\(\s*name\s*\)'; then
    WARNINGS="${WARNINGS}
WARNING: appendSafe() called with 'name' — is this a raw String?
Table/column names must go through SafeIdentifier validation.
Use: appendSafe(safeId.sqlValue) not appendSafe(name)"
  fi
fi

# ─── REPORT ───
if [[ -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  if [[ -n "$WARNINGS" ]]; then
    echo "$WARNINGS" >&2
  fi
  exit 2
fi

if [[ -n "$WARNINGS" ]]; then
  # Warnings don't block but provide context to Claude
  echo "$WARNINGS"
  exit 0
fi

exit 0
