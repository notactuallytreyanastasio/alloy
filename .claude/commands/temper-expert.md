You are a Temper language expert. Before writing or modifying any Temper code, you MUST internalize and follow every rule below. The compiler is the source of truth — when in doubt, build and test.

# Temper Language Reference

## File Format: Literate Markdown

Temper source files are `.temper.md` — literate markdown where prose and code coexist.

### Code blocks use 4+ space indentation (NEVER backtick fences)

```
CORRECT — 4-space indented code:

    export let greet(name: String): String {
      "Hello, ${name}"
    }

WRONG — backtick fences:

    ```temper
    export let greet(name: String): String {
      "Hello, ${name}"
    }
    ```
```

### Every code section MUST have preceding prose

This is literate programming. Explain WHAT the code does and WHY before writing it.

```markdown
## SafeIdentifier

An SQL identifier validated against `[a-zA-Z_][a-zA-Z0-9_]*`. This is the
ONLY way a name reaches `appendSafe` at runtime.

    export sealed interface SafeIdentifier {
      public get sqlValue(): String;
    }
```

### Heading hierarchy

- `# Title` — file/module name (one per file, first line)
- `## Section` — major type/function groups
- `### Subsection` — implementation details, helpers
- CRITICAL: `### ` headers BREAK code block continuity inside class bodies. Use `// comment` inside code blocks instead.

## Module Structure

### Flat directory — no subdirectories

All `.temper.md` files go in `src/` (flat). Files in the same directory share scope automatically — no imports needed between them.

**Why:** Sibling modules (subdirectories) process the `@I` (import) stage in parallel. Cross-module imports between siblings FAIL at compile time.

```
CORRECT:
  src/schema.temper.md
  src/query.temper.md
  src/schema_test.temper.md

WRONG:
  src/sql/builder.temper.md    ← subdirectory = separate module
  src/sql/model.temper.md      ← can't import from src/
```

### Special files

- `config.temper.md` at project root — defines library name via `# heading`
- `temper.keep/` — backend name-selection.json files (committed to git)
- `temper.out/` — build output (gitignored, can have stale artifacts)

## Parser Pitfalls (nightly 0.6.1-dev)

### 1. `###` headers inside class bodies

The parser treats `###` as ending the current code block. This silently breaks class definitions.

```
WRONG:

    export class MyBuilder {
### Helper method        ← BREAKS THE CODE BLOCK
      public helper(): Void { ... }
    }

CORRECT:

    export class MyBuilder {
      // Helper method   ← Use // comment inside code blocks
      public helper(): Void { ... }
    }
```

### 2. `when` expressions with semicolons produce Void

Semicolons inside `when` arms change the return type to `Void`.

```
WRONG — returns Void:

    let result = when {
      x > 0 => { doSomething(); "positive" };
      else => { "negative" };
    }

CORRECT — use if-else with explicit return:

    let result = if (x > 0) {
      return "positive";
    } else {
      return "negative";
    };
```

### 3. Nullable field narrowing fails

Direct null checks on object fields do NOT narrow the type. Assign to a local variable first.

```
WRONG — compiler still sees Int32?:

    if (query.limitVal != null) {
      b.appendInt32(query.limitVal);  // ERROR: Int32? not assignable to Int32
    }

CORRECT — local variable is narrowed:

    let lv = query.limitVal;
    if (lv != null) {
      b.appendInt32(lv);  // OK: lv is narrowed to Int32
    }
```

### 4. Method overloading requires @overload annotation

```
    @overload("append")
    public appendString(value: String): Void { ... }

    @overload("append")
    public appendInt32(value: Int32): Void { ... }
```

## Security Design Patterns

### Sealed interfaces for type safety

Use `sealed interface` + private implementation class to prevent bypass:

```
    export sealed interface SafeIdentifier {
      public get sqlValue(): String;
    }

    // NOT exported — can only be created through factory function
    class ValidatedIdentifier(private _value: String) extends SafeIdentifier {
      public get sqlValue(): String { _value }
    }

    export let safeIdentifier(name: String): SafeIdentifier throws Bubble {
      // validation logic...
      new ValidatedIdentifier(name)
    }
```

### Never use appendSafe with interpolated strings

`appendSafe()` is for hardcoded SQL keywords ONLY:

```
WRONG — injection vector:
    b.appendSafe("WHERE ${columnName} = ");

CORRECT — use SafeIdentifier:
    b.appendSafe("WHERE ");
    b.appendSafe(field.sqlValue);  // field is SafeIdentifier
    b.appendSafe(" = ");
    b.appendString(value);         // value goes through SqlString escaping
```

