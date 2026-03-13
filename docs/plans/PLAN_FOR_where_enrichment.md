# Plan: Phase 1 — WHERE Clause Enrichment

## Design Rationale

### WhereClause Sealed Interface

The current `Query.conditions` is `List<SqlFragment>` — all conditions are AND-joined.
To support OR, we introduce a `WhereClause` sealed interface with two implementations:

- `AndCondition(condition: SqlFragment)` — renders as `AND condition`
- `OrCondition(condition: SqlFragment)` — renders as `OR condition`

The first condition is always rendered bare (no conjunction keyword). Subsequent
conditions are prefixed with their `keyword()` return value.

**Why sealed interface?** Same pattern as `JoinType` — hardcoded keyword strings,
compiler-enforced exhaustive dispatch, no user input reaches the keyword.

### Convenience Methods

All new methods (`whereNull`, `whereNotNull`, `whereIn`, `whereNot`,
`whereBetween`, `whereLike`, `whereILike`) build an `SqlFragment` internally
and delegate to `this.where()`. This ensures:

1. Field names go through `SafeIdentifier.sqlValue` → `appendSafe` (validated)
2. SQL keywords are hardcoded string literals → `appendSafe` (known-safe)
3. User values go through `SqlPart`/`SqlString` escaping (type-dispatched)
4. No new SQL injection surface is created

### Empty IN List

`whereIn` with an empty list produces `1 = 0` (always false) rather than
invalid SQL. This matches Ecto's behavior and prevents the degenerate case
of `field IN ()` which is a SQL syntax error.

## Ecto Equivalences

| Temper Method | Ecto Equivalent |
|---------------|-----------------|
| `where(frag)` | `Ecto.Query.where/3` |
| `orWhere(frag)` | `Ecto.Query.or_where/3` |
| `whereNull(field)` | `where(q, [r], is_nil(r.field))` |
| `whereNotNull(field)` | `where(q, [r], not is_nil(r.field))` |
| `whereIn(field, vals)` | `where(q, [r], r.field in ^vals)` |
| `whereNot(cond)` | `where(q, [r], not(^cond))` |
| `whereBetween(f, lo, hi)` | `where(q, [r], r.f >= ^lo and r.f <= ^hi)` |
| `whereLike(f, pat)` | `where(q, [r], like(r.f, ^pat))` |
| `whereILike(f, pat)` | `where(q, [r], ilike(r.f, ^pat))` |

## Security Analysis

- No new `appendSafe` calls use runtime user strings
- All field names require `SafeIdentifier` (validated at construction)
- LIKE/ILIKE patterns go through `SqlString` escaping (single-quote doubling)
- `WhereClause.keyword()` returns hardcoded strings only
- IN values are `List<SqlPart>` — each element is type-dispatched to proper escaping

## New Types

1. `WhereClause` — sealed interface with `condition` getter and `keyword()` method
2. `AndCondition` — implements WhereClause, keyword = "AND"
3. `OrCondition` — implements WhereClause, keyword = "OR"

## New Methods on Query

1. `orWhere(condition: SqlFragment): Query`
2. `whereNull(field: SafeIdentifier): Query`
3. `whereNotNull(field: SafeIdentifier): Query`
4. `whereIn(field: SafeIdentifier, values: List<SqlPart>): Query`
5. `whereNot(condition: SqlFragment): Query`
6. `whereBetween(field: SafeIdentifier, low: SqlPart, high: SqlPart): Query`
7. `whereLike(field: SafeIdentifier, pattern: String): Query`
8. `whereILike(field: SafeIdentifier, pattern: String): Query`

## Breaking Changes

- `Query.conditions` type changes from `List<SqlFragment>` to `List<WhereClause>`
- All existing `where()` calls still work (they now wrap in `AndCondition` internally)
- No external API breaks — the `where()` method signature is unchanged
