# Plan: Phase 2 — Aggregation

## Design Rationale

### Aggregate Functions as Free Functions

Aggregate functions (`countAll`, `countCol`, `sumCol`, `avgCol`, `minCol`, `maxCol`)
are free functions returning `SqlFragment` rather than methods on Query. This matches
how SQL aggregates work — they produce expressions that can appear in SELECT, HAVING,
or anywhere else an expression is valid.

Each function uses `appendSafe` exclusively: the function name (`COUNT`, `SUM`, etc.)
is a hardcoded string literal, and the field name comes from `SafeIdentifier.sqlValue`.

### selectExpr for Aggregate Selects

The existing `select()` only takes `List<SafeIdentifier>` (column names). For
aggregate queries like `SELECT COUNT(*), name`, we need `selectExpr()` which takes
`List<SqlFragment>`. When `selectExprs` is non-empty, `toSql()` renders those
instead of `selectedFields`.

### GROUP BY and HAVING

GROUP BY takes `List<SafeIdentifier>` fields. HAVING reuses the `WhereClause` type
from Phase 1, enabling mixed AND/OR logic in HAVING clauses just like WHERE.

### DISTINCT

Simple boolean flag on Query. `SELECT DISTINCT` when true.

### countSql

A convenience method that produces `SELECT COUNT(*) FROM table WHERE ...` by
stripping SELECT columns, ORDER BY, LIMIT, and OFFSET from the query.

## Ecto Equivalences

| Temper | Ecto |
|--------|------|
| `countAll()` | `count()` |
| `countCol(field)` | `count(r.field)` |
| `sumCol(field)` | `sum(r.field)` |
| `avgCol(field)` | `avg(r.field)` |
| `minCol(field)` | `min(r.field)` |
| `maxCol(field)` | `max(r.field)` |
| `selectExpr(exprs)` | `select(q, [r], {count(r.id), r.name})` |
| `groupBy(field)` | `group_by(q, [r], r.field)` |
| `having(cond)` | `having(q, [r], count(r.id) > 5)` |
| `distinct()` | `distinct(q, true)` |

## Breaking Changes

- Query constructor grows from 7 to 11 params (adds groupByFields, havingConditions,
  isDistinct, selectExprs)
- All existing code constructing Query directly needs updating
- `from()` factory updated to pass empty defaults for new params
