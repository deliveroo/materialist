require 'spec_helper'
require 'materialist/event_handler'
require 'materialist/event_worker'

RSpec.describe Materialist::EventHandler do
  let(:options) {{}}
  subject { described_class.new options }

  let(:worker_double) { double() }
  before do
    allow(Materialist::EventWorker).to receive(:set)
      .and_return worker_double
  end

  describe "#on_events_received" do
    let(:events) {[{ "topic" => :topic_a }, { "topic" => :topic_b }]}
    let(:perform) { subject.on_events_received events.map() }

    context "when no topic is specified" do
      let(:options) {{ topics: [] }}

      it "doesn't enqueue any event" do
        expect(worker_double).to_not receive(:perform_async)
        perform
      end
    end

    context "when a topic is specified" do
      let(:options) {{ topics: [:topic_a] }}

      it "enqueues event of that topic" do
        expect(worker_double).to receive(:perform_async).with(events[0])
        perform
      end
    end

    context "when both topics are specified" do
      let(:options) {{ topics: [:topic_a, :topic_b] }}

      it "enqueues event of both topics" do
        expect(worker_double).to receive(:perform_async).twice
        perform
      end
    end
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
      let(:options) {{ queue: queue_name }}

      it "enqueues the event in the given queue" do
        expect(Materialist::EventWorker).to receive(:set)
          .with(queue: queue_name)
        expect(worker_double).to receive(:perform_async).with(event)
        perform
      end
    end
  end
end
