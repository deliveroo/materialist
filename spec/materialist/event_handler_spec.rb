require 'spec_helper'
require 'materialist/event_handler'
require 'materialist/event_worker'

RSpec.describe Materialist::EventHandler do
  let(:configuration) do
    OpenStruct.new({
      sidekiq_options: sidekiq_options,
      topics: topics
    })
  end
  let(:topics) {[]}
  let(:sidekiq_options) {{}}
  let(:materializer_class) { double(_sidekiq_options: {}) }
  let(:worker_double) { double() }

  before do
    allow(Materialist).to receive(:configuration).and_return(configuration)
    allow(Materialist::MaterializerFactory).to receive(:class_from_topic).and_return(materializer_class)
    allow(Materialist::EventWorker).to receive(:set).and_return(worker_double)
  end

  describe "#on_events_received" do
    let(:events) {[{ "topic" => :topic_a }, { "topic" => :topic_b }]}
    let(:perform) { subject.on_events_received events.map() }

    context "when no topic is specified" do
      let(:topics) {[]}

      it "doesn't enqueue any event" do
        expect(worker_double).to_not receive(:perform_async)
        perform
      end
    end

    context "when a topic is specified" do
      let(:topics) { %w(topic_a) }

      it "enqueues event of that topic" do
        expect(worker_double).to receive(:perform_async).with(events[0])
        perform
      end
    end

    context "when both topics are specified" do
      let(:topics) { %w(topic_a topic_b) }

      it "enqueues event of both topics" do
        expect(worker_double).to receive(:perform_async).twice
        perform
      end
    end
  end

  describe "#call" do
    subject { described_class.new.call(event) }

    let(:configuration) do
      OpenStruct.new({
        sidekiq_options: { unique: false, retry: 5 }
      })
    end
    let(:event) { { "topic" => topic, "data" => "data" } }
    let(:topic) { "foobar" }
    let(:materializer_class) { double(_sidekiq_options: materializer_sidekiq_options) }
    let(:materializer_sidekiq_options) { { queue: :dedicated, retry: 2 } }
    let(:expected_event_options) { { queue: :dedicated, retry: 2, unique: false } }
    let(:worker_class) { double(perform_async: nil) }

    before do
      allow(Materialist).to receive(:configuration).and_return(configuration)
      allow(Materialist::MaterializerFactory).to receive(:class_from_topic).with(topic).and_return(materializer_class)
      allow(Materialist::EventWorker).to receive(:set).with(expected_event_options).and_return(worker_class)
    end

    it "enqueues the event worker with sidekiq options merged from configuration, default and the materializer" do
      subject

      expect(worker_class).to have_received(:perform_async).with(event)
    end
  end
end
