# Schema Tests

    test("safeIdentifier accepts valid names") {
      let id = safeIdentifier("user_name") orelse panic();
      assert(id.sqlValue == "user_name") { "value should round-trip" };
    }

    test("safeIdentifier rejects empty string") {
      let didBubble = do { safeIdentifier(""); false } orelse true;
      assert(didBubble) { "empty string should bubble" };
    }

    test("safeIdentifier rejects leading digit") {
      let didBubble = do { safeIdentifier("1col"); false } orelse true;
      assert(didBubble) { "leading digit should bubble" };
    }

    test("safeIdentifier rejects SQL metacharacters") {
      let cases = ["name); DROP TABLE", "col'", "a b", "a-b", "a.b", "a;b"];
      for (let c of cases) {
        let didBubble = do { safeIdentifier(c); false } orelse true;
        assert(didBubble) { "should reject: ${c}" };
      }
    }

    test("TableDef field lookup - found") {
      let td = new TableDef(
        safeIdentifier("users") orelse panic(),
        [
          new FieldDef(safeIdentifier("name") orelse panic(), new StringField(), false),
          new FieldDef(safeIdentifier("age")  orelse panic(), new IntField(),    false),
        ],
      );
      let f = td.field("age") orelse panic();
      assert(f.name.sqlValue == "age") { "should find age field" };
    }

    test("TableDef field lookup - not found bubbles") {
      let td = new TableDef(
        safeIdentifier("users") orelse panic(),
        [new FieldDef(safeIdentifier("name") orelse panic(), new StringField(), false)],
      );
      let didBubble = do { td.field("nonexistent"); false } orelse true;
      assert(didBubble) { "unknown field should bubble" };
    }

    test("FieldDef nullable flag") {
      let required = new FieldDef(safeIdentifier("email") orelse panic(), new StringField(), false);
      let optional = new FieldDef(safeIdentifier("bio")   orelse panic(), new StringField(), true);
      assert(!required.nullable) { "required field should not be nullable" };
      assert(optional.nullable)  { "optional field should be nullable" };
    }
