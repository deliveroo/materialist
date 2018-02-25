require 'spec_helper'
require 'materialist/event_worker'

RSpec.describe Materialist::EventWorker do
  describe "#perform" do
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:event) {{ 'topic' => :foobar, 'url' => source_url, 'type' => 'noop' }}
    let!(:materializer_class) { FoobarMaterializer = Class.new }
    let(:metrics_client) { double(increment: true) }

    before do
      allow(FoobarMaterializer).to receive(:perform)
      Materialist.configure { |c| c.metrics_client = metrics_client }
    end

    after { Object.send(:remove_const, :FoobarMaterializer) }

    let(:perform) { subject.perform(event) }

    it "calls the relevant materializer" do
      expect(FoobarMaterializer).to receive(:perform).with(source_url, :noop)
      perform
    end

    it 'logs success to metrics' do
      expect(metrics_client).to receive(:increment).with(
        "materialist.event_worker.success",
        tags: ["action:noop", "topic:foobar"]
      )
      perform
    end

    context 'when there is an error' do
      let(:error){ StandardError.new }
      before do
        expect(FoobarMaterializer).to receive(:perform).and_raise error
      end

      it 'logs failure to metrics and re-raises the error' do
        expect(metrics_client).to receive(:increment).with(
          "materialist.event_worker.failure",
          tags: ["action:noop", "topic:foobar"]
        )
        expect{ perform }.to raise_error error
      end
    end
  end
end
