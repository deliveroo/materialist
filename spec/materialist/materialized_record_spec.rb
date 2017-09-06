require 'spec_helper'
require 'support/uses_redis'
require 'materialist/materialized_record'

RSpec.describe Materialist::MaterializedRecord do
  uses_redis

  let!(:materialized_type) do
    class Foobar
      include Materialist::MaterializedRecord

      attr_accessor :source_url

      source_link_reader :city
      source_link_reader :device, allow_nil: true
      source_link_reader :country, via: :city
      source_link_reader :region, via: :city, allow_nil: true
    end
  end

  let(:record) do
    Foobar.new.tap { |r| r.source_url = source_url }
  end

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

  describe "#source" do
    it "returns the representation of the source" do
      expect(record.source.name).to eq 'jack'
      expect(record.source.age).to eq 30
    end

    context "when remote source returns 404" do
      before do
        stub_request(:get, source_url).to_return(status: 404)
      end

      it "bubbles up routemaster error" do
        expect{ record.source }.to raise_error(Routemaster::Errors::ResourceNotFound)
      end
    end
  end

  describe "simple link reader" do
    it "returns the representation of the link source" do
      expect(record.city.timezone).to eq 'Europe/Paris'
    end

    context "when linked resource returns 404" do
      before do
        stub_request(:get, city_url).to_return(status: 404)
      end

      it { expect{ record.city }.to raise_error Materialist::ResourceNotFound }
    end

    context "remote source is not linked to city" do
      let(:source_body) {{ _links: { }, name: 'jack', age: 30 }}

      it { expect{ record.city }.to raise_error Materialist::ResourceNotFound }
    end

    context "when nil is allowed" do
      let(:device_url) { 'https://service.dev/devices/1' }
      let(:source_body) {{ _links: { device: { href: device_url }}, name: 'jack', age: 30 }}

      context "when linked resource returns 404" do
        before do
          stub_request(:get, device_url).to_return(status: 404)
        end

        it { expect(record.device).to be_nil }
      end

      context "remote source is not linked to device" do
        let(:source_body) {{ _links: { }, name: 'jack', age: 30 }}

        it { expect(record.device).to be_nil }
      end
    end

  end

  describe "simple link reader via another link" do
    it "returns the representation of the link source" do
      expect(record.country.tld).to eq 'fr'
    end

    context "when remote city returns 404" do
      before do
        stub_request(:get, city_url).to_return(status: 404)
      end

      it { expect{ record.country }.to raise_error Materialist::ResourceNotFound }
    end

    context "when remote country returns 404" do
      before do
        stub_request(:get, country_url).to_return(status: 404)
      end

      it { expect{ record.country }.to raise_error Materialist::ResourceNotFound }
    end

    context "remote source is not linked to city" do
      let(:source_body) {{ _links: { }, name: 'jack', age: 30 }}

      it { expect{ record.country }.to raise_error Materialist::ResourceNotFound }
    end

    context "remote city is not linked to country" do
      let(:city_body) {{ _links: { }, timezone: 'Europe/Paris' }}

      it { expect{ record.country }.to raise_error Materialist::ResourceNotFound }
    end

    context "when nil is allowed" do

      context "when remote city returns 404" do
        before do
          stub_request(:get, city_url).to_return(status: 404)
        end

        it { expect(record.region).to be_nil }
      end

      context "remote city is not linked to region" do
        let(:city_body) {{ _links: { }, timezone: 'Europe/Paris' }}

        it { expect(record.region).to be_nil }
      end

      context "when region is defined" do
        let(:region_url) { 'https://service.dev/regions/1' }
        let(:city_body) {{ _links: { region: { href: region_url }}, timezone: 'Europe/Paris' }}

        context "when remote region returns 404" do
          before do
            stub_request(:get, region_url).to_return(status: 404)
          end

          it { expect(record.region).to be_nil }
        end

        context "remote source is not linked to city" do
          let(:city_body) {{ _links: {}, timezone: 'Europe/Paris' }}

          it { expect(record.region).to be_nil }
        end
      end
    end
  end
end