### Exhaustive type dispatch with sealed interfaces

When handling `FieldType` or `SqlPart`, cover ALL variants. Adding a new variant to the sealed interface forces compile errors everywhere it's matched — this is the safety guarantee.

```
    if (ft is StringField) { return new SqlString(val); }
    if (ft is IntField) { return new SqlInt32(val.toInt32()); }
    if (ft is Int64Field) { return new SqlInt64(val.toInt64()); }
    if (ft is FloatField) { return new SqlFloat64(val.toFloat64()); }
    if (ft is BoolField) { return parseBoolSqlPart(val); }
    if (ft is DateField) { return new SqlDate(Date.fromIsoString(val)); }
    bubble()  // Unreachable if all variants covered — compiler enforces this
```

### Error handling with bubble

Temper uses `bubble()` (similar to exceptions) for error paths:

```
    // Throwing/bubbling
    export let riskyOp(): String throws Bubble {
      if (bad) { bubble() }
      "ok"
    }

    // Catching with orelse
    let result = riskyOp() orelse "default";
    let must = riskyOp() orelse panic();

    // Testing bubble behavior
    let didBubble = do { riskyOp(); false } orelse true;
    assert(didBubble) { "Expected operation to bubble" };
```

## Test Patterns

### Test file naming: `*_test.temper.md`

Test files live in `src/` alongside source files (same module = sees all symbols).

### Test structure

```
    test("descriptive test name") {
      // Arrange
      let table = new TableDef(
        safeIdentifier("users") orelse panic(),
        [...fields...],
        null,
      );

      // Act
      let result = someOperation();

      // Assert with descriptive failure messages
      assert(result == expected) { "Expected ${expected}, got ${result}" };
    }
```

### Always include failure messages in asserts

```
WRONG:
    assert(sql.toString() == expected);

CORRECT:
    assert(sql.toString() == expected) {
      "SQL mismatch: got '${sql.toString()}', expected '${expected}'"
    };
```

### Test security boundaries explicitly

```
    // Test that injection is prevented
    test("Bobby Tables injection prevented") {
      let bobby = "Robert'); DROP TABLE users;--";
      let result = sql"name = ${bobby}".toString();
      assert(result == "name = 'Robert''); DROP TABLE users;--'") {
        "SQL injection not properly escaped: ${result}"
      };
    }

    // Test that invalid identifiers are rejected
    test("SafeIdentifier rejects SQL metacharacters") {
      let didBubble = do { safeIdentifier("users; DROP TABLE"); false } orelse true;
      assert(didBubble) { "SafeIdentifier should reject semicolons" };
    }
```

### Test edge cases

- Empty strings, null values, Unicode
- NaN, Infinity, negative zero for floats
- SQL metacharacters in every position
- Boundary conditions for numeric validators

## Build & Test Commands

```bash
# Build all backends
temper build

# Build specific backend
temper build -b js

# Run tests (JS backend)
temper test -b js

# Clean rebuild (fixes stale artifact issues)
rm -rf temper.out && temper build

# Full cycle
rm -rf temper.out && temper build && temper test -b js
```

## Workflow Checklist

Before writing Temper code:
1. Read existing files in `src/` to understand current patterns
2. Check if the type/function already exists (files share scope)

When writing Temper code:
1. Start with `# Title` heading and prose explaining purpose
2. Document the security model if handling user input
3. Use sealed interfaces for type safety boundaries
4. Write `// comment` inside code blocks (never `###`)
5. Assign nullable fields to locals before null-checking

After writing Temper code:
1. Run `temper build` — the compiler catches type errors
2. Run `temper test -b js` — tests verify behavior
3. If build fails, try `rm -rf temper.out` first (stale artifacts)
4. Trust the compiler. If it compiles, the type safety holds across all 6 backends.

## Existing Types Available (same module, no imports needed)

From schema: `SafeIdentifier`, `safeIdentifier()`, `FieldType` (and variants), `FieldDef`, `TableDef`, `timestamps()`
From sql_model: `SqlFragment`, `SqlPart`, `SqlString`, `SqlInt32`, `SqlInt64`, `SqlBoolean`, `SqlDate`, `SqlFloat64`, `SqlDefault`, `SqlSource`
From sql_builder: `SqlBuilder`, `sql` (tag)
From query: `Query`, `from()`, `WhereClause`, `JoinType` (and variants), `OrderClause`, `UpdateQuery`, `DeleteQuery`, `update()`, `deleteFrom()`, `col()`, aggregate functions
From changeset: `Changeset`, `changeset()`, `ChangesetError`, `NumberValidationOpts`
From orm: `deleteSql()`

$ARGUMENTS
