# Changeset Tests

## Helpers

    let csid(name: String): SafeIdentifier {
      safeIdentifier(name) orelse panic()
    }

    let userTable(): TableDef {
      new TableDef(csid("users"), [
        new FieldDef(csid("name"),   new StringField(), false),
        new FieldDef(csid("email"),  new StringField(), false),
        new FieldDef(csid("age"),    new IntField(),    true),
        new FieldDef(csid("score"),  new FloatField(),  true),
        new FieldDef(csid("active"), new BoolField(),   true),
      ])
    }

## cast

    test("cast whitelists allowed fields") {
      let params = new Map<String, String>([
        new Pair("name", "Alice"),
        new Pair("email", "alice@example.com"),
        new Pair("admin", "true"),
      ]);
      let cs = changeset(userTable(), params).cast([csid("name"), csid("email")]);
      assert(cs.changes.has("name"))   { "name should be in changes" };
      assert(cs.changes.has("email"))  { "email should be in changes" };
      assert(!cs.changes.has("admin")) { "admin must be dropped (not in whitelist)" };
      assert(cs.isValid)               { "should still be valid" };
    }

    test("cast is replacing not additive — second call resets whitelist") {
      let params = new Map<String, String>([
        new Pair("name", "Alice"),
        new Pair("email", "alice@example.com"),
      ]);
      // First cast admits name; second cast admits only email — name must be gone
      let cs = changeset(userTable(), params)
        .cast([csid("name")])
        .cast([csid("email")]);
      assert(!cs.changes.has("name"))  { "name must be excluded by second cast" };
      assert(cs.changes.has("email"))  { "email should be present" };
    }

    test("cast ignores empty string values") {
      let params = new Map<String, String>([
        new Pair("name", ""),
        new Pair("email", "bob@example.com"),
      ]);
      let cs = changeset(userTable(), params).cast([csid("name"), csid("email")]);
      assert(!cs.changes.has("name")) { "empty name should not be in changes" };
      assert(cs.changes.has("email")) { "email should be in changes" };
    }

