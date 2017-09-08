require 'spec_helper'
require 'support/uses_redis'
require 'materialist/materializer'

RSpec.describe Materialist::Materializer do
  uses_redis

  describe "#perform" do
    let!(:materializer_class) do
      class FoobarMaterializer
        include Materialist::Materializer

        persist_to :foobar
        capture :name
        capture :age, as: :how_old

        materialize_link :city

        link :city do
          capture :timezone

          link :country do
            capture :tld, as: :country_tld
          end
        end
      end

      class CityMaterializer
        include Materialist::Materializer

        persist_to :city
        capture :name
      end
    end

    # this class mocks active record behaviour
    class BaseModel
      def update_attributes(attrs)
        attrs.each { |k, v| send("#{k}=", v) }
      end

      def save!
        self.class.all[source_url] = self
      end

      def destroy!
        self.class.all.delete source_url
      end

      def reload
        self.class.all[source_url]
      end

      def actions_called
        @_actions_called ||= {}
      end

      class << self
        attr_accessor :error_to_throw_once_in_find_or_initialize_by

        def find_or_initialize_by(source_url:)
          if(err = error_to_throw_once_in_find_or_initialize_by)
            self.error_to_throw_once_in_find_or_initialize_by = nil
            raise err
          end

          (all[source_url] || self.new).tap do |record|
            record.source_url = source_url
          end
        end

        def find_by(source_url:)
          all[source_url]
        end

        def create!(attrs)
          new.tap do |record|
            record.update_attributes attrs
            record.save!
          end
        end

        def all
          store[self.name] ||= {}
        end

        def destroy_all
          store[self.name] = {}
        end

        def store
          @@_store ||= {}
        end

        def count
          all.keys.size
        end
      end
    end

    class Foobar < BaseModel
      attr_accessor :source_url, :name, :how_old, :age, :timezone, :country_tld
    end

    class City < BaseModel
      attr_accessor :source_url, :name
    end

    module ActiveRecord
      class RecordNotUnique < StandardError; end
      class RecordInvalid < StandardError; end
    end

    let(:country_url) { 'https://service.dev/countries/1' }
    let(:country_body) {{ tld: 'fr' }}
    let(:city_url) { 'https://service.dev/cities/1' }
    let(:city_body) {{ _links: { country: { href: country_url }}, name: 'paris', timezone: 'Europe/Paris' }}
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:source_body) {{ _links: { city: { href: city_url }}, name: 'jack', age: 30 }}
    before do
      Foobar.destroy_all
      City.destroy_all

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

    let(:action) { :create }
    let(:perform) { FoobarMaterializer.perform(source_url, action) }

    it "materializes record in db" do
      expect{perform}.to change{Foobar.count}.by 1
      inserted = Foobar.find_by(source_url: source_url)
      expect(inserted.name).to eq source_body[:name]
      expect(inserted.how_old).to eq source_body[:age]
      expect(inserted.timezone).to eq city_body[:timezone]
      expect(inserted.country_tld).to eq country_body[:tld]
    end

    it "materializes linked record separately in db" do
      expect{perform}.to change{City.count}.by 1

      inserted = City.find_by(source_url: city_url)
      expect(inserted.name).to eq city_body[:name]
    end

    context "when record already exists" do
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }

      it "updates the existing record" do
        expect{ perform }.to change { record.reload.name }
          .from('mo').to('jack')
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "removes record from db" do
          expect{perform}.to change{Foobar.count}.by -1
        end
      end
    end

    context "when there is a race condition between a create and update" do
      let(:error) {   }
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }

      before { Foobar.error_to_throw_once_in_find_or_initialize_by = error }

      [ ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid ].each do |error_type|
        context "when error of type #{error_type.name} is thrown" do
          let(:error) { error_type }

          it "still updates the record" do
            expect{ perform }.to change { record.reload.name }
              .from('mo').to('jack')
          end

          context "if error was thrown second time" do
            before { allow(Foobar).to receive(:find_or_initialize_by).and_raise error }

            it "bubbles up the error" do
              expect{ perform }.to raise_error error
            end
          end

        end
      end

    end

    %i(create update noop).each do |action_name|
      context "when action is :#{action_name}" do
        let(:action) { action_name }
        it "inserts record in db" do
          expect{perform}.to change{Foobar.count}.by 1
        end
      end
    end

    context "when action is :delete and no existing record in db" do
      let(:action) { :delete }

      it "does not remove anything from db" do
        expect{perform}.to change{Foobar.count}.by 0
      end
    end

    context "if resource returns 404" do
      before { stub_request(:get, source_url).to_return(status: 404) }

      it "does not add anything to db" do
        expect{perform}.to change{Foobar.count}.by 0
      end
    end

    context "if a linked resource returns 404" do
      before { stub_request(:get, city_url).to_return(status: 404) }

      it "ignores keys from the relation" do
        expect{perform}.to change{Foobar.count}.by 1
        inserted = Foobar.find_by(source_url: source_url)
        expect(inserted.country_tld).to eq nil
      end
    end

    context "when after_upsert is configured" do
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }
      let!(:materializer_class) do
        class FoobarMaterializer
          include Materialist::Materializer

          persist_to :foobar
          after_upsert :my_method

          def my_method(entity)
            entity.actions_called[:after_upsert] = true
          end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "calls after_upsert method" do
            expect{ perform }.to change { record.actions_called[:after_upsert] }
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "does not call after_upsert method" do
          expect{ perform }.to_not change { record.actions_called[:after_upsert] }
        end
      end

    end

    context "when after_destroy is configured" do
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }
      let!(:materializer_class) do
        class FoobarMaterializer
          include Materialist::Materializer

          persist_to :foobar
          after_destroy :my_method

          def my_method(entity)
            entity.actions_called[:after_destroy] = true
          end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "does not call after_destroy method" do
            expect{ perform }.to_not change { record.actions_called[:after_destroy] }
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "calls after_destroy method" do
          expect{ perform }.to change { record.actions_called[:after_destroy] }
        end

        context "when resource doesn't exist locally" do
          it "does not raise error" do
            Foobar.destroy_all
            expect{ perform }.to_not raise_error
          end
        end
      end

    end
  end
end
