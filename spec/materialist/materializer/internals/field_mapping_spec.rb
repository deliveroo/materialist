require 'spec_helper'
require 'materialist/materializer/internals'

include Materialist::Materializer::Internals

RSpec.describe Materialist::Materializer::Internals::FieldMapping, type: :internals do
  let(:instance) { described_class.new(key: key, as: as, value_parser: value_parser_block) }

  describe '#map' do
    let(:key) { :b }
    let(:as) { :z }
    let(:value_parser_block) { nil }
    let(:resource) do
      {
        a: 1,
        b: {
          c: 2
        }
      }
    end
    let(:map) { instance.map(resource) }

    context 'when no parse block is passed' do
      let(:expected_result) { { z: { c: 2 } } }

      it { expect(map).to eq(expected_result) }
    end

    context 'when a value parse block is passed' do
      let(:value_parser_block) { ->value { value[:c] } }
      let(:expected_result) { { z: 2 } }

      it { expect(map).to eq(expected_result) }
    end
  end
end
