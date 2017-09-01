require 'spec_helper'
require 'materialist/materializer'

RSpec.describe Materialist::Materializer do
  describe "#perform" do
    let!(:materializer_class) do
      class FoobarMaterializer
        include Materialist::Materializer

        use_model :foobar
        materialize :name
        materialize :age, as: :how_old

        link :city do
          materialize :timezone

          link :country do
            materialize :tld, as: :country_tld
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
    let(:perform) { FoobarMaterializer.perform(source_url, action) }

    def performs_upsert
      # this is a bit leaky, TODO: mock active record here
      expect(Foobar).to receive(:find_or_initialize_by)
        .with(source_url: source_url)
      expect(record_double).to receive(:update_attributes).with(expected_attributes)
      expect(record_double).to receive(:save!)
      perform
    end

    def performs_destroy
      # this is a bit leaky, TODO: mock active record here
      expect(Foobar).to receive(:find_by)
        .with(source_url: source_url)
        .and_return record_double
      expect(record_double).to receive(:destroy!).and_return record_double
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

    context "when after_upsert is configured" do
      let(:expected_attributes) {{}}
      let!(:materializer_class) do
        class FoobarMaterializer
          include Materialist::Materializer

          use_model :foobar
          after_upsert :my_method

          def my_method(entity)
            entity.after_upsert_action
          end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "calls after_upsert method" do
            expect(record_double).to receive(:after_upsert_action)
            performs_upsert
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "does not call after_upsert method" do
          expect(record_double).to_not receive(:after_upsert_action)
          performs_destroy
        end
      end

    end

    context "when after_destroy is configured" do
      let(:expected_attributes) {{}}
      let!(:materializer_class) do
        class FoobarMaterializer
          include Materialist::Materializer

          use_model :foobar
          after_destroy :my_method

          def my_method(entity)
            entity.after_destroy_action
          end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "does not call after_destroy method" do
            expect(record_double).to_not receive(:after_destroy_action)
            performs_upsert
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }
        it "calls after_destroy method" do
          expect(record_double).to receive(:after_destroy_action)
          performs_destroy
        end

        context "when resource doesn't exist locally" do
          before do
            allow(Foobar).to receive(:find_by)
              .with(source_url: source_url)
              .and_return nil
          end

          it "does not calls after_destroy method" do
            expect(record_double).to_not receive(:after_destroy_action)
            perform
          end
        end
      end

    end
  end
end
