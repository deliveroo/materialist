require 'spec_helper'
require 'materialist/workers/prune_enabled_topics'

RSpec.describe Materialist::Workers::PruneEnabledTopics do
  describe "#perform" do
    subject { described_class.new.perform }

    let(:configuration) do
      OpenStruct.new({
        topics: [topic1, topic2]
      })
    end
    let(:topic1) { "topic1" }
    let(:topic2) { "topic2" }
    let(:materializer_class_topic1) { double(prune_enabled?: false) }
    let(:materializer_class_topic2) { double(prune_enabled?: true) }

    before do
      allow(Materialist).to receive(:configuration).and_return(configuration)
      allow(Materialist::MaterializerFactory).to receive(:class_from_topic).with(topic1).and_return(materializer_class_topic1)
      allow(Materialist::MaterializerFactory).to receive(:class_from_topic).with(topic2).and_return(materializer_class_topic2)
      allow(Materialist::Workers::PruneTopic).to receive(:perform_async)
    end

    it "enqueues the PruneTopic worker for the enabled topics" do
      subject

      expect(Materialist::Workers::PruneTopic).to have_received(:perform_async).with(topic2)
    end

    it "does not enqueue the PruneTopic worker for topics that are not enabled" do
      subject

      expect(Materialist::Workers::PruneTopic).not_to have_received(:perform_async).with(topic1)
    end
  end
end
