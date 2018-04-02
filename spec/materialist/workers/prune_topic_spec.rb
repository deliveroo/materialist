require 'spec_helper'
require 'materialist/workers/prune_topic'

RSpec.describe Materialist::Workers::PruneTopic do
  describe "#perform" do
    subject { described_class.new.perform(topic) }

    let(:topic) { "some_topic" }
    let(:materializer_class) { double(prune!: nil) }

    before do
      allow(Materialist::MaterializerFactory).to receive(:class_from_topic).with(topic).and_return(materializer_class)
    end

    it "calls the prune! method on the correct materializer" do
      subject

      expect(materializer_class).to have_received(:prune!)
    end
  end
end
