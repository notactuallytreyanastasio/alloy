# Alloy

A type-safe, security-focused ORM written in [Temper](https://github.com/temperlang/temper) — a language that compiles to **6 backend targets** from a single source. This repo contains the ORM source, a CI pipeline that compiles and distributes the ORM to per-language library repos, and 6 demo todo-list applications (one per target language) that showcase the ORM in action.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Building](#building)
  - [Running the Demo Apps](#running-the-demo-apps)
- [API Reference](#api-reference)
  - [Core API](#core-api)
  - [Query Features](#query-features)
  - [Changeset Validations](#changeset-validations)
  - [Schema](#schema)
- [Source Files](#source-files)
- [Compilation Targets](#compilation-targets)
- [Demo Applications](#demo-applications)
  - [Cross-Language Usage](#cross-language-usage)
- [Security](#security)
  - [Defense Layers](#defense-layers)
  - [ORM-Level Findings](#orm-level-findings)
  - [Remediation](#remediation)
  - [MITRE CWE Top 25 Mapping](#mitre-cwe-top-25-mapping)
  - [Per-Phase Security Analysis](#per-phase-security-analysis)
  - [Per-App Reports](#per-app-detailed-reports)
  - [Full Security Research](#full-security-research)
- [CI Pipeline](#ci-pipeline)
- [Repository Map](#repository-map)
- [Project Structure](#project-structure)

---

## Architecture Overview

```
                    ┌────────────────────────┐
                    │     alloy (Temper)     │
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
  alloy-js alloy-py alloy-rust alloy-java alloy-lua alloy-csharp
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

## Getting Started

### Prerequisites

- **JDK 21** (for building the Temper compiler)
- **Node.js 18+** (for running JS tests)
- **Git**

### Building

```bash
# Clone and build the Temper compiler
git clone https://github.com/temperlang/temper.git /tmp/temper
cd /tmp/temper
./gradlew cli:installDist --no-daemon
export PATH="/tmp/temper/cli/build/install/temper/bin:$PATH"

# Clone this repo
git clone https://github.com/notactuallytreyanastasio/alloy.git
cd alloy

# Build all 6 backends
temper build

# Run tests (JS backend)
temper test -b js
```

Build output will be in `temper.out/` with subdirectories for each backend.

### Running the Demo Apps

Each app needs the ORM vendored into its local `vendor/` directory. Clone an app repo or use the local `apps/<lang>/` directory if present.

<details>
<summary><strong>JavaScript</strong> (Express + EJS, port 5006)</summary>

```bash
cd apps/js
mkdir -p vendor
cp -r ../../temper.out/js/{orm,std,temper-core} vendor/
npm install
node app.js
# Open http://localhost:5006
```
</details>

<details>
<summary><strong>Python</strong> (Flask, port 5001)</summary>

```bash
cd apps/py
mkdir -p vendor
cp -r ../../temper.out/py/{orm,std,temper-core} vendor/
pip install flask
python app.py
# Open http://localhost:5001
```
</details>

<details>
<summary><strong>Rust</strong> (Axum + askama, port 5003)</summary>

```bash
cd apps/rust
mkdir -p vendor
cp -r ../../temper.out/rust/{orm,std,temper-core} vendor/
cargo run
# Open http://localhost:5003
```
</details>

<details>
<summary><strong>Java</strong> (Spring Boot, port 5004)</summary>

```bash
cd apps/java
mkdir -p vendor
cp -r ../../temper.out/java/{orm,std,temper-core} vendor/
mvn spring-boot:run
# Open http://localhost:5004
```
</details>

<details>
<summary><strong>Lua</strong> (Raw socket HTTP, port 5005)</summary>

```bash
cd apps/lua
mkdir -p vendor
cp -r ../../temper.out/lua/{orm,std,temper-core} vendor/
# Requires lsqlite3: luarocks install lsqlite3
lua app.lua
# Open http://localhost:5005
```
</details>

<details>
<summary><strong>C#</strong> (ASP.NET Core Razor Pages, port 5002)</summary>

```bash
cd apps/csharp/TodoApp
mkdir -p vendor
cp -r ../../../temper.out/csharp/{orm,std,temper-core} vendor/
dotnet run
# Open http://localhost:5002
```
</details>

---

## API Reference

### Core API

```
┌─────────────────────────────────────────────────────────┐
│  safeIdentifier("users")  →  SafeIdentifier             │
│                                                         │
│  TableDef(safeId, fields, primaryKey?)                    │
│  FieldDef(safeId, StringField, nullable, default?, virt) │
│  timestamps() → [inserted_at, updated_at] with DEFAULT   │
│                                                         │
│  from(safeId)                                           │
│    .where(sqlFragment)                                  │
│    .orWhere(sqlFragment)                                │
│    .whereNull(safeId) / .whereNotNull(safeId)           │
│    .whereIn(safeId, sqlParts)                           │
│    .whereNot(sqlFragment)                               │
│    .whereBetween(safeId, low, high)                     │
│    .whereLike(safeId, pattern)                           │
│    .whereILike(safeId, pattern)                          │
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

### Query Features

| Category | Methods |
|----------|---------|
| **WHERE** | `where`, `orWhere`, `whereNull`, `whereNotNull`, `whereIn`, `whereNot`, `whereBetween`, `whereLike`, `whereILike`, `whereInSubquery` |
| **SELECT** | `select`, `selectExpr`, `distinct`, `countSql` |
| **ORDER** | `orderBy`, `orderByNulls` (`NullsFirst` / `NullsLast`) |
| **LIMIT** | `limit`, `offset`, `safeToSql(defaultLimit)` |
| **JOIN** | `join` (INNER, LEFT, RIGHT, FULL OUTER), `crossJoin` |
| **GROUP** | `groupBy`, `having`, `orHaving` |
| **Aggregates** | `countAll`, `countCol`, `sumCol`, `avgCol`, `minCol`, `maxCol` |
| **Set operations** | `unionSql`, `unionAllSql`, `intersectSql`, `exceptSql` |
| **Subqueries** | `subquery`, `existsSql`, `whereInSubquery` |
| **Mutations** | `update(table).set(field, value).where(cond).toSql()`, `deleteFrom(table).where(cond).toSql()` |
| **Locking** | `lock(new ForUpdate())`, `lock(new ForShare())` |

### Changeset Validations

| Category | Validators |
|----------|------------|
| **Required** | `validateRequired` |
| **Type** | `validateInt`, `validateInt64`, `validateFloat`, `validateBool` |
| **Length** | `validateLength` |
| **Range** | `validateNumber` |
| **Inclusion** | `validateInclusion`, `validateExclusion` |
| **String** | `validateContains`, `validateStartsWith`, `validateEndsWith` |
| **Confirmation** | `validateConfirmation`, `validateAcceptance` |
| **Data** | `putChange`, `getChange`, `deleteChange` |

### Schema

**Field types:** `StringField`, `IntField`, `Int64Field`, `FloatField`, `BoolField`, `DateField`

**Schema features:** `TableDef.primaryKey` (custom PK column), `FieldDef.defaultValue` (`SqlDefault` for DB defaults), `FieldDef.virtual` (excluded from SQL), `timestamps()` (inserted_at/updated_at with DEFAULT)

---

## Source Files

All source lives in [`src/`](src/) as Temper literate markdown (`.temper.md`):

| File | Purpose |
|------|---------|
| [`schema.temper.md`](src/schema.temper.md) | `SafeIdentifier`, `FieldType`, `FieldDef` (defaultValue, virtual), `TableDef` (primaryKey), `timestamps()` |
| [`query.temper.md`](src/query.temper.md) | `Query`, `from()`, `WhereClause`, `JoinType` (5 variants), `OrderClause`, `NullsPosition`, `LockMode`, `UpdateQuery`, `DeleteQuery`, set operations, subqueries, aggregates |
| [`changeset.temper.md`](src/changeset.temper.md) | `Changeset`, `changeset()`, cast/validate/SQL pipeline |
| [`orm.temper.md`](src/orm.temper.md) | `deleteSql()` top-level helper |
| [`sql_builder.temper.md`](src/sql_builder.temper.md) | `SqlBuilder`, `sql` tag |
| [`sql_model.temper.md`](src/sql_model.temper.md) | `SqlFragment`, `SqlPart`, `SqlString`, `SqlInt32`, `SqlDefault`, etc. |
| [`sql_imports.temper.md`](src/sql_imports.temper.md) | SQL builder/model type re-exports |
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

| Language | Framework | Port | App Repo |
|----------|-----------|------|----------|
| **JavaScript** | Express + EJS + better-sqlite3 | 5006 | [`alloy-js-app`](https://github.com/notactuallytreyanastasio/alloy-js-app) |
| **Python** | Flask + sqlite3 | 5001 | [`alloy-py-app`](https://github.com/notactuallytreyanastasio/alloy-py-app) |
| **Rust** | Axum + rusqlite + askama | 5003 | [`alloy-rust-app`](https://github.com/notactuallytreyanastasio/alloy-rust-app) |
| **Java** | Spring Boot + SQLite JDBC + Thymeleaf | 5004 | [`alloy-java-app`](https://github.com/notactuallytreyanastasio/alloy-java-app) |
| **Lua** | Raw socket HTTP + lsqlite3 | 5005 | [`alloy-lua-app`](https://github.com/notactuallytreyanastasio/alloy-lua-app) |
| **C#** | ASP.NET Core Razor Pages + SQLite | 5002 | [`alloy-csharp-app`](https://github.com/notactuallytreyanastasio/alloy-csharp-app) |

### Cross-Language Usage

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

### How Each App Uses the ORM vs Raw SQL

Every app needs raw SQL for DDL (`CREATE TABLE`), which the ORM intentionally does not cover. All user-facing CRUD flows through the ORM.

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

---

## Security

The entire point of this project is demonstrating type-safe SQL generation across 6 languages from a single source. The ORM is built on a defense-in-depth approach to SQL injection prevention, using Temper's type system to enforce safety at compile time.

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
| `SqlDefault` | Literal `DEFAULT` keyword | `DEFAULT` |

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

[`Query`](src/query.temper.md) requires `SafeIdentifier` for table names, column selections, ORDER BY clauses, and JOIN table names. WHERE and ON conditions accept only `SqlFragment` (never raw strings). `safeToSql(defaultLimit)` enforces result set bounds (CWE-400). JOIN type keywords are hardcoded from a sealed `JoinType` interface. WHERE conditions use a sealed `WhereClause` interface (`AndCondition`/`OrCondition`), and convenience methods build fragments internally using only validated identifiers and typed values. `UpdateQuery` and `DeleteQuery` bubble on empty WHERE clauses, preventing accidental full-table mutations. Row locking and nulls position use sealed interfaces with hardcoded keywords.

### ORM-Level Findings

| # | Severity | CWE | Finding | Status |
|---|----------|-----|---------|--------|
| ORM-1 | MEDIUM | CWE-89 | `toInsertSql`/`toUpdateSql` passed `pair.key` (a `String`) to `appendSafe`. Safe by construction but type system didn't enforce it. | RESOLVED |
| ORM-2 | LOW | CWE-89 | `SqlDate.formatTo` wrapped `value.toString()` in quotes without escaping. | RESOLVED |
| ORM-3 | LOW | CWE-20 | `SqlFloat64.formatTo` could produce `NaN` or `Infinity` — not valid SQL literals. | RESOLVED |
| ORM-4 | INFO | CWE-89 | ORM renders fully-formed SQL via escaping rather than parameterized queries. | ACKNOWLEDGED |
| ORM-5 | INFO | — | `SqlSource` and `appendSafe` are exported escape hatches that could be misused by application code. | NEW |
| ORM-6 | LOW | CWE-190 | No upper-bound enforcement on `limit()`/`offset()` values in `toSql()`. | NEW |

### Remediation

<details>
<summary><strong>ORM-1 (MEDIUM → RESOLVED):</strong> Column name type downgrade</summary>

**Problem:** `toInsertSql()` and `toUpdateSql()` in [`changeset.temper.md`](src/changeset.temper.md) passed `pair.key` (a raw `String`) to `appendSafe()`. The keys originate from `cast()` via `SafeIdentifier.sqlValue`, but the type system didn't enforce this.

**Fix:** Route column names through the looked-up `FieldDef.name` (a `SafeIdentifier`) instead of the raw map key:

```diff
- colNames.add(pair.key);                    // toInsertSql line 210
+ colNames.add(fd.name.sqlValue);            // fd = _tableDef.field(pair.key)

- b.appendSafe(pair.key);                    // toUpdateSql line 241
+ b.appendSafe(fd.name.sqlValue);
```

**Verification:** Compiled JS output confirms `fd_186.name.sqlValue` (INSERT) and `fd_204.name.sqlValue` (UPDATE) — no raw `pair.key` in `appendSafe` calls.
</details>

<details>
<summary><strong>ORM-2 (LOW → RESOLVED):</strong> SqlDate missing quote escaping</summary>

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
</details>

<details>
<summary><strong>ORM-3 (LOW → RESOLVED):</strong> SqlFloat64 NaN/Infinity</summary>

**Problem:** [`SqlFloat64.formatTo()`](src/sql_model.temper.md) called `value.toString()` which produces `NaN`, `Infinity`, or `-Infinity` — not valid SQL literals.

**Fix:** Check for non-representable values and render `NULL`:

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

**Verification:** New tests confirm `NaN`, `Infinity`, and `-Infinity` all render as `NULL`.
</details>

<details>
<summary><strong>ORM-4 (INFO → ACKNOWLEDGED):</strong> No parameterized query support</summary>

Not fixable in a patch — this is a design-level property. The TODO in [`sql_builder.temper.md`](src/sql_builder.temper.md) acknowledges the desire for prepared statement extraction. The current escaping-based approach is correct for SQLite; parameterized queries would add defense-in-depth.
</details>

**Test Coverage:** 4 new test cases in [`sql_tests.temper.md`](src/sql_tests.temper.md) — all 184 tests pass across the full suite.

### MITRE CWE Top 25 Mapping

Assessment against SQL-relevant CWEs from the [2024 Top 25](https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html). Non-SQL CWEs (memory safety, XSS, CSRF, authentication) are omitted — the ORM is a SQL generation library and those concerns belong to the application layer.

| CWE | Name | Status | Notes |
|-----|------|--------|-------|
| CWE-89 | SQL Injection | **Mitigated** | 5 defense layers: SafeIdentifier, SqlPart hierarchy, SqlBuilder separation, Changeset pipeline, Query builder |
| CWE-20 | Improper Input Validation | **Mitigated** | `safeIdentifier()` rejects non-`[a-zA-Z_][a-zA-Z0-9_]*]`. Float NaN/Infinity → NULL. Negative limit/offset → bubble |
| CWE-190 | Integer Overflow | **Partial** | Negative limit/offset rejected. No upper bound on LIMIT (see ORM-6) |
| CWE-400 | Resource Consumption | **Mitigated** | `safeToSql(defaultLimit)` enforces result set bounds. Set operations unbounded |
| CWE-915 | Mass Assignment | **Mitigated** | `cast(allowedFields)` with `SafeIdentifier` whitelist. Sealed `Changeset` interface |
| CWE-284 | Access Control | **Mitigated** | `UpdateQuery`/`DeleteQuery` bubble on empty WHERE — prevents accidental full-table mutations |

**Summary:** 5 Mitigated, 1 Partial. All SQL-relevant CWEs are mitigated or partially mitigated at the ORM level.

### Per-Phase Security Analysis

<details>
<summary><strong>Phase 1: JOIN</strong></summary>

| Component | Type | Injection Risk |
|-----------|------|----------------|
| JOIN keyword | `JoinType.keyword()` — sealed interface, 4 hardcoded strings | None |
| Table name | `SafeIdentifier` — validated `[a-zA-Z_][a-zA-Z0-9_]*` | None |
| ON condition | `SqlFragment` — type-safe parts via `SqlBuilder` or `sql` tag | None |
| `col()` helper | Two `SafeIdentifier` values joined by hardcoded `"."` | None |

`JoinType` is sealed — no external subclass can return a malicious keyword. JOIN table names require the same `SafeIdentifier` validation as `from()`. ON conditions use the same `SqlFragment` type as WHERE conditions. 8 dedicated test cases verify all join types, chaining, composition, and the `col()` helper.
</details>

<details>
<summary><strong>Phase 2: WHERE Clause Enrichment</strong></summary>

| Component | Type | Injection Risk |
|-----------|------|----------------|
| `WhereClause.keyword()` | Sealed interface — hardcoded `"AND"` or `"OR"` | None |
| `whereNull` / `whereNotNull` | `SafeIdentifier` field + hardcoded `IS NULL` / `IS NOT NULL` | None |
| `whereIn` values | `List<SqlPart>` — type-dispatched escaping per element | None |
| `whereIn` empty list | Hardcoded `1 = 0` — always-false degenerate case | None |
| `whereNot` condition | `SqlFragment` wrapped in hardcoded `NOT (...)` | None |
| `whereBetween` bounds | `SqlPart` values — type-dispatched rendering | None |
| `whereLike` / `whereILike` pattern | `String` → `SqlString` — single-quote escaping | None |

21 dedicated test cases verify all operators, chaining, mixed AND/OR logic, and injection attempts.
</details>

<details>
<summary><strong>Phase 3: Aggregation</strong></summary>

All 6 aggregate functions (`countAll`, `countCol`, `sumCol`, `avgCol`, `minCol`, `maxCol`) use hardcoded function name strings via `appendSafe`. Field names require `SafeIdentifier`. `selectExpr`, `groupBy`, `having`/`orHaving` reuse existing safe types (`SqlFragment`, `WhereClause`). `distinct()` is a boolean flag selecting between two hardcoded strings. No new injection vectors.
</details>

<details>
<summary><strong>Phase 4: Set Operations & Subqueries</strong></summary>

Set operation keywords (`UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT`) are hardcoded string literals. Both operands are `Query` objects (not strings). Sub-SELECTs are parenthesized via hardcoded `(...)`. `subquery()` alias requires `SafeIdentifier`. `existsSql()` wraps in hardcoded `EXISTS (...)`. `whereInSubquery()` combines `SafeIdentifier` field with `Query` subquery. No injection vectors.
</details>

<details>
<summary><strong>Phase 5: Batch UPDATE/DELETE</strong></summary>

| Component | Type Safety Mechanism | Risk |
|-----------|----------------------|------|
| `SetClause.field` | `SafeIdentifier` — sealed, validated | None |
| `SetClause.value` | `SqlPart` — sealed, type-dispatched escaping | None |
| `UpdateQuery.toSql()` no-WHERE guard | Bubbles on empty conditions | **Prevents full-table UPDATE** |
| `DeleteQuery.toSql()` no-WHERE guard | Bubbles on empty conditions | **Prevents full-table DELETE** |
</details>

<details>
<summary><strong>Phase 6: Extended Query Features</strong></summary>

| Component | Type Safety Mechanism | Risk |
|-----------|----------------------|------|
| `NullsPosition.keyword()` | Sealed interface — 2 hardcoded strings | None |
| `CrossJoin.keyword()` | Sealed interface — hardcoded `"CROSS JOIN"` | None |
| Nullable `onCondition` | When null, ON clause omitted entirely | None |
| `LockMode.keyword()` | Sealed interface — 2 hardcoded strings | None |
</details>

<details>
<summary><strong>Phase 7: Changeset Enrichment</strong></summary>

All Phase 7 methods (`putChange`, `getChange`, `deleteChange`, `validateInclusion`, `validateExclusion`, `validateNumber`, `validateAcceptance`, `validateConfirmation`, `validateContains`, `validateStartsWith`, `validateEndsWith`) operate on the `changes` Map — string validation and manipulation only, no SQL generation. Field parameters require `SafeIdentifier`. Values only reach SQL later through `toInsertSql()`/`toUpdateSql()`, which use `valueToSqlPart` (type-dispatched escaping). Immutable pattern preserved — all methods return new `Changeset` instances. No new SQL injection surface.
</details>

<details>
<summary><strong>Phase 8: Schema Enrichment</strong></summary>

| Component | Type Safety Mechanism | Risk |
|-----------|----------------------|------|
| `TableDef.primaryKey` | `SafeIdentifier?` — validated at construction | None |
| `pkName()` | Returns `SafeIdentifier.sqlValue` or hardcoded `"id"` | None |
| `FieldDef.defaultValue` | `SqlPart?` — type-dispatched rendering | None |
| `SqlDefault` | Renders hardcoded `"DEFAULT"` string | None |
| `FieldDef.virtual` | Boolean flag — virtual fields excluded from SQL entirely | **Reduces attack surface** |
| `timestamps()` | Hardcoded field names via `safeIdentifier()` + `SqlDefault` | None |
</details>

### Per-App Detailed Reports

Each app repo contains a `SECURITY_ANALYSIS.md` with SQL-specific findings:

| App | Report |
|-----|--------|
| JavaScript | [`alloy-js-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-js-app/blob/main/SECURITY_ANALYSIS.md) |
| Python | [`alloy-py-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-py-app/blob/main/SECURITY_ANALYSIS.md) |
| Rust | [`alloy-rust-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-rust-app/blob/main/SECURITY_ANALYSIS.md) |
| Java | [`alloy-java-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-java-app/blob/main/SECURITY_ANALYSIS.md) |
| Lua | [`alloy-lua-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-lua-app/blob/main/SECURITY_ANALYSIS.md) |
| C# | [`alloy-csharp-app/SECURITY_ANALYSIS.md`](https://github.com/notactuallytreyanastasio/alloy-csharp-app/blob/main/SECURITY_ANALYSIS.md) |

### Full Security Research

See [RESEARCH.md](docs/RESEARCH.md) for detailed per-phase MITRE CWE Top 25 analysis with component-level security assessment tables.

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
| `js` | [`alloy-js`](https://github.com/notactuallytreyanastasio/alloy-js) | [`alloy-js-app`](https://github.com/notactuallytreyanastasio/alloy-js-app) | `vendor` |
| `py` | [`alloy-py`](https://github.com/notactuallytreyanastasio/alloy-py) | [`alloy-py-app`](https://github.com/notactuallytreyanastasio/alloy-py-app) | `vendor` |
| `rust` | [`alloy-rust`](https://github.com/notactuallytreyanastasio/alloy-rust) | [`alloy-rust-app`](https://github.com/notactuallytreyanastasio/alloy-rust-app) | `vendor` |
| `java` | [`alloy-java`](https://github.com/notactuallytreyanastasio/alloy-java) | [`alloy-java-app`](https://github.com/notactuallytreyanastasio/alloy-java-app) | `vendor` |
| `lua` | [`alloy-lua`](https://github.com/notactuallytreyanastasio/alloy-lua) | [`alloy-lua-app`](https://github.com/notactuallytreyanastasio/alloy-lua-app) | `vendor` |
| `csharp` | [`alloy-csharp`](https://github.com/notactuallytreyanastasio/alloy-csharp) | [`alloy-csharp-app`](https://github.com/notactuallytreyanastasio/alloy-csharp-app) | `TodoApp/vendor` |

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

This creates a fully automated cascade: **ORM source change** → **build** → **lib repos** → **app repos**.

---

## Repository Map

### This Repository (Source)

| Repo | Description |
|------|-------------|
| [`alloy`](https://github.com/notactuallytreyanastasio/alloy) | Temper ORM source, CI pipeline, app source code |

### Library Repos (Compiled Output)

| Repo | Language | Contents |
|------|----------|----------|
| [`alloy-js`](https://github.com/notactuallytreyanastasio/alloy-js) | JavaScript | ES modules |
| [`alloy-py`](https://github.com/notactuallytreyanastasio/alloy-py) | Python | Python 3 modules |
| [`alloy-rust`](https://github.com/notactuallytreyanastasio/alloy-rust) | Rust | Cargo crate |
| [`alloy-java`](https://github.com/notactuallytreyanastasio/alloy-java) | Java | Java source |
| [`alloy-lua`](https://github.com/notactuallytreyanastasio/alloy-lua) | Lua | Lua modules |
| [`alloy-csharp`](https://github.com/notactuallytreyanastasio/alloy-csharp) | C# | .NET source |

### Application Repos (Demo Apps)

| Repo | Language | Framework |
|------|----------|-----------|
| [`alloy-js-app`](https://github.com/notactuallytreyanastasio/alloy-js-app) | JavaScript | Express + EJS |
| [`alloy-py-app`](https://github.com/notactuallytreyanastasio/alloy-py-app) | Python | Flask |
| [`alloy-rust-app`](https://github.com/notactuallytreyanastasio/alloy-rust-app) | Rust | Axum + askama |
| [`alloy-java-app`](https://github.com/notactuallytreyanastasio/alloy-java-app) | Java | Spring Boot |
| [`alloy-lua-app`](https://github.com/notactuallytreyanastasio/alloy-lua-app) | Lua | Raw socket HTTP |
| [`alloy-csharp-app`](https://github.com/notactuallytreyanastasio/alloy-csharp-app) | C# | ASP.NET Core Razor |

---

## Project Structure

```
alloy/
├── config.temper.md              # Library config (defines "orm")
├── src/                          # Temper source (literate markdown)
│   ├── schema.temper.md          # SafeIdentifier, TableDef, FieldDef
│   ├── query.temper.md           # Query builder, from()
│   ├── changeset.temper.md       # Changeset pipeline
│   ├── orm.temper.md             # deleteSql() helper
│   ├── sql_builder.temper.md     # SqlBuilder
│   ├── sql_model.temper.md       # SqlFragment, SqlPart types
│   ├── sql_imports.temper.md     # Type re-exports
│   ├── *_test.temper.md          # Test files
│   └── sql_tests.temper.md       # SQL builder tests
├── .github/
│   ├── workflows/
│   │   └── publish-libs.yml      # CI: build + publish to lib repos
│   └── notify-app-template.yml   # Template: lib repo → app repo vendor update
├── temper.keep/                  # Temper build config (committed)
└── temper.out/                   # Build output (gitignored)
```
