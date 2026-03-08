# SQL Data Model

We build an abstract model that can be rendered to different dialects.

## SqlFragment

The fragment class supports semi-structured raw SQL text and data values, which
then can be escaped differently for different dbs. And while called a
"fragment", an instance can also represent a full statement.

    export class SqlFragment(
      public parts: List<SqlPart>,
    ) {

### toSource

Freeze this to string source content marked as safe SQL.

TODO Make different forms for different dialects.

      public toSource(): SqlSource {
        new SqlSource(toString())
      }

### toString

TODO Make different forms for different dialects.

      public toString(): String {
        let builder = new StringBuilder();
        for (var i = 0; i < parts.length; ++i) {
          parts[i].formatTo(builder);
        }
        builder.toString()
      }

    }

## SqlPart

Each part of a SQL fragment is either raw known-safe SQL source or else a value
needing escaped and/or represented properly for a particular DB dialect.

TODO If we represent SQL syntax in a structured way, we could perhaps do more.

    export sealed interface SqlPart {

### formatTo

Enables using a single StringBuilder across multiple parts for efficiency.

TODO Different dialects.

      public formatTo(builder: StringBuilder): Void;

    }

### SqlSource

`SqlSource` represents known-safe SQL source code that doesn't need escaped. This
often originates from the raw string content in `sql`-tagged strings. For
example, in `sql"select p.name from person p where p.id = ${id}"`, all except
the `${id}` interpolation becomes a `SqlSource` instance.

    export class SqlSource(public source: String) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append(source);
      }

    }

### SqlBoolean

    export class SqlBoolean(public value: Boolean) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append(if (value) { "TRUE" } else { "FALSE" });
      }

    }

### SqlDate

    export class SqlDate(public value: Date) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append("'");
        builder.append(value.toString());
        builder.append("'");
      }

    }

### SqlFloat64

    export class SqlFloat64(public value: Float64) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append(value.toString());
      }

    }

### SqlInt32

    export class SqlInt32(public value: Int32) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append(value.toString());
      }

    }

### SqlInt64

    export class SqlInt64(public value: Int64) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append(value.toString());
      }

    }

### SqlString

`SqlString` represents text data that needs escaped.

    export class SqlString(public value: String) extends SqlPart {

### formatTo

      public formatTo(builder: StringBuilder): Void {
        builder.append("'");
        for (let c of value) {
          if (c == char'\'') {
            builder.append("''");
          } else {
            builder.appendCodePoint(c) orelse panic();
          }
        }
        builder.append("'");
      }

    }
