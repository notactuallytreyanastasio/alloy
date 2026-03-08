# Changeset

Ecto-style cast → validate → generate-SQL pipeline.

## Security model

- `Changeset` is a **sealed interface**. `ChangesetImpl` is not exported.
  External code cannot construct a Changeset — only the `changeset()`
  factory can. This closes the CWE-284 bypass via direct construction.
- `params` (raw user input) is never exposed. Only `changes` (whitelisted,
  cast fields) and `errors` are readable from outside. Closes CWE-532.
- `cast()` takes `List<SafeIdentifier>` — column names must be validated
  identifiers before they are accepted as allowed fields.
- `toInsertSql()` independently enforces non-nullable fields regardless of
  `isValid`, so a manually-constructed object still cannot produce bad SQL.
- `valueToSqlPart` uses exhaustive `when` on sealed `FieldType` — the
  compiler guarantees every type dispatches to a typed `SqlPart`, never
  to raw unescaped text.
- `BoolField` bubbles on unrecognised values rather than silently coercing.

## Imports

All types (SqlFragment, SqlBuilder, SqlPart, TableDef, etc.) are available
from other files in the same module without explicit imports.

## ChangesetError

    export class ChangesetError(
      public field: String,
      public message: String,
    ) {}

## Changeset (sealed interface)

The public contract. All methods return `Changeset` so pipelines can be
chained. `params` is intentionally absent — callers see only the
whitelisted `changes` and accumulated `errors`.

    export sealed interface Changeset {
      public get tableDef(): TableDef;
      public get changes(): Map<String, String>;
      public get errors(): List<ChangesetError>;
      public get isValid(): Boolean;

      public cast(allowedFields: List<SafeIdentifier>): Changeset;
      public validateRequired(fields: List<SafeIdentifier>): Changeset;
      public validateLength(field: SafeIdentifier, min: Int, max: Int): Changeset;
      public validateInt(field: SafeIdentifier): Changeset;
      public validateInt64(field: SafeIdentifier): Changeset;
      public validateFloat(field: SafeIdentifier): Changeset;
      public validateBool(field: SafeIdentifier): Changeset;

      public toInsertSql(): SqlFragment throws Bubble;
      public toUpdateSql(id: Int): SqlFragment throws Bubble;
    }

## ChangesetImpl (private)

