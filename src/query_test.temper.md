# Query Tests

    let sid(name: String): SafeIdentifier {
      safeIdentifier(name) orelse panic()
    }

    test("bare from produces SELECT *") {
      let q = from(sid("users"));
      assert(q.toSql().toString() == "SELECT * FROM users") { "bare query" };
    }

    test("select restricts columns") {
      let q = from(sid("users")).select([sid("id"), sid("name")]);
      assert(q.toSql().toString() == "SELECT id, name FROM users") { "select columns" };
    }

    test("where adds condition with int value") {
      let q = from(sid("users")).where(sql"age > ${18}");
      assert(q.toSql().toString() == "SELECT * FROM users WHERE age > 18") { "where int" };
    }

    test("where adds condition with bool value") {
      let q = from(sid("users")).where(sql"active = ${true}");
      assert(q.toSql().toString() == "SELECT * FROM users WHERE active = TRUE") { "where bool" };
    }

    test("chained where uses AND") {
      let q = from(sid("users"))
        .where(sql"age > ${18}")
        .where(sql"active = ${true}");
      assert(
        q.toSql().toString() == "SELECT * FROM users WHERE age > 18 AND active = TRUE"
      ) { "chained where" };
    }

    test("orderBy ASC") {
      let q = from(sid("users")).orderBy(sid("name"), true);
      assert(q.toSql().toString() == "SELECT * FROM users ORDER BY name ASC") { "order asc" };
    }

    test("orderBy DESC") {
      let q = from(sid("users")).orderBy(sid("created_at"), false);
      assert(
        q.toSql().toString() == "SELECT * FROM users ORDER BY created_at DESC"
      ) { "order desc" };
    }

    test("limit and offset") {
      let q = do { from(sid("users")).limit(10).offset(20) } orelse panic();
      assert(q.toSql().toString() == "SELECT * FROM users LIMIT 10 OFFSET 20") { "limit/offset" };
    }

    test("limit bubbles on negative") {
      let didBubble = do { from(sid("users")).limit(-1); false } orelse true;
      assert(didBubble) { "negative limit should bubble" };
    }

    test("offset bubbles on negative") {
      let didBubble = do { from(sid("users")).offset(-1); false } orelse true;
      assert(didBubble) { "negative offset should bubble" };
    }

    test("complex composed query") {
      let minAge = 21;
      let q = do {
        from(sid("users"))
          .select([sid("id"), sid("name"), sid("email")])
          .where(sql"age >= ${minAge}")
          .where(sql"active = ${true}")
          .orderBy(sid("name"), true)
          .limit(25)
          .offset(0)
      } orelse panic();
      assert(
        q.toSql().toString() ==
          "SELECT id, name, email FROM users WHERE age >= 21 AND active = TRUE ORDER BY name ASC LIMIT 25 OFFSET 0"
      ) { "complex query" };
    }

    test("safeToSql applies default limit when none set") {
      let q = from(sid("users"));
      let s = (q.safeToSql(100) orelse panic()).toString();
      assert(s == "SELECT * FROM users LIMIT 100") { "should have limit: ${s}" };
    }

    test("safeToSql respects explicit limit") {
      let q = do { from(sid("users")).limit(5) } orelse panic();
      let s = (q.safeToSql(100) orelse panic()).toString();
      assert(s == "SELECT * FROM users LIMIT 5") { "explicit limit preserved: ${s}" };
    }

    test("safeToSql bubbles on negative defaultLimit") {
      let didBubble = do { from(sid("users")).safeToSql(-1); false } orelse true;
      assert(didBubble) { "negative defaultLimit should bubble" };
    }

    test("where with injection attempt in string value is escaped") {
      let evil = "'; DROP TABLE users; --";
      let q = from(sid("users")).where(sql"name = ${evil}");
      let s = q.toSql().toString();
      // The leading ' is doubled to '' — the DROP TABLE becomes a literal string value
      assert(s.indexOf("''") is StringIndex) { "quotes must be doubled: ${s}" };
      assert(s.indexOf("SELECT * FROM users WHERE name =") is StringIndex) { "structure intact: ${s}" };
    }

    test("safeIdentifier rejects user-supplied table name with metacharacters") {
      // A user can't supply a table name that passes safeIdentifier()
      let attack = "users; DROP TABLE users; --";
      let didBubble = do { safeIdentifier(attack); false } orelse true;
      assert(didBubble) { "metacharacter-containing name must be rejected at construction" };
    }
