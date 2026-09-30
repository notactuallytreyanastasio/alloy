# SqlBuilder tests

## String escaping

TODO Test for all dialects together?

    test("string escaping") {
      let build(name: String): String {
        sql"select * from hi where name = ${name}".toString()
      }
      let buildWrong(name: String): String {
        "select * from hi where name = '${name}'"
      }

Try an easy case and also little Bobby.

      assert(build("world") == "select * from hi where name = 'world'");
      let bobbyTables = "Robert'); drop table hi;--";
      assert(
        build(bobbyTables) ==
          "select * from hi where name = 'Robert''); drop table hi;--'"
      );

Also show why we care with a failed case.

      assert(
        buildWrong(bobbyTables) ==
          "select * from hi where name = 'Robert'); drop table hi;--'"
      );
    }

## String edge cases

We don't parse the SQL itself, so we can test subexpressions without worrying
context.

Note that we don't have the ability to compose SQL syntax itself in these
templates.

    test("string edge cases") {
      assert(sql"v = ${""}".toString() == "v = ''");
      assert(sql"v = ${"a''b"}".toString() == "v = 'a''''b'");
      assert(sql"v = ${"Hello 世界"}".toString() == "v = 'Hello 世界'");

TODO Which databases allow for multiline strings? Seems sqlite does:

```sql
sqlite> select 'line 1
'  ...> line 2';
line 1
line 2
sqlite>
```

      assert(sql"v = ${"Line1\nLine2"}".toString() == "v = 'Line1\nLine2'");
    }

## Numbers and Booleans

    test("numbers and booleans") {
      assert(
        sql"select ${42}, ${43i64}, ${19.99}, ${true}, ${false}".toString() ==
          "select 42, 43, 19.99, TRUE, FALSE"
      );
      let date = new Date(2024, 12, 25) orelse panic();
      assert(
        sql"insert into t values (${date})".toString() ==
          "insert into t values ('2024-12-25')"
      );
    }

## Lists

Lists go in comma-separated, with each element escaped as appropriate.

TODO If contextual, we could put parens around automatically when needed.

    test("lists") {
      assert(
        sql"v IN (${["a", "b", "c'd"]})".toString() == "v IN ('a', 'b', 'c''d')"
      );
      assert(sql"v IN (${[1, 2, 3]})".toString() == "v IN (1, 2, 3)");
      assert(sql"v IN (${[1i64, 2i64]})".toString() == "v IN (1, 2)");
      assert(sql"v IN (${[1.0, 2.0]})".toString() == "v IN (1.0, 2.0)");
      assert(sql"v IN (${[true, false]})".toString() == "v IN (TRUE, FALSE)");
      let dates = [
        new Date(2024, 1, 1) orelse panic(),
        new Date(2024, 12, 25) orelse panic(),
      ];
      assert(
        sql"v IN (${dates})".toString() == "v IN ('2024-01-01', '2024-12-25')"
      );
    }

## Float64 edge cases

    test("SqlFloat64 NaN renders as NULL") {
      let nan = NaN;
      assert(sql"v = ${nan}".toString() == "v = NULL");
    }

    test("SqlFloat64 Infinity renders as NULL") {
      let inf = Infinity;
      assert(sql"v = ${inf}".toString() == "v = NULL");
    }

    test("SqlFloat64 negative Infinity renders as NULL") {
      let ninf = -Infinity;
      assert(sql"v = ${ninf}".toString() == "v = NULL");
    }

    test("SqlFloat64 normal values still work") {
      assert(sql"v = ${3.14}".toString() == "v = 3.14");
      assert(sql"v = ${0.0}".toString() == "v = 0.0");
      assert(sql"v = ${-42.5}".toString() == "v = -42.5");
    }

## Date escaping

    test("SqlDate renders with quotes") {
      let d = new Date(2024, 6, 15) orelse panic();
      assert(sql"v = ${d}".toString() == "v = '2024-06-15'");
    }

