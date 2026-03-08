# Schema

Defines the structure of a database table: its name and typed columns.

## Imports

    let { Date } = import("std/temporal");

## SafeIdentifier

An SQL identifier (table or column name) that has been validated against
`[a-zA-Z_][a-zA-Z0-9_]*`. This is the ONLY way a name reaches
`appendSafe` at runtime — the `ValidatedIdentifier` implementation class
is not exported, so external code cannot instantiate one without going
through `safeIdentifier()`.

    export sealed interface SafeIdentifier {
      public get sqlValue(): String;
    }

The private implementation. Not exported — cannot be constructed outside
this module.

    class ValidatedIdentifier(private _value: String) extends SafeIdentifier {
      public get sqlValue(): String { _value }
    }

Character classification helpers.

    let isIdentStart(c: Int): Boolean {
      (c >= char'a' && c <= char'z') ||
      (c >= char'A' && c <= char'Z') ||
      c == char'_'
    }

    let isIdentPart(c: Int): Boolean {
      isIdentStart(c) || (c >= char'0' && c <= char'9')
    }

### safeIdentifier

The sole constructor of `SafeIdentifier`. Bubbles on any character outside
`[a-zA-Z_][a-zA-Z0-9_]*`, including spaces, semicolons, quotes, dashes,
dots, and parentheses — the full set of SQL metacharacters.

    export let safeIdentifier(name: String): SafeIdentifier throws Bubble {
      if (name.isEmpty) { bubble() }
      var idx = String.begin;
      if (!isIdentStart(name[idx])) { bubble() }
      idx = name.next(idx);
      while (name.hasIndex(idx)) {
        if (!isIdentPart(name[idx])) { bubble() }
        idx = name.next(idx);
      }
      new ValidatedIdentifier(name)
    }

## FieldType

A sealed union of all supported column types. Adding a new variant forces
a compile error in every exhaustive `when` that handles `FieldType`,
making it impossible to forget to update the SQL escaping logic.

    export sealed interface FieldType {}

    export class StringField() extends FieldType {}
    export class IntField() extends FieldType {}
    export class Int64Field() extends FieldType {}
    export class FloatField() extends FieldType {}
    export class BoolField() extends FieldType {}
    export class DateField() extends FieldType {}

## FieldDef

A single column definition. `name` is a `SafeIdentifier` so it is
validated before it can be used anywhere in SQL construction.

    export class FieldDef(
      public name: SafeIdentifier,
      public fieldType: FieldType,
      public nullable: Boolean,
    ) {}

## TableDef

Describes a full table: its SQL name and ordered list of columns.

    export class TableDef(
      public tableName: SafeIdentifier,
      public fields: List<FieldDef>,
    ) {

      // field: look up a FieldDef by name, used for type dispatch. Bubbles if not found.
      public field(name: String): FieldDef throws Bubble {
        for (let f of fields) {
          if (f.name.sqlValue == name) { return f; }
        }
        bubble()
      }

    }
