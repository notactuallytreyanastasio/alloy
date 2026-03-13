# Plan: Phase 7 — Schema Enrichment

## Goal

Extend the schema layer with Ecto-equivalent features: configurable primary keys,
default column values, virtual (computed) fields, and a `timestamps()` convenience
helper. These are the foundational schema features that every Ecto application relies on.

## Ecto Equivalents

| Temper Feature | Ecto Equivalent |
|---|---|
| `TableDef.primaryKey` | `@primary_key {:id, :integer, autogenerate: true}` |
| `TableDef.pkName()` | Used internally by `Repo.update/delete` |
| `FieldDef.defaultValue` | `field :status, :string, default: "draft"` |
| `FieldDef.virtual` | `field :full_name, :string, virtual: true` |
| `SqlDefault` | Renders literal `DEFAULT` keyword |
| `timestamps()` | `timestamps()` macro in Ecto schemas |

## Design Decisions

### 1. Primary Key as SafeIdentifier?

The `primaryKey` field on `TableDef` is `SafeIdentifier?` (nullable). When null,
`pkName()` returns `"id"` — matching Ecto's default. This avoids a breaking change
for tables that use the standard `id` convention while allowing custom PKs like
`post_id` or `uuid`.

**Why SafeIdentifier?**: The PK column name goes directly into `appendSafe()` calls
in `toUpdateSql()` and `deleteSql()`. Using `SafeIdentifier` ensures it's validated
at construction time — no SQL injection possible through the PK column name.

### 2. Default Values as SqlPart?

`defaultValue` is typed as `SqlPart?` rather than `String?`. This means defaults
are rendered through the same type-safe SQL generation pipeline as all other values.
The `SqlDefault` class renders the literal `DEFAULT` keyword, which tells the
database to use its own column default (e.g., `NOW()` for timestamps).

**Why not String?**: A string default would need to go through `valueToSqlPart()`
conversion, but `DEFAULT` is a SQL keyword, not a value. Using `SqlPart` directly
allows both literal defaults and keyword defaults.

### 3. Virtual Fields

Virtual fields are excluded from both INSERT and UPDATE SQL generation. They are
also excluded from the non-nullable field check in `toInsertSql()` — a non-nullable
virtual field does not require a value since it won't appear in the SQL.

**Use case**: Computed columns (e.g., `full_name` derived from `first_name` and
`last_name`) that exist in the application schema but not in the database.

### 4. Breaking Changes

- `FieldDef` grows from 3 to 5 parameters: `(name, fieldType, nullable, defaultValue, virtual)`
- `TableDef` grows from 2 to 3 parameters: `(tableName, fields, primaryKey)`
- All existing constructor calls updated with `null, false` / `, null` respectively

## Security Analysis

- **Primary key column names**: Flow through `SafeIdentifier` → validated at construction
- **Default values**: Flow through `SqlPart` → type-safe rendering (no raw strings)
- **SqlDefault**: Renders hardcoded `"DEFAULT"` string — no user input involved
- **Virtual field exclusion**: Reduces attack surface by omitting fields from SQL entirely
- **timestamps()**: Calls `safeIdentifier()` with hardcoded strings — validated at call time

## Tests Added (15 total)

### schema_test.temper.md (5 tests)
1. pkName defaults to "id" when primaryKey is null
2. pkName returns custom primary key
3. timestamps() returns two DateField defs with defaults
4. FieldDef defaultValue field
5. FieldDef virtual flag

### changeset_test.temper.md (10 tests)
6. toInsertSql uses default value when field not in changes
7. toInsertSql change overrides default value
8. toInsertSql with timestamps uses DEFAULT
9. toInsertSql skips virtual fields
10. toInsertSql allows missing non-nullable virtual field
11. toUpdateSql skips virtual fields
12. toUpdateSql uses custom primary key
13. deleteSql uses custom primary key
14. deleteSql uses default id when primaryKey null
15. toUpdateSql with virtual-only changes bubbles (implicit in skip test)
