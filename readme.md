## Routemaster Indexer

An "indexer" is a ruby class that is responsible for receiving an event and
materializing the remote resource (described by the event) in database.

This is a set of utilities that provide both the wiring and the DSL to
painlessly index routemaster topics.

### Configuration

First you need an "event handler":

```ruby
indexer_handler = Routemaster::Indexer::EventHandler.new({ ...options })
```

Where options could be:

- `topics` (only when using in `.subscribe`): An array of topics to be used.
If not provided nothing would be indexed.
- `queue`: name of the queue to be used by sidekiq worker

Then there are two options to configure:

1. **If you DON'T need resources to be cached in redis:** use `indexer_handler` as siphon:

```ruby
indexer_handler = Routemaster::Indexer::EventHandler.new
siphon_events = {
  zones:               indexer_handler,
  rider_domain_riders: indexer_handler
}

app = Routemaster::Drain::Caching.new(siphon_events: siphon_events)
# ...

map '/events' do
  run app
end
```

2. **You DO need resources cached in redis:** In this case you need to use
use `Routemaster::Indexer::Listener` and configure it as a listener:

```ruby
TOPICS_TO_INDEX = %w(
  zones
  rider_domain_riders
)

indexer = Routemaster::Indexer::EventHandler.new({ topics: TOPICS_TO_INDEX })
app = Routemaster::Drain::Caching.new # or ::Basic.new
app.subscribe(indexer, prefix: true)
# ...

map '/events' do
  run app
end
```

### DSL

Next you would need to define an indexer for each of the topic. The name of
the indexer class should match the topic name (in singular)

```ruby
require 'routemaster/indexer'

class ZoneIndexer
  include Routemaster::Indexer

  use_model :zone

  index :id, as: :orderweb_id
  index :code
  index :name

  link :city do
    index :tz_name, as: :timezone

    link :country do
      index :name, prefix: 'country_'
      index :iso_alpha2_code, prefix: 'country_'
    end
  end
end
```

Here is what each part of the DSL mean:

#### `use_model <model_name>`
describes the name of the active record model to be used.

#### `index <key>, as: <column> (default: key), prefix: <prefix> (default: '')`
describes mapping a resource key to database column.

#### `link <key>`
describes indexing from a relation of the resource. This can be nested to any depth as shown above.

When inside the block of a `link` any other part of DSL can be used and will be evaluated in the context of the relation resource.

#### `after_index <method>`
describes the name of the instance method to be invoked after a record was indexed.

```ruby
class ZoneIndexer
  include Routemaster::Indexer

  after_index :my_method

  def my_method(record)
  end
end
```
