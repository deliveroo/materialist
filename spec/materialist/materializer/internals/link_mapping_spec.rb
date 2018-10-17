require 'spec_helper'
require 'materialist/materializer/internals'

include Materialist::Materializer::Internals

RSpec.describe Materialist::Materializer::Internals::LinkMapping, type: :internals do
  let(:key) { :details }
  subject(:instance) { described_class.new(key: key, mapping: mappings) }
  let(:mappings) { [ FieldMapping.new(key: :name) ] }

  let(:url_sub) { 'https://deliveroo.co.uk/details/1001' }
  let(:payload) { { _links: { details: { href: url_sub } } } }
  let(:payload_sub) { { name: "jack", age: 20 } }

  let(:client) { double }
  let(:resource_class) { Materialist::Materializer::Internals::PayloadResource }
  let(:resource) { resource_class.new(payload, client: client) }
  let(:resource_sub) { resource_class.new(payload_sub, client: client) }

  before do
    allow(client).to receive(:get).with(url_sub, anything).and_return resource_sub
  end

  describe '#map' do
    subject(:perform) { instance.map resource }

    it 'returns a hash corresponding to the mapping' do
      is_expected.to eq({ name: 'jack' })
    end

    context 'when multiple mappings given' do
      let(:mappings) do
        [
          FieldMapping.new(key: :age),
          LinkMapping.new(key: :wont_find_me),
          FieldMapping.new(key: :name)
        ]
      end

      it 'returns a hash corresponding to the mapping' do
        is_expected.to eq({ age: 20, name: 'jack' })
      end
    end

    describe 'missing sub resource' do
      context 'when given link is not present' do
        let(:key) { :foo }

        it { is_expected.to be nil }
      end

      context 'when given link is malformed' do
        let(:payload) { { _links: { details: { foo: url_sub } } } }

        it { is_expected.to be nil }
      end

      context 'when client returns nil' do
        let(:resource_sub) { nil }

        it { is_expected.to be nil }
      end

      context 'when client throws not-found error' do
        before do
          allow(client).to receive(:get)
            .with(url_sub, anything)
            .and_raise Routemaster::Errors::ResourceNotFound.new(double(body: nil))
        end

        it { is_expected.to be nil }
      end

      context 'when caching enabled' do
        let(:instance) { described_class.new(key: key, mapping: mappings, enable_caching: true) }

        it 'passes on the option to client' do
          expect(client).to receive(:get)
            .with(url_sub, options: { enable_caching: true, response_class: HateoasResource})
          perform
        end
      end
    end
  end

end
