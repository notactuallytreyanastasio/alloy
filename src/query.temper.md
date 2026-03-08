# Query

Composable, immutable SELECT query builder.

## Security model

- `tableName`, `selectedFields`, and `orderBy` fields all require
  `SafeIdentifier` — validated against `[a-zA-Z_][a-zA-Z0-9_]*` before
  they can be passed here. There is no path for a raw user string to reach
  `appendSafe` except through a `SafeIdentifier`.
- `appendSafe` is only ever called with: (a) hardcoded SQL keyword string
  literals, or (b) `safeIdentifier.sqlValue`. Never with runtime arbitrary
  strings.
- User values only enter SQL via `SqlFragment` conditions already built
  with the `sql` tag. The `where()` method takes a `SqlFragment`, not a
  raw `String`.
- `safeToSql(defaultLimit)` is provided as the production-safe variant
  that always applies an upper bound on result set size (CWE-400).

## Imports

    let { SqlFragment, SqlBuilder, sql } = import("./sql/builder");
    let { SafeIdentifier } = import("./schema");

## OrderClause

    export class OrderClause(
      public field: SafeIdentifier,
      public ascending: Boolean,
    ) {}

## Query

    export class Query(
      public tableName: SafeIdentifier,
      public conditions: List<SqlFragment>,
      public selectedFields: List<SafeIdentifier>,
      public orderClauses: List<OrderClause>,
      public limitVal: Int?,
      public offsetVal: Int?,
    ) {

      // where: condition must be a SqlFragment built via the sql tag
      public where(condition: SqlFragment): Query {
        let nb = conditions.toListBuilder();
        nb.add(condition);
        new Query(tableName, nb.toList(), selectedFields, orderClauses, limitVal, offsetVal)
      }

      // select: field names must be SafeIdentifier values
      public select(fields: List<SafeIdentifier>): Query {
        new Query(tableName, conditions, fields, orderClauses, limitVal, offsetVal)
      }

      // orderBy
      public orderBy(field: SafeIdentifier, ascending: Boolean): Query {
        let nb = orderClauses.toListBuilder();
        nb.add(new OrderClause(field, ascending));
        new Query(tableName, conditions, selectedFields, nb.toList(), limitVal, offsetVal)
      }

      // limit: bubbles on negative values
      public limit(n: Int): Query throws Bubble {
        if (n < 0) { bubble() }
        new Query(tableName, conditions, selectedFields, orderClauses, n, offsetVal)
      }

      // offset: bubbles on negative values
      public offset(n: Int): Query throws Bubble {
        if (n < 0) { bubble() }
        new Query(tableName, conditions, selectedFields, orderClauses, limitVal, n)
      }

      // toSql: assembles the final SqlFragment
      public toSql(): SqlFragment {
        let b = new SqlBuilder();

        b.appendSafe("SELECT ");
        if (selectedFields.isEmpty) {
          b.appendSafe("*");
        } else {
          b.appendSafe(selectedFields.join(", ") { f => f.sqlValue });
        }

        b.appendSafe(" FROM ");
        b.appendSafe(tableName.sqlValue);

        if (!conditions.isEmpty) {
          b.appendSafe(" WHERE ");
          b.appendFragment(conditions[0]);
          for (var i = 1; i < conditions.length; ++i) {
            b.appendSafe(" AND ");
            b.appendFragment(conditions[i]);
          }
        }

        if (!orderClauses.isEmpty) {
          b.appendSafe(" ORDER BY ");
          var first = true;
          for (let oc of orderClauses) {
            if (!first) { b.appendSafe(", "); }
            first = false;
            b.appendSafe(oc.field.sqlValue);
            b.appendSafe(if (oc.ascending) { " ASC" } else { " DESC" });
          }
        }

        if (limitVal != null) {
          b.appendSafe(" LIMIT ");
          b.appendInt32(limitVal);
        }
        if (offsetVal != null) {
          b.appendSafe(" OFFSET ");
          b.appendInt32(offsetVal);
        }

        b.accumulated
      }

      // safeToSql: production-safe variant, applies defaultLimit if none set (CWE-400)
      public safeToSql(defaultLimit: Int): SqlFragment throws Bubble {
        if (defaultLimit < 0) { bubble() }
        if (limitVal != null) { toSql() } else { this.limit(defaultLimit).toSql() }
      }

    }

## from

Entry point. `tableName` must be a `SafeIdentifier`.

    export let from(tableName: SafeIdentifier): Query {
      new Query(tableName, [], [], [], null, null)
    }
