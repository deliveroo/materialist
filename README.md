## Materialist

> _adjective_ `philosophy`: relating to the theory that nothing exists except matter and its movements and modifications.

A "materializer" is a ruby class that is responsible for receiving an event and
materializing the remote resource (described by the event) in database.

This library is a set of utilities that provide both the wiring and the DSL to
painlessly do so.

### Entity

Your materialised entity need to have a **unique** `source_url` column, alongside any other field you wish to materialise.

```ruby
create_table "zones", force: :cascade do |t|
  t.integer  "orderweb_id"
  t.string   "code",                    null: false
  t.string   "name"
  t.string   "timezone"
  t.string   "country_name"
  t.string   "country_iso_alpha2_code"
  t.string   "source_url"
  t.datetime "created_at",              null: false
  t.datetime "updated_at",              null: false
  t.index ["code"], name: "index_zones_on_code", unique: true, using: :btree
  t.index ["source_url"], name: "index_zones_on_source_url", unique: true, using: :btree
end
```

### Routemaster Configuration

First you need an "event handler":

```ruby
handler = Materialist::EventHandler.new({ ...options })
```

Where options could be:

- `topics` (only when using in `.subscribe`): An array of topics to be used.
If not provided nothing would be materialized.
- `queue`: name of the queue to be used by sidekiq worker

Then there are two ways to configure materialist in routemaster:

1. **If you DON'T need resources to be cached in redis:** use `handler` as siphon:

```ruby
handler = Materialist::EventHandler.new
siphon_events = {
  zones:               handler,
  rider_domain_riders: handler
}

app = Routemaster::Drain::Caching.new(siphon_events: siphon_events)
# ...

map '/events' do
  run app
end
```

2. **You DO need resources cached in redis:** In this case you need to use `handler` to subscribe to the caching pipeline:

```ruby
TOPICS = %w(
  zones
  rider_domain_riders
)

handler = Materialist::EventHandler.new({ topics: TOPICS })
app = Routemaster::Drain::Caching.new # or ::Basic.new
app.subscribe(handler, prefix: true)
# ...

map '/events' do
  run app
end
```

### DSL

Next you would need to define a materializer for each of the topic. The name of
the materializer class should match the topic name (in singular)

These materializers would live in a first-class directory (`/materializers`) in your rails app.

```ruby
require 'materialist/materializer'

class ZoneMaterializer
  include Materialist::Materializer

  use_model :zone

  materialize :id, as: :orderweb_id
  materialize :code
  materialize :name

  link :city do
    materialize :tz_name, as: :timezone

    link :country do
      materialize :name, as: :country_name
      materialize :iso_alpha2_code, as: :country_iso_alpha2_code
    end
  end
end
```

Here is what each part of the DSL mean:

#### `use_model <model_name>`
describes the name of the active record model to be used.

#### `materialize <key>, as: <column> (default: key)`
describes mapping a resource key to database column.

#### `link <key>`
describes materializing from a relation of the resource. This can be nested to any depth as shown above.

When inside the block of a `link` any other part of DSL can be used and will be evaluated in the context of the relation resource.

#### `after_upsert <method>` -- also `after_destroy`
describes the name of the instance method to be invoked after a record was materialized.

```ruby
class ZoneMaterializer
  include Materialist::Materializer

  after_upsert :my_method

  def my_method(record)
  end
end
```

### Materialized record

Imagine you have materialized rider from a routemaster topic and you need to access a key from the remote source that you HAVEN'T materialized locally.

> NOTE that doing such thing is only acceptable if you use `caching` drain, otherwise every time the remote source is fetched a fresh http call is made which will result in hammering of the remote service.

> Also it is unacceptable to iterate through a large set of records and call on remote sources. Any such data should be materialised because database (compared to redis cache) is more optimised to perform scan operations.

```ruby
class Rider
  include Materialist::MaterializedRecord

  source_link_reader :city
  source_link_reader :country, via: :city
end
```

Above will give you `.source`, `.city` and `.country` on any instances of `Rider`, allowing you to access remote keys.

e.g.

```ruby
Rider.last.country.created_at
```
