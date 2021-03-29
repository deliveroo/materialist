## Materialist

> _adjective_ `philosophy`: relating to the theory that nothing exists except matter and its movements and modifications.

A "materializer" is a ruby class that is responsible for receiving an event and
materializing the remote resource (described by the event) in database.

This library is a set of utilities that provide both the wiring and the DSL to
painlessly do so.

### Install

In your `gemfile`

```ruby
gem 'materialist'

# or for sandbox features
gem 'materialist', github: 'deliveroo/materialist', branch: 'sandbox'
```

Then do

```bash
bundle
```

### Release

After merging all of your PRs:

1. Bump the version in `lib/materialist/version.rb` -- let's say `x.y.z`
1. Build the gem: `gem build materialist.gemspec`
1. Push the gem: `gem push materialist-x.y.z.gem`
1. Commit changes: `git commit -am "Bump version"`
1. Create a tag: `git tag -a vx.y.z`
1. Push changes: `git push origin master`
1. Push the new: `git push origin --tags`

## Usage

### Entity

Your materialised entity need to have a **unique** `source_url` column, alongside any other field you wish to materialise.

```ruby
class CreateZones < ActiveRecord::Migration[5.0]
  def change
    create_table :zones do |t|
      t.integer :orderweb_id
      t.string :code, null: false
      t.string :name
      t.string :timezone
      t.string :country_name
      t.string :country_iso_alpha2_code
      t.string :source_url

      t.timestamps

      t.index :code, unique: true
      t.index :source_url, unique: true
    end
  end
end
```

```ruby
class Zone < ApplicationRecord
end
```

### Materialist Configuration

If you need to override any of the materialist configurations,
you can do so in an `configure/initializers/materialist.rb` file:


```ruby
Materialist.configure do |config|
  # Configure materialist here. For example:
  #
  # config.topics = %w(topic_a topic_b)
  #
  # config.sidekiq_options = {
  #   queue: :routemaster_index,
  #   retry: 3
  # }
  #
  # config.metrics_client = STATSD
  # config.api_client = Routemaster::APIClient.new(response_class: Routemaster::Responses::HateoasResponse)
end
```

- `topics` (only when using in `.subscribe`): A string array of topics to be used.
If not provided nothing would be materialized.
- `sidekiq_options` (optional, default: `{ retry: 10 }`) -- See [Sidekiq docs](https://github.com/mperham/sidekiq/wiki/Advanced-Options#workers) for list of options
- `api_client` (optional) -- You can pass your `Routemaster::APIClient` instance
- `metrics_client` (optional) -- You can pass your `STATSD` instance
- `notice_error` (optional) -- You can pass a lambda accepting two parameters (`exception` and `event`) -- Typical use case is to enrich error and send to NewRelic APM

### Routemaster Configuration

First you need an "event handler":

```ruby
handler = Materialist::EventHandler.new
```

Where options could be:

Then there are two ways to configure materialist in routemaster:

1. **If you DON'T need resources to be cached in redis:** use `handler` as siphon:

```ruby
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

2. **You DO need resources cached in redis:** In this case you need to provide `topics` in `Materialist.configure` and use `handler` to subscribe to routemaster caching pipeline:

```ruby
app = Routemaster::Drain::Caching.new # or ::Basic.new
app.subscribe(handler, prefix: true)
# ...

map '/events' do
  run app
end
```

#### DSL

Next you would need to define a materializer for each of the topic. The name of
the materializer class should match the topic name (in singular)

These materializers would live in a first-class directory (`/materializers`) in your rails app.

```ruby
require 'materialist/materializer'

class ZoneMaterializer
  include Materialist::Materializer

  sidekiq_options queue: :orderweb_service, retry: false

  persist_to :zone

  source_key :source_id do |url, response|
    /(\d+)\/?$/.match(url)[1] # or response.dig(:some_attr)
  end

  capture :id, as: :orderweb_id
  capture :code
  capture :name

  link :city do
    capture :tz_name, as: :timezone

    link :country do
      capture :name, as: :country_name
      capture :iso_alpha2_code, as: :country_iso_alpha2_code
    end
  end

  materialize_link :settings, topic: :zone_settings
end
```

Here is what each part of the DSL mean:

#### `sidekiq_options <options>`
allows to override options for the Sidekiq job which does the materialization.
Typically it will specify which queue to put the job on or how many times
should the job try to retry. These options override the options specified in
`Materialist.configuration.sidekiq_options`.

#### `persist_to <model_name>`
describes the name of the active record model to be used.
If missing, materialist skips materialising the resource itself, but will continue
with any other functionality -- such as `materialize_link`.

#### `source_key <column> <parser_block> (default: url, resource response body[create, update action only])`
describes the column used to persist the unique identifier parsed from the url_parser_block.
By default the column used is `:source_url` and the original `url` is used as the identifier.
Passing an optional block allows you to extract an identifier from the URL and captured attributes.

#### `capture <key>, as: <column> (default: key)`
describes mapping a resource key to a database column.

You can optionally provide a block for parsing the value:

```ruby
capture(:location, as: :latitude) { |location| location[:latitude] }
```

#### `capture_link_href <key>, as: <column>`
describes mapping a link href (as it appears on the hateous response) to a database column.

You can optionally provide a block for parsing the url:

```ruby
capture_link_href :rider, as: :rider_id do |url|
  url.split('/').last
end
```

#### `link <key>, enable_caching: <enable_caching> (default: false)`
describes materializing from a relation of the resource. This can be nested to any depth as shown above.

When inside the block of a `link` any other part of DSL can be used and will be evaluated in the context of the relation resource.

`<enable_caching>` is optional and false by default. If `true` then Routemaster cache will be used when available for linked resources.

### `materialize_link <key>, topic: <topic> (default: key)`
describes materializing the linked entity.
This simulates a `:noop` event on the given topic and the `url` of the
liked resource `<key>` as it appears on the response (`_links`) -- meaning the materializer for the given topic will be invoked.

#### `before_upsert <method> (, <method>(, ...))` -- also `before_destroy`
describes the name of the instance method(s) to be invoked before a record is materialized, with the record as it exists in the database, or nil if it has not been created yet.

```ruby
class ZoneMaterializer
  include Materialist::Materializer

  before_upsert :my_method, :my_second_method

  def my_method(record)
  end

  def my_second_method(record)
  end
end
```

#### `before_upsert_with_payload <method> (, <method>(, ...))`
describes the name of the instance method(s) to be invoked before a record is
materialized, with the record as it exists in the database, or nil if it has
not been created yet. The function will get as a second argument the `payload`
of the HTTP response, this can be used to add additional information/persist
other objects.


```ruby
class ZoneMaterializer
  include Materialist::Materializer

  before_upsert_with_payload :my_method

  def my_method(record, payload); end
end
```


#### `after_upsert <method> (, <method>(, ...))` -- also `after_destroy`
describes the name of the instance method(s) to be invoked after a record was materialized, with the updated record as a parameter. See above for a similar example implementation.


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

#### DSL

- `source_link_reader <key>, via: <key> (default: none), allow_nil: true/false (default: false)`: Adds a method named `<key>` to the class giving access to the specified linked resource. If `allow_nil` is set to `false` (default) and error is raised if the resource is missing.

The above example will give you `.source`, `.city` and `.country` on any instances of `Rider`, allowing you to access remote resources.

e.g.

```ruby
rider = Rider.last
rider.source.name
rider.city.code
rider.country.created_at
```
