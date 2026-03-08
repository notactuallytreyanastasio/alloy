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
