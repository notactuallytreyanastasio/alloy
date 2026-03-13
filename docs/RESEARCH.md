# Security Research: MITRE CWE Top 25 Analysis

Systematic security assessment of the Temper ORM against the [MITRE CWE Top 25 (2024)](https://cwe.mitre.org/top25/archive/2024/2024_cwe_top25.html), conducted per-phase as features were added.

## Table of Contents

- [Phase 1: WHERE Clause Enrichment](#phase-1-where-clause-enrichment)
- [Phase 2: Aggregation](#phase-2-aggregation)
- [Phase 3: Set Operations and Subqueries](#phase-3-set-operations-and-subqueries)
- [Phase 4: Batch UPDATE and DELETE](#phase-4-batch-update-and-delete)
- [Phase 5: Extended Query Features](#phase-5-extended-query-features)
- [Phase 6: Changeset Enrichment](#phase-6-changeset-enrichment)
- [Phase 7: Schema Enrichment](#phase-7-schema-enrichment)
- [Cumulative CWE Mapping](#cumulative-cwe-mapping)

---

## Phase 1: WHERE Clause Enrichment

### Components Analyzed

| Component | Type Safety Mechanism | Injection Risk |
|-----------|----------------------|----------------|
| `WhereClause.keyword()` | Sealed interface -- hardcoded `"AND"` or `"OR"` | None |
| `whereNull` / `whereNotNull` | `SafeIdentifier` field + hardcoded `IS NULL` / `IS NOT NULL` | None |
| `whereIn` values | `List<SqlPart>` -- type-dispatched escaping per element | None |
| `whereIn` empty list | Hardcoded `1 = 0` -- always-false degenerate case | None |
| `whereNot` condition | `SqlFragment` wrapped in hardcoded `NOT (...)` | None |
| `whereBetween` bounds | `SqlPart` values -- type-dispatched rendering | None |
| `whereLike` / `whereILike` pattern | `String` -> `SqlString` -- single-quote escaping | None |

### Key Properties

- `WhereClause` is sealed -- no external subclass can return a malicious keyword
- All convenience methods delegate to `this.where()` which wraps in `AndCondition`
- LIKE/ILIKE patterns go through `SqlString` escaping (single-quote doubling)
- Empty IN list produces `1 = 0` rather than invalid SQL syntax
- 21 dedicated test cases verify all operators, chaining, mixed AND/OR logic, and injection attempts

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P1-1 | None | CWE-89 | All WHERE operators use hardcoded SQL keywords via `appendSafe`. No user input reaches keyword positions. |
| P1-2 | None | CWE-20 | Field names require `SafeIdentifier`. LIKE patterns use `SqlString` escaping. IN values are `SqlPart`-typed. |

---

## Phase 2: Aggregation

### Components Analyzed

| Component | Type Safety Mechanism | SQL Keywords | Injection Risk |
|-----------|----------------------|-------------|----------------|
| `countAll()` | No parameters; returns hardcoded `"COUNT(*)"` | Hardcoded literal | None |
| `countCol(field)` | `field: SafeIdentifier` | `"COUNT("`, `")"` hardcoded | None |
| `sumCol(field)` | `field: SafeIdentifier` | `"SUM("`, `")"` hardcoded | None |
| `avgCol(field)` | `field: SafeIdentifier` | `"AVG("`, `")"` hardcoded | None |
| `minCol(field)` | `field: SafeIdentifier` | `"MIN("`, `")"` hardcoded | None |
| `maxCol(field)` | `field: SafeIdentifier` | `"MAX("`, `")"` hardcoded | None |
| `selectExpr(exprs)` | `exprs: List<SqlFragment>` | `", "` separator hardcoded | None |
| `groupBy(field)` | `field: SafeIdentifier` | `" GROUP BY "`, `", "` hardcoded | None |
| `having(condition)` | `condition: SqlFragment`; wraps in `AndCondition` | `" HAVING "`, `" AND "` hardcoded | None |
| `orHaving(condition)` | `condition: SqlFragment`; wraps in `OrCondition` | `" OR "` hardcoded | None |
| `distinct()` | `isDistinct: Boolean` -- primitive | `"SELECT DISTINCT "` hardcoded | None |
| `countSql()` | No parameters; reuses validated query state | `"SELECT COUNT(*) FROM "` hardcoded | None |

### Key Properties

- No raw `String` reaches `appendSafe` in any aggregation code path
- All 6 aggregate functions use the identical 3-line pattern: `appendSafe(fn + "(")`, `appendSafe(field.sqlValue)`, `appendSafe(")")`
- `selectExpr` and `having`/`orHaving` reuse existing safe types (`SqlFragment`, `WhereClause`)
- `countSql()` intentionally strips LIMIT/OFFSET (correct for COUNT semantics)

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| AGG-1 | Info | CWE-89 | All Phase 2 features use identical injection-proof patterns. No new attack surface. |
| AGG-2 | Info | CWE-400 | `countSql()` strips LIMIT, which is correct for COUNT but could produce expensive queries on large tables. |
| AGG-3 | Info | CWE-20 | Aggregate functions don't validate that columns are numeric. The database catches semantic errors. |

---

## Phase 3: Set Operations and Subqueries

### Components Analyzed

| Component | Function Signature | SQL Keyword Source | Injection Risk |
|-----------|-------------------|-------------------|----------------|
| `unionSql()` | `(a: Query, b: Query): SqlFragment` | Hardcoded `") UNION ("` literal | None |
| `unionAllSql()` | `(a: Query, b: Query): SqlFragment` | Hardcoded `") UNION ALL ("` literal | None |
| `intersectSql()` | `(a: Query, b: Query): SqlFragment` | Hardcoded `") INTERSECT ("` literal | None |
| `exceptSql()` | `(a: Query, b: Query): SqlFragment` | Hardcoded `") EXCEPT ("` literal | None |
| `subquery()` | `(q: Query, alias: SafeIdentifier): SqlFragment` | Hardcoded `") AS "` literal | None |
| `existsSql()` | `(q: Query): SqlFragment` | Hardcoded `"EXISTS ("` literal | None |
| `whereInSubquery()` | `(field: SafeIdentifier, sub: Query): Query` | Hardcoded `" IN ("` literal | None |

### Key Properties

- All set operation keywords (`UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT`) are hardcoded string literals
- Both operands are `Query` objects (not strings) -- enforcing SafeIdentifier for table names
- Sub-SELECTs are parenthesized via hardcoded `(...)` -- preventing syntax ambiguity
- Composition uses `appendFragment` which preserves structured `SqlPart` boundaries
- `subquery()` alias requires `SafeIdentifier` -- cannot contain SQL metacharacters
- 10 dedicated test cases covering all operations, WHERE on each side, and nested subqueries

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P3-1 | None | CWE-89 | All keywords hardcoded, all identifiers validated, all user data type-dispatched. Zero injection vectors. |
| P3-2 | Info | CWE-400 | Set operations produce unbounded result sets. Application must apply its own LIMIT. |

---

## Phase 4: Batch UPDATE and DELETE

### Components Analyzed

| Component | Type Safety Mechanism | CWE-89 | CWE-284 (Access Control) | Risk |
|-----------|----------------------|--------|--------------------------|------|
| `SetClause.field` | `SafeIdentifier` -- sealed, validated | None | N/A | None |
| `SetClause.value` | `SqlPart` -- sealed, type-dispatched escaping | None | N/A | None |
| `UpdateQuery.set()` | `SafeIdentifier` + `SqlPart` | None | N/A | None |
| `UpdateQuery.where()` | `SqlFragment` (structured parts) | None | N/A | None |
| `UpdateQuery.toSql()` no-WHERE guard | Bubbles on empty conditions | N/A | **Prevents full-table UPDATE** | None |
| `UpdateQuery.toSql()` no-SET guard | Bubbles on empty SET clauses | N/A | Prevents empty UPDATE | None |
| `DeleteQuery.where()` | `SqlFragment` | None | N/A | None |
| `DeleteQuery.toSql()` no-WHERE guard | Bubbles on empty conditions | N/A | **Prevents full-table DELETE** | None |
| `update()` factory | Requires `SafeIdentifier` | None | Safe-by-default (empty state) | None |
| `deleteFrom()` factory | Requires `SafeIdentifier` | None | Safe-by-default (empty state) | None |

### Key Properties

- **Destructive operation guard**: `toSql()` bubbles on empty WHERE conditions, making accidental full-table UPDATE/DELETE impossible through the public API
- `UpdateQuery` also guards against empty SET clauses
- Both guards use `throws Bubble`, forcing callers to handle the error path
- SET clause values are `SqlPart` (sealed) -- type-dispatched escaping for all value types
- 13 dedicated test cases including escaping verification and no-WHERE bubble tests

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P4-1 | None | CWE-89 | No injection vectors. All identifiers via SafeIdentifier, all values via SqlPart. |
| P4-2 | None | CWE-284 | No-WHERE guard is adequate. Both UpdateQuery and DeleteQuery bubble on empty conditions. |
| P4-3 | Low | CWE-20 | No upper bound on `limit()` values (consistent with existing ORM-6). |
| P4-4 | Info | CWE-89 | `SqlSource` escape hatch remains available (existing ORM-5). |

---

## Phase 5: Extended Query Features

### Components Analyzed

| Component | Type Safety Mechanism | Injection Risk |
|-----------|----------------------|----------------|
| `NullsPosition.keyword()` | Sealed interface -- `" NULLS FIRST"` or `" NULLS LAST"` hardcoded | None |
| `orderByNulls()` | `SafeIdentifier` field + `Boolean` ascending + `NullsPosition` | None |
| `CrossJoin.keyword()` | Sealed interface -- `"CROSS JOIN"` hardcoded | None |
| `crossJoin()` | `SafeIdentifier` table + null onCondition (ON clause omitted) | None |
| Nullable `onCondition` | `SqlFragment?` -- when null, ON clause skipped entirely | None |
| `LockMode.keyword()` | Sealed interface -- `" FOR UPDATE"` or `" FOR SHARE"` hardcoded | None |
| `lock()` | Takes `LockMode` (sealed, 2 variants) | None |

### Key Properties

- All three features follow the sealed-interface-with-hardcoded-keywords pattern
- `NullsPosition` sealed: exactly 2 implementations, each returning a hardcoded string
- `CrossJoin` extends `JoinType` sealed: total 5 implementations, all hardcoded
- `LockMode` sealed: exactly 2 implementations
- Nullable `onCondition` in JoinClause uses local-variable narrowing pattern for null check
- `crossJoin()` creates JoinClause with `null` onCondition -- ON clause simply omitted
- Regular `join()` still requires non-nullable `SqlFragment` for ON condition
- Query constructor grows to 12 params but all `new Query(...)` calls pass through

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P5-1 | None | CWE-89 | Three new sealed interfaces, all with hardcoded keyword strings. No user input reaches appendSafe. |
| P5-2 | None | CWE-476 | Three new nullable fields all use correct local-variable narrowing. No null dereference risk. |
| P5-3 | None | CWE-362 | Query remains fully immutable. `lock()`, `orderByNulls()`, `crossJoin()` all return new instances. |

---

## Phase 6: Changeset Enrichment

### Components Analyzed

| Component | Purpose | SQL Impact | Risk |
|-----------|---------|-----------|------|
| `putChange(field, value)` | Add/overwrite changes map entry | None -- operates on `Map<String, String>`, not SQL | None |
| `getChange(field)` | Retrieve change value, bubble if missing | None -- pure map lookup | None |
| `deleteChange(field)` | Remove changes map entry | None -- pure map rebuild | None |
| `validateInclusion(field, allowed)` | Value must be in allowed list | None -- string comparison only | None |
| `validateExclusion(field, disallowed)` | Value must not be in disallowed list | None -- string comparison only | None |
| `validateNumber(field, opts)` | Numeric range constraints | None -- Float64 comparison only | None |
| `validateAcceptance(field)` | Must be truthy (true/1/yes/on) | None -- string comparison only | None |
| `validateConfirmation(field, confField)` | Confirmation must match | None -- string comparison only | None |
| `validateContains(field, substring)` | Must contain substring | None -- `indexOf` only | None |
| `validateStartsWith(field, prefix)` | Must start with prefix | None -- `indexOf` + `countBetween` | None |
| `validateEndsWith(field, suffix)` | Must end with suffix | None -- cursor-based char comparison | None |

### Key Properties

- **No SQL generation**: All Phase 6 methods operate on the `changes` Map (validation/manipulation), not on SQL output
- All field parameters are `SafeIdentifier` -- validated identifiers
- `NumberValidationOpts` uses nullable `Float64?` fields with local-variable narrowing
- `putChange` values only reach SQL later through `toInsertSql()`/`toUpdateSql()`, which use `valueToSqlPart` (type-dispatched escaping)
- `validateEndsWith` uses cursor-based character comparison for correctness (handles repeated suffixes)
- Immutable pattern preserved -- all methods return new `Changeset` instances

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P6-1 | None | CWE-89 | No new SQL injection surface. Validation methods operate on string values, not SQL. |
| P6-2 | None | CWE-20 | All field names require `SafeIdentifier`. Numeric validation properly parses and checks bounds. |
| P6-3 | None | CWE-915 | Sealed `Changeset` interface preserved. `putChange` still goes through validated pipeline. |

---

## Phase 7: Schema Enrichment

### Components Analyzed

| Component | Type Safety Mechanism | Injection Risk |
|-----------|----------------------|----------------|
| `TableDef.primaryKey` | `SafeIdentifier?` -- sealed, non-exported implementation | None |
| `pkName()` | Returns `SafeIdentifier.sqlValue` or hardcoded `"id"` | None |
| `FieldDef.defaultValue` | `SqlPart?` -- sealed interface, type-dispatched rendering | None |
| `SqlDefault.formatTo()` | Hardcoded `"DEFAULT"` string literal | None |
| `FieldDef.virtual` | Boolean flag -- virtual fields excluded from SQL entirely | None (reduces surface) |
| `timestamps()` | Hardcoded field names via `safeIdentifier()` + `SqlDefault` values | None |
| `toInsertSql()` virtual skip | `if (f.virtual) { continue; }` in three loops | None (reduces surface) |
| `toUpdateSql()` custom PK | `appendSafe(_tableDef.pkName())` -- validated or hardcoded | None |
| `deleteSql()` custom PK | `appendSafe(tableDef.pkName())` -- validated or hardcoded | None |

### Key Properties

- **Primary key names flow through SafeIdentifier**: `TableDef.primaryKey` is `SafeIdentifier?`, meaning custom PK names must pass `safeIdentifier()` validation at construction time. When null, `pkName()` returns the hardcoded `"id"`.
- **SqlDefault is a zero-input constant**: `formatTo()` appends the literal string `"DEFAULT"` -- no user data, interpolation, or runtime computation involved.
- **Virtual field exclusion shrinks attack surface**: Fields with `virtual == true` are skipped in INSERT column/value lists, UPDATE SET clauses, and non-nullable field checks.
- **Default values use sealed SqlPart pipeline**: `FieldDef.defaultValue` is typed as `SqlPart?`, flowing through the same type-safe rendering pipeline as all other values. Set at schema-definition time, not from user input.
- **timestamps() validates hardcoded names**: Even though `"inserted_at"` and `"updated_at"` are constants, they pass through `safeIdentifier()` for defense-in-depth.
- **Nullable narrowing correct throughout**: `pkName()` assigns `primaryKey` to local `pk` before null check. `toInsertSql()` assigns `f.defaultValue` to local `dv` before null check. Both follow the Temper idiom for nullable narrowing.

### Findings

| # | Severity | CWE | Finding |
|---|----------|-----|---------|
| P7-1 | None | CWE-89 | Primary key column names via `SafeIdentifier?` -- validated at construction or hardcoded `"id"`. No injection vector. |
| P7-2 | None | CWE-89 | `SqlDefault` renders hardcoded `"DEFAULT"` -- zero user-input surface. |
| P7-3 | None | CWE-89 | Default values flow through sealed `SqlPart` pipeline with per-type escaping. Set at schema time, not from user input. |
| P7-4 | None | CWE-20 | Custom PK names must pass `safeIdentifier()`. Empty strings bubble. SQL metacharacters rejected. |
| P7-5 | None | CWE-476 | All nullable fields (`primaryKey`, `defaultValue`) use local-variable narrowing. Temper enforces null checks at compile time. |
| P7-6 | None | CWE-125 | All array accesses in `toInsertSql`/`toUpdateSql` are loop-bounded. `valParts[0]` guarded by `length == 0` check. |

---

## Cumulative CWE Mapping

Updated assessment across all phases (Phases 1-7):

| Rank | CWE | Name | Status | Phase Impact |
|------|-----|------|--------|-------------|
| 1 | CWE-787 | Out-of-bounds Write | N/A | No change |
| 2 | CWE-79 | XSS | N/A | No change |
| 3 | CWE-89 | SQL Injection | **Mitigated** | Phases 1-5 add sealed interfaces with hardcoded keywords. Phase 6 adds no SQL paths. Phase 7 adds SqlDefault (hardcoded), PK via SafeIdentifier. |
| 4 | CWE-416 | Use After Free | N/A | No change |
| 5 | CWE-78 | OS Command Injection | N/A | No change |
| 6 | CWE-20 | Improper Input Validation | **Mitigated** | Phase 6 adds numeric range validation. All phases require SafeIdentifier. |
| 7 | CWE-125 | Out-of-bounds Read | N/A | No change |
| 8 | CWE-22 | Path Traversal | N/A | No change |
| 9 | CWE-352 | CSRF | N/A | No change |
| 10 | CWE-434 | File Upload | N/A | No change |
| 11 | CWE-862 | Missing Authorization | N/A | No change |
| 12 | CWE-476 | NULL Pointer Deref | **Partial** | Phase 5 adds 3 new nullable fields. Phase 7 adds 2 more (primaryKey, defaultValue). All use correct narrowing. |
| 13 | CWE-287 | Improper Authentication | N/A | No change |
| 14 | CWE-190 | Integer Overflow | **Partial** | Phase 4 rejects negative limit. No upper bound (ORM-6). |
| 15 | CWE-502 | Deserialization | N/A | No change |
| 16 | CWE-77 | Command Injection | N/A | No change |
| 17 | CWE-119 | Buffer Overflow | N/A | No change |
| 18 | CWE-798 | Hardcoded Credentials | N/A | No change |
| 19 | CWE-918 | SSRF | N/A | No change |
| 20 | CWE-306 | Missing Auth for Critical Func | N/A | No change |
| 21 | CWE-362 | Race Condition | N/A | All data structures remain immutable across all phases. |
| 22 | CWE-269 | Privilege Management | N/A | No change |
| 23 | CWE-94 | Code Injection | N/A | No change |
| 24 | CWE-863 | Incorrect Authorization | N/A | No change |
| 25 | CWE-276 | Default Permissions | N/A | No change |
| -- | CWE-400 | Resource Consumption | **Mitigated** | `safeToSql(defaultLimit)` enforces bounds. Set operations unbounded (P3-2). |
| -- | CWE-915 | Mass Assignment | **Mitigated** | Sealed Changeset preserved through Phase 6. |
| -- | CWE-284 | Access Control | **Mitigated** | Phase 4 adds no-WHERE guards for UPDATE/DELETE. |

**Summary:** 5 Mitigated, 2 Partial, 19 N/A. No Vulnerable ratings at the ORM level. Phase 7 introduces no new vulnerabilities.

## Test Coverage

| Phase | Tests Added | Total Tests | Description |
|-------|------------|-------------|-------------|
| Baseline | 64 | 64 | Core ORM, SQL builder, schema, changeset |
| Phase 1 | 21 | 85 | WHERE enrichment (OR, NULL, IN, NOT, BETWEEN, LIKE) |
| Phase 2 | 20 | 105 | Aggregation (GROUP BY, HAVING, DISTINCT, aggregates) |
| Phase 3 | 10 | 115 | Set operations (UNION, INTERSECT, EXCEPT, subqueries) |
| Phase 4 | 13 | 128 | Batch UPDATE/DELETE with no-WHERE guards |
| Phase 5 | 8 | 136 | NULLS FIRST/LAST, CROSS JOIN, row locking |
| Phase 6 | 34 | 170 | Changeset data manipulation and validation |
| Phase 7 | 14 | 184 | Schema enrichment: primaryKey, defaults, virtual, timestamps |
