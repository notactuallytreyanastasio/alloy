# Narratives: Temper ORM Decision Graph

## Narrative 1: Building a Secure ORM in Temper
The spine of the project. An Ecto-inspired ORM built in the Temper language with SQL injection
prevention baked into the type system.

**Concepts:** Changeset, Query, Schema, SafeIdentifier, TableDef, FieldDef, SqlBuilder, SqlFragment

**Commits:**
- 328d02d: initial — Full ORM implementation: Schema (SafeIdentifier, TableDef, FieldDef),
  Query (composable immutable SELECT builder), Changeset (cast→validate→SQL pipeline),
  and Orm (deleteSql helper). Tests for all three (changeset_test, query_test, schema_test).
  Security model: sealed interfaces, validated identifiers, SqlFragment for user values.

This is a single-commit creation — the ORM design arrived fully formed.

## Narrative 2: Dependency Strategy — How to Include secure-composition
The ORM depends on secure-composition (a private repo providing SqlBuilder, SqlFragment, etc).
The strategy for including this dependency evolved through three approaches.

**Concepts:** secure-composition, vendor, import paths, project boundaries, package.json

**Commits:**
- 3033637: Vendor secure-composition and add CI with Temper v0.6.0 —
  Vendored the entire secure-composition repo as a nested project. Set up import paths
  from ../../secure-composition/. Added CI workflow. Added package.json file: dependency.
- 551b566: Inline secure-composition SQL into ORM source tree —
  Realized vendoring all of secure-composition confused Temper's project boundary detection.
  Pivoted to including ONLY the SQL files (builder, model, imports, tests) directly under src/sql/.
  Removed the standalone secure-composition/ directory. Import paths: ./sql/*
- e57869a: Flatten module structure for Temper nightly compatibility —
  Final pivot: moved sql/ files into src/ directly (as sql_builder, sql_model, etc.)
  because sibling modules process @I stage in parallel, causing cross-module import failures.
  Everything became one flat module in src/.

**Lifecycle:**
- secure-composition/ directory: introduced (3033637), removed (551b566)
- src/sql/ subdirectory: introduced (551b566), flattened into src/ (e57869a)
- Cross-module imports: introduced (551b566), removed (e57869a) — same-module files share scope

## Narrative 3: CI & Temper Version Compatibility
Getting CI to work required switching Temper versions and solving JRE problems.

**Concepts:** Temper v0.6.0, Temper nightly 0.6.1-dev, @overload, JRE, JDK 21, JAVA_HOME

**Commits:**
- 3033637: Initial CI with Temper v0.6.0 — downloads linux binary, builds secure-composition first
- 96628b4: Switch CI to Temper nightly (0.6.1-dev) — v0.6.0 doesn't support @overload and
  generic interfaces used by secure-composition
- 52b6488: Add JDK 21 setup and inspect temper binary layout — nightly bundles minimal JRE
  missing java.desktop module
- 2b6c38e: Use system JDK instead of bundled minimal JRE — override launcher script to use
  system JDK 21 (temurin) with all required modules

**Lifecycle:**
- Temper v0.6.0: used (3033637), replaced by nightly (96628b4)
- Bundled JRE: discovered insufficient (52b6488), bypassed with system JDK (2b6c38e)
- JDK 21 setup-java: added (52b6488), refined (2b6c38e)

## Narrative 4: Nightly Parser Compatibility Fixes
The Temper nightly parser has quirks not present in v0.6.0. Several code changes were
needed to work around parser limitations.

**Concepts:** when expressions, ### headers, multi-line if/else in when arms, Int32? narrowing,
parseBoolSqlPart, code block continuity

**Commits:**
- 68a4a5a: Extract BoolField logic to helper to fix nightly parser —
  Nightly can't handle multi-line if/else inside when arms. Extracted to parseBoolSqlPart().
- 345137e: Remove ### headers inside class bodies for nightly parser compat —
  Nightly treats ### as code block boundaries, breaking class method continuity.
  Replaced with // comments.
- e57869a: Flatten module structure (also fixes) —
  Convert when expressions to if-else chains. Fix nullable Int32? narrowing with local var pattern.

**Lifecycle:**
- when expressions: used initially (328d02d), converted to if-else (e57869a) due to parser
- ### headers: used for organization (328d02d), replaced with // comments (345137e) due to parser
- parseBoolSqlPart: introduced (68a4a5a) as workaround for when-arm limitation

## Cross-Narrative Connections
- Narrative 2 → 3: The decision to vendor secure-composition required CI, and secure-composition's
  use of @overload forced the switch to nightly (Narrative 3)
- Narrative 3 → 4: Switching to nightly introduced parser incompatibilities (Narrative 4)
- Narrative 4 → 2: Some parser fixes (flatten module structure) also resolved the dependency
  inclusion strategy (Narrative 2's final form)

## Commit: ce6b2ae "lets see"
This just adds temper.keep/ name-selection files for additional backends (csharp, java, lua, py, rust).
Not part of any design narrative — it's exploration of multi-backend output.
