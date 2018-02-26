## 3.0.0

Breaking change:
- `topics`, `retry` and `queue` options are now configured via `Materialist.configure` block.

Features:
- Ability to provide metrics client e.g. STATSD

## 2.3.1

Fixes:
- Fix issue with double `save` in upsert (#32)

## 2.3.0

Features:
 - Add `before_upsert` and `before_destroy` (#31)

## 2.2.0

Features:

- Default retry option plus, allow specifying it (#25)

## 2.1.0

Features:

- Allow source key to be specified (#30)

## 2.0.0

Breaking Changes:

- Don't serialize hashes and arrays (#29)

## 1.0.0

Features:

- Add support for capture_link_href (#26)
- Allow serialisation of complex types to json (#28)

## 0.0.5

Features:

- Make it possible to materialise linked resource without materialising self (#22)

## 0.0.4

Fix:

- Class name inflection (#20)

## 0.0.3

Changes:

- Feature: Materialized record allow nil (#13)
- Fix: Handle race condition on upsert (#14)

## 0.0.2

Features:

- support for after_destroy in materialiser DSL (#5)
- MaterializedRecord utility (#2)
