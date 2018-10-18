## Next

_description of next release_

## 3.5.0

- Add support for providing an `Routemaster::APIClient` instance as part of configuration

## 3.4.0

- Add support for providing payload into the materializer
- Enhance linked resource materialization to avoid `:noop` stats

## 3.3.0

Features:
- Add support for parsing url when using `capture_link_href`
- Add support for providing `notice_error` on configuration.

## 3.2.0

Features:
- For linked resources specified by `link` an option to `enable_caching` can now be explicitly set. This
tells Routemaster to use or not use the drain cache.

## 3.1.0

Features:
- Allow sidekiq options to be specified per materializer
- Materialist::EventHandler will infer the correct materializer class from the incoming topic

Notes:

Materialist::EventWorker has been moved to Materialist::Workers::Event, but the original has
been left there for backwards compatibility. It will be removed in a later major release.

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
