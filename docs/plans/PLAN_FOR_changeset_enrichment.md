# Plan: Phase 6 — Changeset Enrichment

## Design Rationale

### Data Manipulation (putChange, getChange, deleteChange)

These methods allow programmatic modification of changeset data after casting.
All operate on the immutable `changes` Map, returning new Changeset instances.

- `putChange(field, value)` — adds or overwrites a field in changes. Uses MapBuilder
  to copy existing entries and set the new one. The field must be a SafeIdentifier.
- `getChange(field)` — retrieves a field value, bubbles if field not present.
  Uses `_changes.has()` for presence check, not `.isEmpty`.
- `deleteChange(field)` — removes a field from changes by rebuilding the Map
  without the specified key.

### validateInclusion / validateExclusion

Check that a field's value is (or is not) in a provided list of allowed/disallowed
strings. Skip validation if the field is not in changes (matches Ecto behavior).

### validateNumber

Takes a `NumberValidationOpts` class with 5 nullable Float64 fields:
`greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`, `equalTo`.

Each non-null option is checked against the parsed numeric value. Uses the
local-variable narrowing pattern for nullable fields (assign to local var,
then null-check the local).

### validateAcceptance / validateConfirmation

- `validateAcceptance` — checks that a field is truthy (true/1/yes/on). Matches
  Ecto's `validate_acceptance/3` for terms-of-service style checkboxes.
- `validateConfirmation` — checks that a confirmation field matches the original.
  Error is attached to the confirmation field, not the original.

### String Pattern Validation

- `validateContains` — uses `String.indexOf()` to check substring presence
- `validateStartsWith` — uses `indexOf()` + `countBetween(String.begin, idx) == 0`
  to verify match is at position 0
- `validateEndsWith` — uses cursor-based character comparison: advances val cursor
  by (valLen - suffixLen) positions using `String.next()`, then compares remaining
  characters with suffix using `[idx]` character access

## Ecto Equivalences

| Temper Method | Ecto Equivalent |
|---------------|-----------------|
| `putChange(field, value)` | `Ecto.Changeset.put_change/3` |
| `getChange(field)` | `Ecto.Changeset.get_change/3` |
| `deleteChange(field)` | `Ecto.Changeset.delete_change/2` |
| `validateInclusion(field, allowed)` | `Ecto.Changeset.validate_inclusion/3` |
| `validateExclusion(field, disallowed)` | `Ecto.Changeset.validate_exclusion/3` |
| `validateNumber(field, opts)` | `Ecto.Changeset.validate_number/3` |
| `validateAcceptance(field)` | `Ecto.Changeset.validate_acceptance/3` |
| `validateConfirmation(field, confField)` | `Ecto.Changeset.validate_confirmation/3` |
| `validateContains(field, substring)` | Custom (no Ecto built-in) |
| `validateStartsWith(field, prefix)` | Custom (no Ecto built-in) |
| `validateEndsWith(field, suffix)` | Custom (no Ecto built-in) |

## Security Analysis

- No new SQL injection surface: these methods operate on the `changes` Map
  (String keys and values), not on SQL generation.
- `putChange` accepts SafeIdentifier for field name — validated identifier only.
- `validateNumber` parses values as Float64 for comparison — no SQL generated.
- String pattern validators use Temper's built-in string methods (indexOf,
  countBetween, next, hasIndex, character access) — no external input
  reaches SQL builders.
- All methods return new Changeset instances (immutable pattern preserved).

## New Types

1. `NumberValidationOpts` — class with 5 nullable Float64 fields

## New Methods on Changeset

1. `putChange(field: SafeIdentifier, value: String): Changeset`
2. `getChange(field: SafeIdentifier): String throws Bubble`
3. `deleteChange(field: SafeIdentifier): Changeset`
4. `validateInclusion(field: SafeIdentifier, allowed: List<String>): Changeset`
5. `validateExclusion(field: SafeIdentifier, disallowed: List<String>): Changeset`
6. `validateNumber(field: SafeIdentifier, opts: NumberValidationOpts): Changeset`
7. `validateAcceptance(field: SafeIdentifier): Changeset`
8. `validateConfirmation(field: SafeIdentifier, confirmationField: SafeIdentifier): Changeset`
9. `validateContains(field: SafeIdentifier, substring: String): Changeset`
10. `validateStartsWith(field: SafeIdentifier, prefix: String): Changeset`
11. `validateEndsWith(field: SafeIdentifier, suffix: String): Changeset`

## Breaking Changes

- Changeset sealed interface grows by 11 methods
- No changes to constructor signatures or existing methods