## Nesting

Put already escaped SQL into another SQL fragment.

    test("nesting") {
      let name = "Someone";
      let condition = sql"where p.last_name = ${name}";

First check adding expanded semi-structured fragment content.

      assert(
        sql"select p.id from person p ${condition}".toString() ==
          "select p.id from person p where p.last_name = 'Someone'"
      );

Also check adding content frozen to SQL source.

      assert(
        sql"select p.id from person p ${condition.toSource()}".toString() ==
          "select p.id from person p where p.last_name = 'Someone'"
      );

We can also append individual parts.

      let parts: List<SqlPart> = [new SqlString("a'b"), new SqlInt32(3)];
      assert(sql"select ${parts}".toString() == "select 'a''b', 3");
    }

## Audit Phase 4: New tests from coverage/test/complexity audits

    test("SqlInt32 negative and zero values") {
      assert(sql"v = ${-42}".toString() == "v = -42") { "negative int" };
      assert(sql"v = ${0}".toString() == "v = 0") { "zero int" };
    }

    test("SqlInt64 negative value") {
      assert(sql"v = ${-99i64}".toString() == "v = -99") { "negative int64" };
    }

    test("single element list rendering") {
      assert(sql"v IN (${[42]})".toString() == "v IN (42)") { "single int" };
      assert(sql"v IN (${["only"]})".toString() == "v IN ('only')") { "single string" };
    }

    test("SqlDefault renders DEFAULT keyword") {
      let b = new SqlBuilder();
      b.appendSafe("v = ");
      b.appendPart(new SqlDefault());
      assert(b.accumulated.toString() == "v = DEFAULT") { "default keyword" };
    }

    test("SqlString with backslash") {
      assert(sql"v = ${"a\\b"}".toString() == "v = 'a\\b'") { "backslash passthrough" };
    }

## Parameterized

`toParameterized` keeps each value out of the text: a placeholder goes where
it was, and the value goes into `params`, unescaped, because a driver that
binds it never parses it as SQL.

    test("toParameterized numbers the values and keeps them out of the text") {
      let name = "O'Brien; drop table people";
      let p = sql"select * from people where name = ${name} and age > ${30} and height < ${1.5}".toParameterized();
      assert(p.text == "select * from people where name = $1 and age > $2 and height < $3") { p.text };
      assert(p.params.length == 3) { "three params" };
      assert(p.params[0] == "O'Brien; drop table people") { p.params[0] };
      assert(p.params[1] == "30") { p.params[1] };
      assert(p.params[2] == "1.5") { p.params[2] };
    }

    test("toParameterized leaves what is not data in the text") {
      let b = new SqlBuilder();
      b.appendSafe("insert into t (a, b, c, d) values (");
      b.appendBoolean(true);
      b.appendSafe(", ");
      b.appendPart(new SqlDefault());
      b.appendSafe(", ");
      b.appendFloat64(NaN);
      b.appendSafe(", ");
      b.appendInt64(-7i64);
      b.appendSafe(")");
      let p = b.accumulated.toParameterized();
      assert(p.text == "insert into t (a, b, c, d) values (TRUE, DEFAULT, NULL, $1)") { p.text };
      assert(p.params.length == 1 && p.params[0] == "-7") { "one param" };
    }

    test("toParameterized works on a whole query") {
      let p = from(safeIdentifier("users") orelse panic())
        .where(sql"email = ${"a@b.c"}")
        .orWhere(sql"id = ${7}")
        .toSql()
        .toParameterized();
      assert(p.text == "SELECT * FROM users WHERE email = $1 OR id = $2") { p.text };
      assert(p.params[0] == "a@b.c" && p.params[1] == "7") { "params in order" };
    }

    test("toParameterized with no values is the same text as toString") {
      let f = sql"select 1";
      assert(f.toParameterized().text == f.toString());
      assert(f.toParameterized().params.length == 0);
    }
