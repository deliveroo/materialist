require 'spec_helper'
require 'materialist/materializer/internals'

include Materialist::Materializer::Internals

RSpec.describe Materialist::Materializer::Internals::FieldMapping, type: :internals do
  describe '#map' do
    let(:resource) do
      {
        a: 1,
        b: {
          c: 2,
          d: {
            e: 3
          }
        }
      }
    end
    let(:map) { described_class.new(key: key, as: :z).map(resource) }

    context 'when a single key is passed' do
      let(:key) { :a }
      let(:expected_result) { { z: 1 } }

      it { expect(map).to eq(expected_result) }
    end

    context 'when a single key is passed that does not exist' do
      let(:key) { :c }
      let(:expected_result) { { z: nil } }

      it { expect(map).to eq(expected_result) }
    end

    context 'when an array of keys is passed' do
      let(:key) { [:b, :d] }
      let(:expected_result) { { z: { e: 3 } } }

      it { expect(map).to eq(expected_result) }
    end

    context 'when an array of keys that does not exist is passed' do
      let(:key) { [:b, :d, :f] }
      let(:expected_result) { { z: nil } }

      it { expect(map).to eq(expected_result) }
    end
  end
end