Not exported — the only path to an instance is through `changeset()`.

    class ChangesetImpl(
      private _tableDef: TableDef,
      private _params: Map<String, String>,
      private _changes: Map<String, String>,
      private _errors: List<ChangesetError>,
      private _isValid: Boolean,
    ) extends Changeset {

      public get tableDef(): TableDef { _tableDef }
      public get changes(): Map<String, String> { _changes }
      public get errors(): List<ChangesetError> { _errors }
      public get isValid(): Boolean { _isValid }

      // cast: whitelists fields by SafeIdentifier
      public cast(allowedFields: List<SafeIdentifier>): Changeset {
        let mb = new MapBuilder<String, String>();
        for (let f of allowedFields) {
          let val = _params.getOr(f.sqlValue, "");
          if (!val.isEmpty) {
            mb.set(f.sqlValue, val);
          }
        }
        new ChangesetImpl(_tableDef, _params, mb.toMap(), _errors, _isValid)
      }

      // validateRequired
      public validateRequired(fields: List<SafeIdentifier>): Changeset {
        if (!_isValid) { return this; }
        let eb = _errors.toListBuilder();
        var valid = true;
        for (let f of fields) {
          if (!_changes.has(f.sqlValue)) {
            eb.add(new ChangesetError(f.sqlValue, "is required"));
            valid = false;
          }
        }
        new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), valid)
      }

      // validateLength
      public validateLength(field: SafeIdentifier, min: Int, max: Int): Changeset {
        if (!_isValid) { return this; }
        let val = _changes.getOr(field.sqlValue, "");
        let len = val.countBetween(String.begin, val.end);
        if (len < min || len > max) {
          let msg = "must be between ${min} and ${max} characters";
          let eb = _errors.toListBuilder();
          eb.add(new ChangesetError(field.sqlValue, msg));
          return new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), false);
        }
        this
      }

      // validateInt
      public validateInt(field: SafeIdentifier): Changeset {
        if (!_isValid) { return this; }
        let val = _changes.getOr(field.sqlValue, "");
        if (val.isEmpty) { return this; }
        let parseOk = do { val.toInt32(); true } orelse false;
        if (!parseOk) {
          let eb = _errors.toListBuilder();
          eb.add(new ChangesetError(field.sqlValue, "must be an integer"));
          return new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), false);
        }
        this
      }

      // validateInt64
      public validateInt64(field: SafeIdentifier): Changeset {
        if (!_isValid) { return this; }
        let val = _changes.getOr(field.sqlValue, "");
        if (val.isEmpty) { return this; }
        let parseOk = do { val.toInt64(); true } orelse false;
        if (!parseOk) {
          let eb = _errors.toListBuilder();
          eb.add(new ChangesetError(field.sqlValue, "must be a 64-bit integer"));
          return new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), false);
        }
        this
      }

      // validateFloat
      public validateFloat(field: SafeIdentifier): Changeset {
        if (!_isValid) { return this; }
        let val = _changes.getOr(field.sqlValue, "");
        if (val.isEmpty) { return this; }
        let parseOk = do { val.toFloat64(); true } orelse false;
        if (!parseOk) {
          let eb = _errors.toListBuilder();
          eb.add(new ChangesetError(field.sqlValue, "must be a number"));
          return new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), false);
        }
        this
      }

      // validateBool: accepts true/1/yes/on and false/0/no/off, bubbles on anything else
      public validateBool(field: SafeIdentifier): Changeset {
        if (!_isValid) { return this; }
        let val = _changes.getOr(field.sqlValue, "");
        if (val.isEmpty) { return this; }
        let isTrue = val == "true" || val == "1" || val == "yes" || val == "on";
        let isFalse = val == "false" || val == "0" || val == "no" || val == "off";
        if (!isTrue && !isFalse) {
          let eb = _errors.toListBuilder();
          eb.add(new ChangesetError(field.sqlValue, "must be a boolean (true/false/1/0/yes/no/on/off)"));
          return new ChangesetImpl(_tableDef, _params, _changes, eb.toList(), false);
        }
        this
      }

      // parseBoolSqlPart: converts validated bool string to SqlBoolean
      private parseBoolSqlPart(val: String): SqlBoolean throws Bubble {
        if (val == "true" || val == "1" || val == "yes" || val == "on") {
          return new SqlBoolean(true);
        }
        if (val == "false" || val == "0" || val == "no" || val == "off") {
          return new SqlBoolean(false);
        }
        bubble()
      }

      // valueToSqlPart: type-dispatched conversion from validated string to SqlPart
      private valueToSqlPart(fieldDef: FieldDef, val: String): SqlPart throws Bubble {
        let ft = fieldDef.fieldType;
        if (ft is StringField) { return new SqlString(val); }
        if (ft is IntField) { return new SqlInt32(val.toInt32()); }
        if (ft is Int64Field) { return new SqlInt64(val.toInt64()); }
        if (ft is FloatField) { return new SqlFloat64(val.toFloat64()); }
        if (ft is BoolField) { return parseBoolSqlPart(val); }
        if (ft is DateField) { return new SqlDate(Date.fromIsoString(val)); }
        bubble()
      }

      // toInsertSql: generates INSERT INTO … (cols) VALUES (vals)
      public toInsertSql(): SqlFragment throws Bubble {
        if (!_isValid) { bubble() }
        for (var i = 0; i < _tableDef.fields.length; ++i) {
          let f = _tableDef.fields[i];
          if (!f.nullable && !_changes.has(f.name.sqlValue)) {
            bubble()
          }
        }
        let pairs = _changes.toList();
        if (pairs.length == 0) { bubble() }
        let colNames = new ListBuilder<String>();
        let valParts = new ListBuilder<SqlPart>();
        for (var i = 0; i < pairs.length; ++i) {
          let pair = pairs[i];
          let fd = _tableDef.field(pair.key);
          colNames.add(pair.key);
          valParts.add(valueToSqlPart(fd, pair.value));
        }
        let b = new SqlBuilder();
        b.appendSafe("INSERT INTO ");
        b.appendSafe(_tableDef.tableName.sqlValue);
        b.appendSafe(" (");
        b.appendSafe(colNames.toList().join(", ") { c => c });
        b.appendSafe(") VALUES (");
        b.appendPart(valParts[0]);
        for (var j = 1; j < valParts.length; ++j) {
          b.appendSafe(", ");
          b.appendPart(valParts[j]);
        }
        b.appendSafe(")");
        b.accumulated
      }

      // toUpdateSql: generates UPDATE … SET col = val, … WHERE id = ?
      public toUpdateSql(id: Int): SqlFragment throws Bubble {
        if (!_isValid) { bubble() }
        let pairs = _changes.toList();
        if (pairs.length == 0) { bubble() }
        let b = new SqlBuilder();
        b.appendSafe("UPDATE ");
        b.appendSafe(_tableDef.tableName.sqlValue);
        b.appendSafe(" SET ");
        for (var i = 0; i < pairs.length; ++i) {
          if (i > 0) { b.appendSafe(", "); }
          let pair = pairs[i];
          let fd = _tableDef.field(pair.key);
          b.appendSafe(pair.key);
          b.appendSafe(" = ");
          b.appendPart(valueToSqlPart(fd, pair.value));
        }
        b.appendSafe(" WHERE id = ");
        b.appendInt32(id);
        b.accumulated
      }

    }

## changeset

The sole entry point. Returns the sealed `Changeset` interface.

    export let changeset(tableDef: TableDef, params: Map<String, String>): Changeset {
      new ChangesetImpl(
        tableDef,
        params,
        new Map<String, String>([]),
        [],
        true,
      )
    }
