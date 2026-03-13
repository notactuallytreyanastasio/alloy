# Generic Temper ORM

A type-safe, security-focused ORM written in [Temper](https://github.com/temperlang/temper) — a language that compiles to **6 backend targets** from a single source. This repo contains the ORM source, a CI pipeline that compiles and distributes the ORM to per-language library repos, and 6 demo todo-list applications (one per target language) that showcase the ORM in action.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [The ORM](#the-orm)
  - [Security Model](#security-model)
  - [Core API](#core-api)
  - [Source Files](#source-files)
- [Compilation Targets](#compilation-targets)
- [Demo Applications](#demo-applications)
- [CI Pipeline](#ci-pipeline)
  - [Build Stage](#build-stage)
  - [Publish Stage](#publish-stage)
  - [App Vendor Update](#app-vendor-update)
- [Repository Map](#repository-map)
- [Building Locally](#building-locally)
- [Running the Demo Apps](#running-the-demo-apps)
- [Project Structure](#project-structure)

---

## Architecture Overview

```
                    ┌────────────────────────┐
                    │   generic_orm (Temper)  │
                    │   Single source tree    │
                    └───────────┬────────────┘
                                │ temper build
                    ┌───────────▼────────────┐
                    │      temper.out/        │
                    │  js/ py/ rust/ java/    │
                    │  lua/ csharp/           │
                    └───────────┬────────────┘
                                │ CI publish
        ┌───────┬───────┬───────┼───────┬───────┐
        ▼       ▼       ▼       ▼       ▼       ▼
   orm-js   orm-py  orm-rust orm-java orm-lua orm-csharp
   (lib)    (lib)   (lib)    (lib)    (lib)   (lib)
        │       │       │       │       │       │
        │  push triggers notify-app workflow    │
        ▼       ▼       ▼       ▼       ▼       ▼
   js-app  py-app  rust-app java-app lua-app csharp-app
   (demo)  (demo)  (demo)   (demo)  (demo)  (demo)
```

A push to `main` in this repo triggers CI, which:
1. Builds the Temper compiler from source
2. Compiles the ORM for all 6 backends
3. Runs the test suite (JS backend)
4. Pushes compiled output to 6 per-language **lib repos**
5. Each lib repo's push triggers a **notify-app workflow** that vendors the updated ORM into its corresponding **app repo**

---

## The ORM

### Security Model

The ORM is built on a defense-in-depth approach to SQL injection prevention, using Temper's type system to enforce safety at compile time:

- **`SafeIdentifier`** — Table and column names must pass through [`safeIdentifier()`](src/schema.temper.md), which validates against `[a-zA-Z_][a-zA-Z0-9_]*`. The `ValidatedIdentifier` implementation class is *not exported*, so external code cannot construct one without validation. This is the only path to `appendSafe` at runtime.

- **`SqlBuilder`** — The [query builder](src/sql_builder.temper.md) separates SQL structure (`appendSafe`) from user data (`appendString`, `appendInt32`, etc.). User values are typed as `SqlPart` instances that handle escaping per-type. `SqlString` escapes single quotes; `SqlInt32`/`SqlInt64` render bare integers; `SqlBoolean` emits `TRUE`/`FALSE` literals.

- **`Changeset`** — The [changeset pipeline](src/changeset.temper.md) follows Ecto's cast-then-validate pattern. `Changeset` is a *sealed interface* — `ChangesetImpl` is not exported, so the only construction path is through the `changeset()` factory. Raw `params` are never exposed; only whitelisted `changes` are readable. `cast()` requires `List<SafeIdentifier>` for field whitelisting. `toInsertSql()` independently enforces non-nullable fields. Type dispatch uses exhaustive `when` on the sealed `FieldType` union.

- **`Query`** — The [query builder](src/query.temper.md) requires `SafeIdentifier` for table names, selected fields, ORDER BY clauses, and JOIN table names. WHERE and ON conditions accept only `SqlFragment` (never raw strings). `safeToSql(defaultLimit)` provides CWE-400 protection by enforcing a result set size limit. JOIN type keywords are hardcoded from a sealed `JoinType` interface. The `col()` helper produces qualified column references (`table.column`) from two `SafeIdentifier` values.

### Core API

```
┌─────────────────────────────────────────────────────────┐
│  safeIdentifier("users")  →  SafeIdentifier             │
│                                                         │
│  TableDef(safeId, [FieldDef(safeId, StringField, false)])│
│                                                         │
│  from(safeId)                                           │
│    .where(sqlFragment)                                  │
│    .orderBy(safeId, ascending)                          │
│    .limit(n)                                            │
│    .toSql()  →  SqlFragment                             │
│                                                         │
│  changeset(tableDef, paramsMap)                          │
│    .cast(allowedFields)                                 │
│    .validateRequired(fields)                            │
│    .toInsertSql()  →  SqlFragment                       │
│    .toUpdateSql(id) → SqlFragment                       │
│                                                         │
│  deleteSql(tableDef, id)  →  SqlFragment                │
│                                                         │
│  sqlFragment.toString()  →  String  (rendered SQL)       │
└─────────────────────────────────────────────────────────┘
```

**Field types:** `StringField`, `IntField`, `Int64Field`, `FloatField`, `BoolField`, `DateField`

**Changeset validations:** `validateRequired`, `validateLength`, `validateInt`, `validateInt64`, `validateFloat`, `validateBool`

### Source Files

All source lives in [`src/`](src/) as Temper literate markdown (`.temper.md`):

| File | Purpose |
|------|---------|
| [`schema.temper.md`](src/schema.temper.md) | `SafeIdentifier`, `FieldType`, `FieldDef`, `TableDef` |
| [`query.temper.md`](src/query.temper.md) | `Query`, `from()`, `OrderClause`, `JoinType`, `JoinClause`, `col()` |
| [`changeset.temper.md`](src/changeset.temper.md) | `Changeset`, `changeset()`, cast/validate/SQL pipeline |
| [`orm.temper.md`](src/orm.temper.md) | `deleteSql()` top-level helper |
| [`sql_builder.temper.md`](src/sql_builder.temper.md) | `SqlBuilder`, `sql` tag |
| [`sql_model.temper.md`](src/sql_model.temper.md) | `SqlFragment`, `SqlPart`, `SqlString`, `SqlInt32`, etc. |
| [`sql_imports.temper.md`](src/sql_imports.temper.md) | Re-exports from vendored `secure-composition` |
| [`schema_test.temper.md`](src/schema_test.temper.md) | Schema tests |
| [`query_test.temper.md`](src/query_test.temper.md) | Query builder tests |
| [`changeset_test.temper.md`](src/changeset_test.temper.md) | Changeset tests |
| [`sql_tests.temper.md`](src/sql_tests.temper.md) | SQL builder/model tests |

The library name is defined in [`config.temper.md`](config.temper.md).

---

## Compilation Targets

The Temper compiler produces idiomatic output for each backend:

| Target | Output | Runtime |
|--------|--------|---------|
| **JavaScript** | ES modules | `@temperlang/core` |
| **Python** | Python 3 modules | `temper_core` |
| **Rust** | Cargo crate | `temper-core` |
| **Java** | Java source files | `temper-core` JAR |
| **Lua** | Lua modules | `temper` runtime |
| **C#** | .NET source files | `TemperLang.Core` |

Build output lands in `temper.out/<lang>/` with three subdirectories: `orm/` (the ORM itself), `std/` (Temper standard library), and `temper-core/` (Temper runtime).

---

## Demo Applications

Each demo is a **todo list manager** with the same retro Mac System 6 + Windows 95 hybrid UI theme. All apps support:

- Create, rename, and delete todo lists
- Create, edit, toggle, and delete todo items within lists
- Inline editing with confirmation dialogs
- Completion tracking in the status bar

| Language | Framework | Port | App Repo | Source |
|----------|-----------|------|----------|--------|
| **JavaScript** | Express + EJS + better-sqlite3 | 5006 | [`generic-orm-js-app`](https://github.com/notactuallytreyanastasio/generic-orm-js-app) | [`apps/js/`](apps/js/) |
| **Python** | Flask + sqlite3 | 5001 | [`generic-orm-py-app`](https://github.com/notactuallytreyanastasio/generic-orm-py-app) | [`apps/py/`](apps/py/) |
| **Rust** | Axum + rusqlite + askama | 5003 | [`generic-orm-rust-app`](https://github.com/notactuallytreyanastasio/generic-orm-rust-app) | [`apps/rust/`](apps/rust/) |
| **Java** | Spring Boot + SQLite JDBC + Thymeleaf | 5004 | [`generic-orm-java-app`](https://github.com/notactuallytreyanastasio/generic-orm-java-app) | [`apps/java/`](apps/java/) |
| **Lua** | Raw socket HTTP + lsqlite3 | 5005 | [`generic-orm-lua-app`](https://github.com/notactuallytreyanastasio/generic-orm-lua-app) | [`apps/lua/`](apps/lua/) |
| **C#** | ASP.NET Core Razor Pages + SQLite | 5002 | [`generic-orm-csharp-app`](https://github.com/notactuallytreyanastasio/generic-orm-csharp-app) | [`apps/csharp/`](apps/csharp/) |

### ORM API Usage Across Languages

Each app adapts the same ORM API to its language's idioms. Here's how a SELECT query looks in each:

**JavaScript:**
```javascript
import { from, safeIdentifier, SqlBuilder } from 'orm';
const q = from(safeIdentifier("todos"))
  .where(whereFragment)
  .orderBy(safeIdentifier("created_at"), true)
  .toSql().toString();
```

**Python:**
```python
from orm.src import from_, safe_identifier, SqlBuilder
q = (from_(safe_identifier("todos"))
     .where(where_fragment)
     .order_by(safe_identifier("created_at"), True)
     .to_sql().to_string())
```

**Rust:**
```rust
use orm::src::{from, safe_identifier, SqlBuilder};
let q = from(safe_identifier("todos")?)
    .where_(where_fragment)
    .order_by(safe_identifier("created_at")?, true)
    .to_sql().to_string();
```

**Java:**
```java
import orm.src.SrcGlobal;
String q = SrcGlobal.from(SrcGlobal.safeIdentifier("todos"))
    .where(whereFragment)
    .orderBy(SrcGlobal.safeIdentifier("created_at"), true)
    .toSql().toString();
```

**Lua:**
```lua
local orm = require("orm")
local q = orm.from(orm.safeIdentifier("todos"))
    :where(where_fragment)
    :orderBy(orm.safeIdentifier("created_at"), true)
    :toSql():toString()
```

**C#:**
```csharp
using Orm.Src;
var q = SrcGlobal.From(SrcGlobal.SafeIdentifier("todos"))
    .Where(whereFragment)
    .OrderBy(SrcGlobal.SafeIdentifier("created_at"), true)
    .ToSql().ToString();
```

---

## CI Pipeline

The pipeline is defined in [`.github/workflows/publish-libs.yml`](.github/workflows/publish-libs.yml).

### Build Stage

1. **Checkout** this repository
2. **Set up JDK 21** (Temurin)
3. **Clone and build** the [Temper compiler](https://github.com/temperlang/temper) from `main`
4. **Run `temper build`** — compiles the ORM for all 6 backends into `temper.out/`
5. **Run `temper test -b js`** — executes the full test suite against the JS backend
6. **Upload artifacts** — `temper.out/` and the [notify-app template](.github/notify-app-template.yml)

### Publish Stage

A **matrix of 6 jobs** (one per language) runs in parallel after the build:

| Matrix Entry | Lib Repo | App Repo | Vendor Path |
|-------------|----------|----------|-------------|
| `js` | [`generic-orm-js`](https://github.com/notactuallytreyanastasio/generic-orm-js) | [`generic-orm-js-app`](https://github.com/notactuallytreyanastasio/generic-orm-js-app) | `vendor` |
| `py` | [`generic-orm-py`](https://github.com/notactuallytreyanastasio/generic-orm-py) | [`generic-orm-py-app`](https://github.com/notactuallytreyanastasio/generic-orm-py-app) | `vendor` |
| `rust` | [`generic-orm-rust`](https://github.com/notactuallytreyanastasio/generic-orm-rust) | [`generic-orm-rust-app`](https://github.com/notactuallytreyanastasio/generic-orm-rust-app) | `vendor` |
| `java` | [`generic-orm-java`](https://github.com/notactuallytreyanastasio/generic-orm-java) | [`generic-orm-java-app`](https://github.com/notactuallytreyanastasio/generic-orm-java-app) | `vendor` |
| `lua` | [`generic-orm-lua`](https://github.com/notactuallytreyanastasio/generic-orm-lua) | [`generic-orm-lua-app`](https://github.com/notactuallytreyanastasio/generic-orm-lua-app) | `vendor` |
| `csharp` | [`generic-orm-csharp`](https://github.com/notactuallytreyanastasio/generic-orm-csharp) | [`generic-orm-csharp-app`](https://github.com/notactuallytreyanastasio/generic-orm-csharp-app) | `TodoApp/vendor` |

Each publish job:
1. Downloads the `temper.out/` artifact
2. Configures SSH with a per-language deploy key (`DEPLOY_KEY_JS`, `DEPLOY_KEY_PY`, etc.)
3. Clones the target lib repo
4. Replaces all content with the new build output (orm/ + std/ + temper-core/)
5. Writes the [notify-app workflow](.github/notify-app-template.yml) into `.github/workflows/`
6. Commits and pushes

### App Vendor Update

When a lib repo receives a push (from the publish stage above), its [`notify-app.yml`](.github/notify-app-template.yml) workflow:
1. Clones the corresponding app repo
2. Removes old `vendor/orm`, `vendor/std`, `vendor/temper-core`
3. Copies the new compiled output into `vendor/`
4. Commits and pushes

This creates a fully automated cascade: **ORM source change** -> **build** -> **lib repos** -> **app repos**.

---

## Repository Map

### This Repository (Source)

| Repo | Description |
|------|-------------|
| [`generic_orm`](https://github.com/notactuallytreyanastasio/generic_orm) | Temper ORM source, CI pipeline, app source code |

### Library Repos (Compiled Output)

| Repo | Language | Contents |
|------|----------|----------|
| [`generic-orm-js`](https://github.com/notactuallytreyanastasio/generic-orm-js) | JavaScript | ES modules |
| [`generic-orm-py`](https://github.com/notactuallytreyanastasio/generic-orm-py) | Python | Python 3 modules |
| [`generic-orm-rust`](https://github.com/notactuallytreyanastasio/generic-orm-rust) | Rust | Cargo crate |
| [`generic-orm-java`](https://github.com/notactuallytreyanastasio/generic-orm-java) | Java | Java source |
| [`generic-orm-lua`](https://github.com/notactuallytreyanastasio/generic-orm-lua) | Lua | Lua modules |
| [`generic-orm-csharp`](https://github.com/notactuallytreyanastasio/generic-orm-csharp) | C# | .NET source |

### Application Repos (Demo Apps)

| Repo | Language | Framework |
|------|----------|-----------|
| [`generic-orm-js-app`](https://github.com/notactuallytreyanastasio/generic-orm-js-app) | JavaScript | Express + EJS |
| [`generic-orm-py-app`](https://github.com/notactuallytreyanastasio/generic-orm-py-app) | Python | Flask |
| [`generic-orm-rust-app`](https://github.com/notactuallytreyanastasio/generic-orm-rust-app) | Rust | Axum + askama |
| [`generic-orm-java-app`](https://github.com/notactuallytreyanastasio/generic-orm-java-app) | Java | Spring Boot |
| [`generic-orm-lua-app`](https://github.com/notactuallytreyanastasio/generic-orm-lua-app) | Lua | Raw socket HTTP |
| [`generic-orm-csharp-app`](https://github.com/notactuallytreyanastasio/generic-orm-csharp-app) | C# | ASP.NET Core Razor |

---

## SQL Security Analysis

The entire point of this project is demonstrating type-safe SQL generation across 6 languages from a single source. Here's how the ORM prevents SQL injection and where the boundaries are.

### Defense Layers

**Layer 1: `SafeIdentifier` (CWE-89 — table/column names)**

Table and column names must pass through [`safeIdentifier()`](src/schema.temper.md), which validates against `[a-zA-Z_][a-zA-Z0-9_]*`. The internal `ValidatedIdentifier` class is **not exported** — external code cannot construct one without validation. This is the only path to `appendSafe` at runtime, closing off identifier-based injection entirely.

```
safeIdentifier("users")       → ValidatedIdentifier ✓
safeIdentifier("users; DROP") → bubble (rejected)
safeIdentifier("table--name") → bubble (rejected)
```

**Layer 2: Typed `SqlPart` hierarchy (CWE-89 — value escaping)**

User values never touch `appendSafe`. Each type gets its own [`SqlPart`](src/sql_model.temper.md) subclass with type-appropriate rendering:

| Type | Rendering | Example |
|------|-----------|---------|
| `SqlString` | Quote-wraps with `'` escaping (`'` → `''`) | `'O''Brien'` |
| `SqlInt32` / `SqlInt64` | Bare integer via `.toString()` | `42` |
| `SqlBoolean` | Literal `TRUE` / `FALSE` | `TRUE` |
| `SqlFloat64` | Bare float via `.toString()` | `3.14` |
| `SqlDate` | Quote-wrapped date string | `'2026-03-12'` |

The `SqlPart` interface is **sealed** — the compiler enforces exhaustive handling. Adding a new type without updating the rendering logic is a compile error.

**Layer 3: `SqlBuilder` separation (CWE-89 — structural safety)**

[`SqlBuilder`](src/sql_builder.temper.md) enforces a clean separation between SQL structure and data:
- `appendSafe(str)` — for SQL keywords and validated identifiers only
- `appendString(val)` → wraps in `SqlString` (escaped)
- `appendInt32(val)` → wraps in `SqlInt32` (bare integer)

There is no `appendRaw` or bypass method. The only way to get unescaped content into a query is through `appendSafe`, which is only ever called with hardcoded literals or `SafeIdentifier.sqlValue`.

**Layer 4: Changeset pipeline (CWE-915 — mass assignment)**

[`Changeset`](src/changeset.temper.md) is a **sealed interface** — `ChangesetImpl` is not exported, so construction only happens through the `changeset()` factory. The pipeline enforces:
- `cast(allowedFields)` — field whitelisting via `List<SafeIdentifier>`, prevents mass assignment
- `validateRequired(fields)` — non-nullable enforcement
- `toInsertSql()` / `toUpdateSql(id)` — independently enforces non-nullable fields regardless of `isValid`
- Raw `params` are never exposed — only whitelisted `changes` are readable
- `valueToSqlPart` uses exhaustive type dispatch on the sealed `FieldType` union

**Layer 5: Query builder (CWE-89, CWE-400)**

[`Query`](src/query.temper.md) requires `SafeIdentifier` for table names, column selections, ORDER BY clauses, and JOIN table names. WHERE and ON conditions accept only `SqlFragment` (never raw strings). `safeToSql(defaultLimit)` enforces result set bounds (CWE-400). JOIN type keywords (`INNER JOIN`, `LEFT JOIN`, etc.) are hardcoded from a sealed `JoinType` interface with exactly 4 implementations — no user input can influence the keyword.

### ORM-Level Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| ORM-1 | MEDIUM | CWE-89 | `toInsertSql`/`toUpdateSql` pass `pair.key` (a `String`) to `appendSafe`. Safe by construction — keys originate from `cast()` which requires `SafeIdentifier` — but the type system doesn't enforce this at the call site. A refactor that introduces a new code path to `changes` could silently bypass validation. |
| ORM-2 | LOW | CWE-89 | `SqlDate.formatTo` wraps `value.toString()` in quotes without escaping. If `Date.toString()` ever contains a single quote, this produces malformed SQL. Currently safe because date format is `YYYY-MM-DD`. |
| ORM-3 | LOW | CWE-20 | `SqlFloat64.formatTo` calls `value.toString()` which can produce `NaN` or `Infinity` — not valid SQL literals. SQLite silently accepts these as column names, so `SELECT NaN` returns a null rather than erroring. |
| ORM-4 | INFO | CWE-89 | The ORM renders fully-formed SQL strings via escaping rather than parameterized queries (`?` placeholders). While the escaping is correct for SQLite, parameterized queries are the gold standard defense. The TODO in [`sql_builder.temper.md`](src/sql_builder.temper.md) acknowledges this. |

### How Each App Uses the ORM vs Raw SQL

Every app needs raw SQL for two things the ORM doesn't cover: DDL (`CREATE TABLE`) and JOINs with aggregates (GROUP BY + COUNT/SUM). The ORM now supports basic JOINs (INNER, LEFT, RIGHT, FULL OUTER) but not yet aggregate functions. All user-facing CRUD flows through the ORM.

| Operation | JS | PY | RS | JV | LU | CS |
|-----------|----|----|----|----|----|----|
| SELECT (single table) | ORM `from()` | ORM `from_()` | ORM `from()` | ORM `from()` | ORM `from()` | ORM `From()` |
| INSERT | ORM `changeset().toInsertSql()` | ORM `changeset().to_insert_sql()` | ORM `changeset().to_insert_sql()` | ORM `changeset().toInsertSql()` | ORM `changeset().toInsertSql()` | ORM `Changeset().ToInsertSql()` |
| UPDATE | ORM `changeset().toUpdateSql()` | ORM `changeset().to_update_sql()` | ORM `changeset().to_update_sql()` | ORM `changeset().toUpdateSql()` | Raw `?` param | ORM `Changeset().ToUpdateSql()` |
| DELETE | ORM `deleteSql()` | ORM `delete_sql()` | ORM `delete_sql()` | ORM `deleteSql()` | ORM `deleteSql()` | ORM `DeleteSql()` |
| Toggle completed | Raw `?` param | Raw `?` param | ORM changeset | Raw `?` param | Raw `?` param | Raw via SqlBuilder |
| JOIN + aggregate | Raw `?` param | Raw `?` param | Raw (hardcoded) | Raw `?` param | Raw (hardcoded) | ORM `From()` |
| DDL | Raw (static) | Raw (static) | Raw (static) | Raw (static) | Raw (static) | Raw (static) |
| WHERE clauses | ORM `SqlBuilder` | ORM `SqlBuilder` | ORM `SqlBuilder` | ORM `SqlBuilder` | ORM `SqlBuilder` | ORM `SqlBuilder` |

**Raw SQL parameterization**: JS and Java achieve 100% parameterized raw SQL. Python and C# are near-100%. Rust and Lua have hardcoded JOIN queries (safe — no user input) and use `?` params elsewhere.

### Per-App Detailed Reports

Each app repo contains a `SECURITY_ANALYSIS.md` with SQL-specific findings:

| App | Report |
|-----|--------|
| JavaScript | [`generic-orm-js-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-js-app/blob/main/SECURITY_ANALYSIS.md) |
| Python | [`generic-orm-py-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-py-app/blob/main/SECURITY_ANALYSIS.md) |
| Rust | [`generic-orm-rust-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-rust-app/blob/main/SECURITY_ANALYSIS.md) |
| Java | [`generic-orm-java-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-java-app/blob/main/SECURITY_ANALYSIS.md) |
| Lua | [`generic-orm-lua-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-lua-app/blob/main/SECURITY_ANALYSIS.md) |
| C# | [`generic-orm-csharp-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/generic-orm-csharp-app/blob/main/SECURITY_ANALYSIS.md) |

### Remediation

Three of the four ORM-level findings were fixed in the Temper source, rebuilt across all 6 backends, and verified in compiled output. Here's the process and results.

#### ORM-1 (MEDIUM → RESOLVED): Column name type downgrade

**Problem:** `toInsertSql()` and `toUpdateSql()` in [`changeset.temper.md`](src/changeset.temper.md) passed `pair.key` (a raw `String`) to `appendSafe()`. The keys originate from `cast()` via `SafeIdentifier.sqlValue`, but the type system didn't enforce this — a future refactor could silently introduce an unvalidated code path.

**Fix:** Route column names through the looked-up `FieldDef.name` (a `SafeIdentifier`) instead of the raw map key:

```diff
- colNames.add(pair.key);                    // toInsertSql line 210
+ colNames.add(fd.name.sqlValue);            // fd = _tableDef.field(pair.key)

- b.appendSafe(pair.key);                    // toUpdateSql line 241
+ b.appendSafe(fd.name.sqlValue);
```

**Verification:** Compiled JS output confirms `fd_186.name.sqlValue` (INSERT) and `fd_204.name.sqlValue` (UPDATE) — no raw `pair.key` in `appendSafe` calls.

#### ORM-2 (LOW → RESOLVED): SqlDate missing quote escaping

**Problem:** [`SqlDate.formatTo()`](src/sql_model.temper.md) wrapped `value.toString()` in quotes without escaping. If `Date.toString()` ever contained a single quote, it would produce malformed SQL.

**Fix:** Added character-by-character escaping identical to `SqlString.formatTo()`:

```diff
  public formatTo(builder: StringBuilder): Void {
    builder.append("'");
-   builder.append(value.toString());
+   for (let c of value.toString()) {
+     if (c == char'\'') {
+       builder.append("''");
+     } else {
+       builder.appendCodePoint(c) orelse panic();
+     }
+   }
    builder.append("'");
  }
```

**Verification:** Compiled output shows the escaping loop in SqlDate across all backends.

#### ORM-3 (LOW → RESOLVED): SqlFloat64 NaN/Infinity

**Problem:** [`SqlFloat64.formatTo()`](src/sql_model.temper.md) called `value.toString()` which produces `NaN`, `Infinity`, or `-Infinity` — not valid SQL literals.

**Fix:** Check for non-representable values and render `NULL` (safest SQL representation):

```diff
  public formatTo(builder: StringBuilder): Void {
-   builder.append(value.toString());
+   let s = value.toString();
+   if (s == "NaN" || s == "Infinity" || s == "-Infinity") {
+     builder.append("NULL");
+   } else {
+     builder.append(s);
+   }
  }
```

**Verification:** New tests confirm `NaN`, `Infinity`, and `-Infinity` all render as `NULL`. Compiled JS shows the guard (`if (s_404 === "NaN") ... builder.append("NULL")`).

#### ORM-4 (INFO → ACKNOWLEDGED): No parameterized query support

**Status:** Not fixable in a patch — this is a design-level property. The TODO in [`sql_builder.temper.md`](src/sql_builder.temper.md) acknowledges the desire for prepared statement extraction. The current escaping-based approach is correct for SQLite; parameterized queries would add defense-in-depth.

#### Test Coverage

4 new test cases added to [`sql_tests.temper.md`](src/sql_tests.temper.md):
- `SqlFloat64 NaN renders as NULL`
- `SqlFloat64 Infinity renders as NULL`
- `SqlFloat64 negative Infinity renders as NULL`
- `SqlFloat64 normal values still work`

All 64 tests pass across the full suite (56 original + 4 float tests + 4 additional, plus 8 JOIN tests).

#### Summary

| Finding | Severity | Status | Fix |
|---------|----------|--------|-----|
| ORM-1 | MEDIUM | RESOLVED | Column names routed through `SafeIdentifier` in INSERT/UPDATE SQL |
| ORM-2 | LOW | RESOLVED | `SqlDate.formatTo()` now escapes single quotes |
| ORM-3 | LOW | RESOLVED | `SqlFloat64.formatTo()` renders NaN/Infinity as `NULL` |
| ORM-4 | INFO | ACKNOWLEDGED | Design limitation — escaping-based, not parameterized |
| ORM-5 | INFO | NEW | `SqlSource` and `appendSafe` are exported escape hatches that could be misused by application code |
| ORM-6 | LOW | NEW | No upper-bound enforcement on `limit()`/`offset()` values in `toSql()` |

### MITRE CWE Top 25 (2024) Mapping

Systematic assessment of the ORM against every CWE in the [2024 Top 25](https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html).

| Rank | CWE | Name | Status | Notes |
|------|-----|------|--------|-------|
| 1 | CWE-787 | Out-of-bounds Write | N/A | No manual memory management. All 6 targets are managed runtimes (or Rust with borrow checker). |
| 2 | CWE-79 | XSS | N/A | The ORM generates SQL, not HTML. XSS is the application layer's responsibility. |
| 3 | CWE-89 | SQL Injection | **Mitigated** | 5 defense layers: SafeIdentifier, SqlPart hierarchy, SqlBuilder separation, Changeset pipeline, Query builder. JOIN support follows identical patterns. |
| 4 | CWE-416 | Use After Free | N/A | All target runtimes are garbage-collected or borrow-checked. |
| 5 | CWE-78 | OS Command Injection | N/A | The ORM produces SQL fragments only — no process spawning. |
| 6 | CWE-20 | Improper Input Validation | **Mitigated** | `safeIdentifier()` rejects non-`[a-zA-Z_][a-zA-Z0-9_]*]`. Float NaN/Infinity → NULL. Negative limit/offset → bubble. |
| 7 | CWE-125 | Out-of-bounds Read | N/A | Bounds-checked on all backends. |
| 8 | CWE-22 | Path Traversal | N/A | No filesystem operations. |
| 9 | CWE-352 | CSRF | N/A | Library, not a web framework. |
| 10 | CWE-434 | File Upload | N/A | No file handling. |
| 11 | CWE-862 | Missing Authorization | N/A | No user/role model — application concern. |
| 12 | CWE-476 | NULL Pointer Deref | **Partial** | Nullable fields use local-variable narrowing pattern. Test `orelse panic()` is intentional. |
| 13 | CWE-287 | Improper Authentication | N/A | No auth mechanisms. |
| 14 | CWE-190 | Integer Overflow | **Partial** | Negative limit/offset rejected. No upper bound on LIMIT (see ORM-6). |
| 15 | CWE-502 | Deserialization | N/A | Accepts `Map<String, String>` — flat key-value, not serialized objects. |
| 16 | CWE-77 | Command Injection | N/A | No command execution. |
| 17 | CWE-119 | Buffer Overflow | N/A | No manual buffer management. |
| 18 | CWE-798 | Hardcoded Credentials | N/A | No credentials in ORM source. |
| 19 | CWE-918 | SSRF | N/A | Pure computation library — no network operations. |
| 20 | CWE-306 | Missing Auth for Critical Func | N/A | No critical functions requiring auth. |
| 21 | CWE-362 | Race Condition | N/A | Immutable data structures throughout. No shared mutable state. |
| 22 | CWE-269 | Privilege Management | N/A | No privilege model. |
| 23 | CWE-94 | Code Injection | N/A | Produces inert SQL strings — no code evaluation. |
| 24 | CWE-863 | Incorrect Authorization | N/A | No authorization model. |
| 25 | CWE-276 | Default Permissions | N/A | No file/resource creation. |
| — | CWE-400 | Resource Consumption | **Mitigated** | `safeToSql(defaultLimit)` enforces result set bounds. |
| — | CWE-915 | Mass Assignment | **Mitigated** | `cast(allowedFields)` with `SafeIdentifier` whitelist. Sealed `Changeset` interface. |

**Summary:** 4 Mitigated, 2 Partial, 19 N/A. No Vulnerable ratings at the ORM level.

### JOIN Feature Security Analysis

The ORM's JOIN support (added 2026-03-13) follows the same security model as the rest of the query builder:

| Component | Type | Injection Risk |
|-----------|------|----------------|
| JOIN keyword | `JoinType.keyword()` — sealed interface, 4 hardcoded strings | None |
| Table name | `SafeIdentifier` — validated `[a-zA-Z_][a-zA-Z0-9_]*` | None |
| ON condition | `SqlFragment` — type-safe parts via `SqlBuilder` or `sql` tag | None |
| `col()` helper | Two `SafeIdentifier` values joined by hardcoded `"."` | None |

**Key properties:**
- `JoinType` is sealed — no external subclass can return a malicious keyword
- JOIN table names require the same `SafeIdentifier` validation as `from()`
- ON conditions use the same `SqlFragment` type as WHERE conditions
- `toSql()` renders JOINs using only `appendSafe` (literals/identifiers) and `appendFragment` (structured parts)
- 8 dedicated test cases verify all join types, chaining, composition, and the `col()` helper

---

## Building Locally

### Prerequisites

- **JDK 21** (for building the Temper compiler)
- **Node.js 18+** (for running JS tests)
- **Git**

### Build Steps

```bash
# Clone and build the Temper compiler
git clone https://github.com/temperlang/temper.git /tmp/temper
cd /tmp/temper
./gradlew cli:installDist --no-daemon
export PATH="/tmp/temper/cli/build/install/temper/bin:$PATH"

# Clone this repo
git clone https://github.com/notactuallytreyanastasio/generic_orm.git
cd generic_orm

# Build all 6 backends
temper build

# Run tests (JS backend)
temper test -b js
```

Build output will be in `temper.out/` with subdirectories for each backend.

---

## Running the Demo Apps

Each app is in [`apps/<lang>/`](apps/) and needs the ORM vendored into its local `vendor/` directory.

### JavaScript

```bash
cd apps/js
mkdir -p vendor
cp -r ../../temper.out/js/{orm,std,temper-core} vendor/
npm install
node app.js
# Open http://localhost:5006
```

### Python

```bash
cd apps/py
mkdir -p vendor
cp -r ../../temper.out/py/{orm,std,temper-core} vendor/
pip install flask
python app.py
# Open http://localhost:5001
```

### Rust

```bash
cd apps/rust
mkdir -p vendor
cp -r ../../temper.out/rust/{orm,std,temper-core} vendor/
cargo run
# Open http://localhost:5003
```

### Java

```bash
cd apps/java
mkdir -p vendor
cp -r ../../temper.out/java/{orm,std,temper-core} vendor/
mvn spring-boot:run
# Open http://localhost:5004
```

### Lua

```bash
cd apps/lua
mkdir -p vendor
cp -r ../../temper.out/lua/{orm,std,temper-core} vendor/
# Requires lsqlite3: luarocks install lsqlite3
lua app.lua
# Open http://localhost:5005
```

### C#

```bash
cd apps/csharp/TodoApp
mkdir -p vendor
cp -r ../../../temper.out/csharp/{orm,std,temper-core} vendor/
dotnet run
# Open http://localhost:5002
```

---

## Project Structure

```
generic_orm/
├── config.temper.md              # Library config (defines "orm")
├── src/                          # Temper source (literate markdown)
│   ├── schema.temper.md          # SafeIdentifier, TableDef, FieldDef
│   ├── query.temper.md           # Query builder, from()
│   ├── changeset.temper.md       # Changeset pipeline
│   ├── orm.temper.md             # deleteSql() helper
│   ├── sql_builder.temper.md     # SqlBuilder
│   ├── sql_model.temper.md       # SqlFragment, SqlPart types
│   ├── sql_imports.temper.md     # Re-exports from secure-composition
│   ├── *_test.temper.md          # Test files
│   └── sql_tests.temper.md       # SQL builder tests
├── apps/                         # Demo applications
│   ├── js/                       # Express + EJS
│   ├── py/                       # Flask
│   ├── rust/                     # Axum + askama
│   ├── java/                     # Spring Boot
│   ├── lua/                      # Raw socket HTTP
│   └── csharp/                   # ASP.NET Core Razor Pages
├── .github/
│   ├── workflows/
│   │   └── publish-libs.yml      # CI: build + publish to lib repos
│   └── notify-app-template.yml   # Template: lib repo → app repo vendor update
├── temper.keep/                  # Temper build config (committed)
└── temper.out/                   # Build output (gitignored)
```
