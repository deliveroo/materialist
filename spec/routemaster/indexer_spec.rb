require 'spec_helper'
require 'routemaster/indexer/event_worker'

RSpec.describe Routemaster::Indexer do
  describe "#perform" do
    let!(:indexer_class) do
      class FoobarIndexer
        include Routemaster::Indexer

        use_model :foobar
        index :name
        index :age, as: :how_old

        link :city do
          index :timezone

          link :country do
            index :tld, as: :country_tld
          end
        end
      end
    end

    let!(:foobar_class) { class Foobar; end }
    let(:country_url) { 'https://service.dev/countries/1' }
    let(:country_body) {{ tld: 'fr' }}
    let(:city_url) { 'https://service.dev/cities/1' }
    let(:city_body) {{ _links: { country: { href: country_url }}, timezone: 'Europe/Paris' }}
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:source_body) {{ _links: { city: { href: city_url }}, name: 'jack', age: 30 }}
    before do
      stub_request(:get, source_url).to_return(
        status: 200,
        body: source_body.to_json,
        headers:  { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, country_url).to_return(
        status: 200,
        body: country_body.to_json,
        headers:  { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, city_url).to_return(
        status: 200,
        body: city_body.to_json,
        headers:  { 'Content-Type' => 'application/json' }
      )
    end

    let(:expected_attributes) do
      { name: 'jack', how_old: 30, country_tld: 'fr', timezone: 'Europe/Paris' }
    end

    let(:record_double) { double() }
    before do
      allow(Foobar).to receive(:find_or_initialize_by).and_return record_double
    end

    let(:action) { :create }
    let(:perform) { FoobarIndexer.perform(source_url, action) }

    def performs_upsert
      expect(Foobar).to receive(:find_or_initialize_by)
        .with(source_url: source_url)
      expect(record_double).to receive(:update_attributes).with(expected_attributes)
      expect(record_double).to receive(:save!)
      perform
    end

    def performs_destroy
      expect(Foobar).to receive(:where)
        .with(source_url: source_url)
        .and_return record_double
      expect(record_double).to receive(:destroy_all)
      perform
    end

    it { performs_upsert }

    %i(create update noop).each do |action_name|
      context "when action is :#{action_name}" do
        let(:action) { action_name }
        it { performs_upsert }
      end
    end

    context "when action is :delete" do
      let(:action) { :delete }

      it { performs_destroy }
    end

    context "if resource returns 404" do
      before { stub_request(:get, source_url).to_return(status: 404) }

      it "bubbles up routemaster not found error" do
        expect { perform }.to raise_error Routemaster::Errors::ResourceNotFound
      end
    end

    context "if a linked resource returns 404" do
      before { stub_request(:get, city_url).to_return(status: 404) }

      let(:expected_attributes) do
        { name: 'jack', how_old: 30 }
      end

      it "ignores keys from the relation" do
        performs_upsert
      end
    end

    context "when after_index is configured" do
      let(:expected_attributes) {{}}
      let!(:indexer_class) do
        class FoobarIndexer
          include Routemaster::Indexer

          use_model :foobar
          after_index :my_method

          def my_method(entity)
            entity.after_index_action
          end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "calls after_index method" do
            expect(record_double).to receive(:after_index_action)
            performs_upsert
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "does not call after_index method" do
          expect(record_double).to_not receive(:after_index_action)
          performs_destroy
        end
      end

    end
  end
end
