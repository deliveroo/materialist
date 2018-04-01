require 'spec_helper'
require 'materialist/event_handler'
require 'materialist/event_worker'

RSpec.describe Materialist::EventHandler do
  let(:topics) {[]}
  let(:sidekiq_options) {{}}
  let(:worker_double) { double() }

  before do
    Materialist.configure do |config|
      config.sidekiq_options = sidekiq_options
      config.topics = topics
    end

    allow(Materialist::EventWorker).to receive(:set)
      .and_return worker_double
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
    subject { described_class.new.call }

    let(:event) { { "topic" => topic } }
    let(:topic) { :foobar }
    let(:configuration) do
      OpenStruct.new({
        sidekiq_options: sidekiq_options
      })
    end
    let(:sidekiq_options) { { "option_1" => "value" } }

    before do
      allow(Materialist).to receive(:configuration).and_return(configuration)
      allow(Materialist::MaterializerFactory).to receive(:class_from_topic).with(topic).and_return(materializer_class)
    end

    context "when the materializer class specifies a queue"
    context "when the materializer class does not specify a queue"
  end

  describe "#call" do
    let(:event) { { "topic" => :foobar } }
    let(:perform) { subject.call event }

    it "enqueues the event" do
      expect(worker_double).to receive(:perform_async).with(event)
      perform
    end

    context "if queue name is privided" do
      let(:queue_name) { :some_queue_name }
      let(:sidekiq_options) {{ queue: queue_name }}

      it "enqueues the event in the given queue" do
        expect(Materialist::EventWorker).to receive(:set)
          .with(queue: queue_name, retry: 10)
        expect(worker_double).to receive(:perform_async).with(event)
        perform
      end
    end

    context "when a retry is specified in options" do
      let(:sidekiq_options) {{ retry: false }}

      it "uses the given retry option for sidekiq" do
        expect(Materialist::EventWorker).to receive(:set)
          .with(retry: false)
        expect(worker_double).to receive(:perform_async).with(event)
        perform
      end
    end
  end
end
