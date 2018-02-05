ActiveRecord::Schema.define do
  self.verbose = false

  create_table :foobars, :force => true do |t|
    t.string :source_url, null: false
    t.string :name
    t.integer :how_old
    t.integer :age
    t.string :timezone
    t.string :country_tld
    t.string :city_url
    t.string :account_url

    t.timestamps
  end

  create_table :cities, :force => true do |t|
    t.string :source_url, null: false
    t.string :name

    t.timestamps
  end

  create_table :defined_sources, :force => true do |t|
    t.integer :source_id, null: false
    t.string :name

    t.timestamps
  end

end
