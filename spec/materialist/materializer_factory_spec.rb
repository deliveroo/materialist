require 'spec_helper'
require 'materialist/materializer_factory'

RSpec.describe Materialist::MaterializerFactory do
  class BuffaloMozarellaMaterializer; end

  describe '.class_from_topic' do
    subject { described_class.class_from_topic(topic) }

    context 'when the materializer class exists' do
      let(:topic) { 'buffalo_mozarella'}

      it 'returns the class' do
        is_expected.to eql(BuffaloMozarellaMaterializer)
      end
    end

    context 'when the materializer class does not exist' do
      let(:topic) { 'cheddar' }

      it { is_expected.to be nil }
    end
  end
end
