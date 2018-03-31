require 'spec_helper'
require 'support/uses_redis'
require 'materialist/materializer'

RSpec.describe Materialist::Materializer do
  uses_redis

  describe "#perform" do
    let!(:materializer_class) do
      FoobarMaterializer = Class.new do
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
    end

    let!(:city_materializer) do
      CityMaterializer = Class.new do
        include Materialist::Materializer

        persist_to :city
        source_key :source_url
        capture :name
      end
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
      stub_resource source_url, source_body
      stub_resource country_url, country_body
      stub_resource city_url, city_body
      stub_resource defined_source_url, defined_source_body
    end

    after do
      Object.send(:remove_const, :FoobarMaterializer)
      Object.send(:remove_const, :CityMaterializer)
    end

    let(:action) { :create }
    let(:perform) { materializer_class.perform(source_url, action) }
    let(:actions_called) { materializer_class.class_variable_get(:@@actions_called) }

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
      let(:error) { nil }
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }

      [ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid].each do |error_type|
        context "when error of type #{error_type.name} is thrown" do
          let(:error) { error_type }

          it "still updates the record" do
            expect(Foobar).to receive(:find_or_initialize_by).ordered.and_raise(error)
            expect(Foobar).to receive(:find_or_initialize_by).ordered.and_call_original
            expect{ perform }.to change { record.reload.name }
              .from('mo').to('jack')
          end

          context "if error was thrown second time" do
            it "bubbles up the error" do
              expect(Foobar).to receive(:find_or_initialize_by).and_raise(error).twice
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

    context "when {after, before}_upsert is configured" do
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }
      let!(:materializer_class) do
        FoobarMaterializer = Class.new do
          include Materialist::Materializer
          cattr_accessor(:actions_called) { {} }

          persist_to :foobar
          before_upsert :before_hook
          after_upsert :after_hook

          def before_hook(entity); self.actions_called[:before_hook] = true; end
          def after_hook(entity); self.actions_called[:after_hook] = true; end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "calls before_upsert method" do
            expect{ perform }.to change { actions_called[:before_hook] }
          end

          it "calls after_upsert method" do
            expect{ perform }.to change { actions_called[:after_hook] }
          end

          context "when configured with more than one hook" do
            let(:materializer_class) do
              FoobarMaterializer = Class.new do
                include Materialist::Materializer
                cattr_accessor(:actions_called) { {} }

                persist_to :foobar
                before_upsert :before_hook, :before_hook2
                after_upsert :after_hook, :after_hook2

                def before_hook(entity); self.actions_called[:before_hook] = true; end
                def before_hook2(entity); self.actions_called[:before_hook2] = true; end
                def after_hook(entity); self.actions_called[:after_hook] = true; end
                def after_hook2(entity); self.actions_called[:after_hook2] = true; end
              end
            end

            it "calls more than one method" do
              expect{ perform }.to  change { actions_called[:before_hook] }
                               .and change { actions_called[:before_hook2] }
                               .and change { actions_called[:after_hook] }
                               .and change { actions_called[:after_hook2] }
            end
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "does not call after_upsert method" do
          expect{ perform }.to_not change { actions_called[:after_hook] }
        end

        it "does call after_upsert method" do
          expect{ perform }.to_not change { actions_called[:before_hook] }
        end
      end

    end

    context "when {before, after}_destroy is configured" do
      let!(:record) { Foobar.create!(source_url: source_url, name: 'mo') }
      let!(:materializer_class) do
        FoobarMaterializer = Class.new do
          include Materialist::Materializer
          cattr_accessor(:actions_called) { {} }

          persist_to :foobar
          before_destroy :before_hook
          after_destroy :after_hook

          def before_hook(entity); self.actions_called[:before_hook] = true; end
          def after_hook(entity); self.actions_called[:after_hook] = true; end
        end
      end

      %i(create update noop).each do |action_name|
        context "when action is :#{action_name}" do
          let(:action) { action_name }
          it "does not call after_destroy method" do
            expect{ perform }.to_not change { actions_called[:after_hook] }
          end

          it "does not call before_destroy method" do
            expect{ perform }.to_not change { actions_called[:before_hook] }
          end
        end
      end

      context "when action is :delete" do
        let(:action) { :delete }

        it "calls after_destroy method" do
          expect{ perform }.to change { actions_called[:after_hook] }
        end

        it "calls before_destroy method" do
          expect{ perform }.to change { actions_called[:before_hook] }
        end

        context "when configured with more than one hook" do
          let(:materializer_class) do
            FoobarMaterializer = Class.new do
              include Materialist::Materializer
              cattr_accessor(:actions_called) { {} }

              persist_to :foobar
              before_destroy :before_hook, :before_hook2
              after_destroy :after_hook, :after_hook2

              def before_hook(entity); self.actions_called[:before_hook] = true; end
              def before_hook2(entity); self.actions_called[:before_hook2] = true; end
              def after_hook(entity); self.actions_called[:after_hook] = true; end
              def after_hook2(entity); self.actions_called[:after_hook2] = true; end
            end
          end

          it "calls more than one method" do
            expect{ perform }.to  change { actions_called[:before_hook] }
                             .and change { actions_called[:before_hook2] }
                             .and change { actions_called[:after_hook] }
                             .and change { actions_called[:after_hook2] }
          end
        end

        context "when resource doesn't exist locally" do
          it "does not raise error" do
            Foobar.delete_all
            expect{ perform }.to_not raise_error
          end
        end
      end
    end

    context "when not materializing self but materializing linked parent" do
      subject do
        Class.new do
          include Materialist::Materializer

          materialize_link :city
        end
      end
      let(:city_settings_url) { 'https://service.dev/city_settings/1' }
      let(:city_settings_body) {{ _links: { city: { href: city_url }}}}
      before { stub_resource city_settings_url, city_settings_body }

      let(:perform) { subject.perform(city_settings_url, action) }

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

    context "entity based on the source_key column" do
      subject do
        Class.new do
          include Materialist::Materializer

          persist_to :defined_source

          source_key :source_id do |url|
            url.split('/').last.to_i
          end

          capture :name
        end
      end

      context "when creating" do
        let(:perform) { subject.perform(defined_source_url, action) }

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

      context "when updating" do
        let(:action) { :update }
        let!(:record) { DefinedSource.create!(source_id: defined_source_id, name: 'mo') }
        let(:perform) { subject.perform(defined_source_url, action) }

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

      context "when deleting" do
        let(:action) { :delete }
        let!(:record) { DefinedSource.create!(source_id: defined_source_id, name: 'mo') }
        let(:perform) { subject.perform(defined_source_url, action) }

        it "deletes based on source_key" do
          perform
          expect(DefinedSource.count).to eq 0
        end
      end
    end
  end
end
