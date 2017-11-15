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
        capture_link_href :city, as: :city_url
        capture_link_href :account, as: :account_url

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
        source_key :source_url
        capture :name
      end

      class DefinedSourceMaterializer
        include Materialist::Materializer

        persist_to :defined_source

        source_key :source_id do |url|
          url.split('/').last.to_i
        end

        capture :name
      end
    end

    # this class mocks active record behaviour
    class BaseModel
      def update_attributes(attrs)
        attrs.each { |k, v| send("#{k}=", v) }
      end

      def save!
        self.class.all[source_key_value] = self
      end

      def destroy!
        self.class.all.delete source_key_value
      end

      def reload
        self.class.all[source_key_value]
      end

      def actions_called
        @_actions_called ||= {}
      end

      private def source_key_value
        send(self.class.source_key_column)
      end

      class << self
        attr_accessor :error_to_throw_once_in_find_or_initialize_by,
                      :source_key_column

        def find_or_initialize_by(kv_hash)
          if(err = error_to_throw_once_in_find_or_initialize_by)
            self.error_to_throw_once_in_find_or_initialize_by = nil
            raise err
          end

          key_value = kv_hash[source_key_column]

          (all[key_value] || self.new).tap do |record|
            record.send("#{source_key_column}=", key_value)
          end
        end

        def source_key_column
          @source_key_column || :source_url
        end

        def find_by(kv_hash)
          key_value = kv_hash[source_key_column]
          all[key_value]
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
      attr_accessor :source_url, :name, :how_old, :age, :timezone,
        :country_tld, :city_url, :account_url
    end

    class City < BaseModel
      attr_accessor :source_url, :name
    end

    class DefinedSource < BaseModel
      attr_accessor :source_id, :name
      self.source_key_column = :source_id
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
    let(:defined_source_id) { 65 }
    let(:defined_source_url) { "https://service.dev/defined_sources/#{defined_source_id}" }
    let(:defined_source_body) {{ name: 'ben' }}

    def stub_resource(url, body)
      stub_request(:get, url).to_return(
        status: 200,
        body: body.to_json,
        headers:  { 'Content-Type' => 'application/json' }
      )
    end

    before do
      Foobar.destroy_all
      City.destroy_all
      DefinedSource.destroy_all

      stub_resource source_url, source_body
      stub_resource country_url, country_body
      stub_resource city_url, city_body
      stub_resource defined_source_url, defined_source_body
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
      expect(inserted.account_url).to be_nil
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

          it "calls more than one after_upsert method" do
            class FoobarMaterializer
              after_upsert :my_method, :my_method2

              def my_method2(entity)
                entity.actions_called[:after_upsert2] = true
              end
            end
            expect{ perform }.to  change { record.actions_called[:after_upsert]  }
                             .and change { record.actions_called[:after_upsert2] }
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

        it "calls more than one after_destroy method" do
          class FoobarMaterializer
            after_destroy :my_method, :my_method2

            def my_method2(entity)
              entity.actions_called[:after_destroy2] = true
            end
          end
          expect{ perform }.to change  { record.actions_called[:after_destroy]  }
                           .and change { record.actions_called[:after_destroy2] }
        end

        context "when resource doesn't exist locally" do
          it "does not raise error" do
            Foobar.destroy_all
            expect{ perform }.to_not raise_error
          end
        end
      end

    end

    context "when not materializing self but materializing linked parent" do
      class CitySettingsMaterializer
        include Materialist::Materializer

        materialize_link :city
      end

      let(:city_settings_url) { 'https://service.dev/city_settings/1' }
      let(:city_settings_body) {{ _links: { city: { href: city_url }}}}
      before { stub_resource city_settings_url, city_settings_body }

      let(:perform) { CitySettingsMaterializer.perform(city_settings_url, action) }

      it "materializes linked parent" do
        expect{perform}.to change{City.count}.by 1
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "does not materialize linked parent" do
          expect{perform}.to_not change{City.count}
        end
      end
    end

    context "when creating a new entity based on the source_key column" do
      let(:perform) { DefinedSourceMaterializer.perform(defined_source_url, action) }

      it "creates based on source_key" do
        expect{perform}.to change{DefinedSource.count}.by 1
      end

      it "sets the correct source key" do
        perform
        inserted = DefinedSource.find_by(source_id: defined_source_id)
        expect(inserted.source_id).to eq defined_source_id
        expect(inserted.name).to eq defined_source_body[:name]
      end
    end

    context "when updating a new entity based on the source_key column" do
      let(:action) { :update }
      let!(:record) { DefinedSource.create!(source_id: defined_source_id, name: 'mo') }
      let(:perform) { DefinedSourceMaterializer.perform(defined_source_url, action) }

      it "updates based on source_key" do
        perform
        expect(DefinedSource.count).to eq 1
      end

      it "updates the existing record" do
        perform
        inserted = DefinedSource.find_by(source_id: defined_source_id)
        expect(inserted.source_id).to eq defined_source_id
        expect(inserted.name).to eq defined_source_body[:name]
      end
    end

    context "when deleting an entity based on the source_key column" do
      let(:action) { :delete }
      let!(:record) { DefinedSource.create!(source_id: defined_source_id, name: 'mo') }
      let(:perform) { DefinedSourceMaterializer.perform(defined_source_url, action) }

      it "deletes based on source_key" do
        perform
        expect(DefinedSource.count).to eq 0
      end
    end
  end
end