## validateRequired

    test("validateRequired passes when field present") {
      let params = new Map<String, String>([new Pair("name", "Alice")]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateRequired([csid("name")]);
      assert(cs.isValid)            { "should be valid" };
      assert(cs.errors.length == 0) { "no errors expected" };
    }

    test("validateRequired fails when field missing") {
      let params = new Map<String, String>([]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateRequired([csid("name")]);
      assert(!cs.isValid)               { "should be invalid" };
      assert(cs.errors.length == 1)     { "should have one error" };
      assert(cs.errors[0].field == "name") { "error should name the field" };
    }

## validateLength

    test("validateLength passes within range") {
      let params = new Map<String, String>([new Pair("name", "Alice")]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateLength(csid("name"), 2, 50);
      assert(cs.isValid) { "should be valid" };
    }

    test("validateLength fails when too short") {
      let params = new Map<String, String>([new Pair("name", "A")]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateLength(csid("name"), 2, 50);
      assert(!cs.isValid) { "should be invalid" };
    }

    test("validateLength fails when too long") {
      let params = new Map<String, String>([new Pair("name", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateLength(csid("name"), 2, 10);
      assert(!cs.isValid) { "should be invalid" };
    }

## validateInt / validateFloat

    test("validateInt passes for valid integer") {
      let params = new Map<String, String>([new Pair("age", "30")]);
      let cs = changeset(userTable(), params).cast([csid("age")]).validateInt(csid("age"));
      assert(cs.isValid) { "should be valid" };
    }

    test("validateInt fails for non-integer") {
      let params = new Map<String, String>([new Pair("age", "not-a-number")]);
      let cs = changeset(userTable(), params).cast([csid("age")]).validateInt(csid("age"));
      assert(!cs.isValid) { "should be invalid" };
    }

    test("validateFloat passes for valid float") {
      let params = new Map<String, String>([new Pair("score", "9.5")]);
      let cs = changeset(userTable(), params).cast([csid("score")]).validateFloat(csid("score"));
      assert(cs.isValid) { "should be valid" };
    }

## validateInt64

    test("validateInt64 passes for valid 64-bit integer") {
      let params = new Map<String, String>([new Pair("age", "9999999999")]);
      let cs = changeset(userTable(), params).cast([csid("age")]).validateInt64(csid("age"));
      assert(cs.isValid) { "should be valid" };
    }

    test("validateInt64 fails for non-integer") {
      let params = new Map<String, String>([new Pair("age", "not-a-number")]);
      let cs = changeset(userTable(), params).cast([csid("age")]).validateInt64(csid("age"));
      assert(!cs.isValid) { "should be invalid" };
    }

## validateBool

    test("validateBool accepts true/1/yes/on") {
      for (let v of ["true", "1", "yes", "on"]) {
        let params = new Map<String, String>([new Pair("active", v)]);
        let cs = changeset(userTable(), params).cast([csid("active")]).validateBool(csid("active"));
        assert(cs.isValid) { "should accept: ${v}" };
      }
    }

    test("validateBool accepts false/0/no/off") {
      for (let v of ["false", "0", "no", "off"]) {
        let params = new Map<String, String>([new Pair("active", v)]);
        let cs = changeset(userTable(), params).cast([csid("active")]).validateBool(csid("active"));
        assert(cs.isValid) { "should accept: ${v}" };
      }
    }

    test("validateBool rejects ambiguous values") {
      for (let v of ["TRUE", "Yes", "maybe", "2", "enabled"]) {
        let params = new Map<String, String>([new Pair("active", v)]);
        let cs = changeset(userTable(), params).cast([csid("active")]).validateBool(csid("active"));
        assert(!cs.isValid) { "should reject ambiguous: ${v}" };
      }
    }

## toInsertSql — SQL injection safety

    test("toInsertSql escapes Bobby Tables") {
      let params = new Map<String, String>([
        new Pair("name", "Robert'); DROP TABLE users;--"),
        new Pair("email", "bobby@evil.com"),
      ]);
      let cs = changeset(userTable(), params)
        .cast([csid("name"), csid("email")])
        .validateRequired([csid("name"), csid("email")]);
      let sqlFrag = cs.toInsertSql() orelse panic();
      let s = sqlFrag.toString();
      // The single-quote in "Robert'" is doubled to '' — the attack is inert
      assert(s.indexOf("''") is StringIndex) { "single quote must be doubled: ${s}" };
    }

    test("toInsertSql produces correct SQL for string field") {
      let params = new Map<String, String>([
        new Pair("name", "Alice"),
        new Pair("email", "a@example.com"),
      ]);
      let cs = changeset(userTable(), params)
        .cast([csid("name"), csid("email")])
        .validateRequired([csid("name"), csid("email")]);
      let sqlFrag = cs.toInsertSql() orelse panic();
      let s = sqlFrag.toString();
      assert(s.indexOf("INSERT INTO users") is StringIndex) { "has INSERT INTO: ${s}" };
      assert(s.indexOf("'Alice'") is StringIndex)           { "has quoted name: ${s}" };
    }

    test("toInsertSql produces correct SQL for int field") {
      // age is nullable in userTable, so we can insert with just age
      let params = new Map<String, String>([
        new Pair("name", "Bob"),
        new Pair("email", "b@example.com"),
        new Pair("age", "25"),
      ]);
      let cs = changeset(userTable(), params)
        .cast([csid("name"), csid("email"), csid("age")])
        .validateRequired([csid("name"), csid("email")]);
      let sqlFrag = cs.toInsertSql() orelse panic();
      let s = sqlFrag.toString();
      assert(s.indexOf("25") is StringIndex) { "age rendered unquoted: ${s}" };
    }

    test("toInsertSql bubbles on invalid changeset") {
      let params = new Map<String, String>([]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateRequired([csid("name")]);
      let didBubble = do { cs.toInsertSql(); false } orelse true;
      assert(didBubble) { "invalid changeset should bubble" };
    }

    test("toInsertSql enforces non-nullable fields independently of isValid") {
      // Build a table where name is non-nullable
      let strictTable = new TableDef(csid("posts"), [
        new FieldDef(csid("title"), new StringField(), false),
        new FieldDef(csid("body"),  new StringField(), true),
      ]);
      // Provide body only — title is required but missing
      let params = new Map<String, String>([new Pair("body", "hello")]);
      let cs = changeset(strictTable, params).cast([csid("body")]);
      // cs.isValid is true (no validations failed), but title is missing
      assert(cs.isValid) { "changeset should appear valid (no explicit validation run)" };
      // toInsertSql must still bubble — independent nullable check catches it
      let didBubble = do { cs.toInsertSql(); false } orelse true;
      assert(didBubble) { "toInsertSql should enforce nullable regardless of isValid" };
    }

## toUpdateSql

    test("toUpdateSql produces correct SQL") {
      let params = new Map<String, String>([new Pair("name", "Bob")]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateRequired([csid("name")]);
      let sqlFrag = cs.toUpdateSql(42) orelse panic();
      let s = sqlFrag.toString();
      assert(s == "UPDATE users SET name = 'Bob' WHERE id = 42") { "got: ${s}" };
    }

    test("toUpdateSql bubbles on invalid changeset") {
      let params = new Map<String, String>([]);
      let cs = changeset(userTable(), params).cast([csid("name")]).validateRequired([csid("name")]);
      let didBubble = do { cs.toUpdateSql(1); false } orelse true;
      assert(didBubble) { "invalid changeset should bubble" };
    }
