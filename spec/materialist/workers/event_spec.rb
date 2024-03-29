require 'spec_helper'
require 'materialist/workers/event'
require 'routemaster/api_client'

RSpec.describe Materialist::Workers::Event do
  describe "#perform" do
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:event) {{ 'topic' => :foobar, 'url' => source_url, 'type' => 'noop' }}
    let!(:materializer_class) { FoobarMaterializer = Class.new }
    let(:metrics_client) { double(increment: true) }

    before do
      allow(FoobarMaterializer).to receive(:perform)
      Materialist.configure do |c|
        c.metrics_client = metrics_client
        c.api_client = Routemaster::APIClient.new(response_class: ::Routemaster::Responses::HateoasResponse)
      end
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

    it 'does not log latency' do
      expect(metrics_client).to_not receive(:histogram)
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

      context 'when there is notice_error configured' do
        let(:configuration) { Materialist::Configuration.new.tap{ |c| c.notice_error = func } }
        let(:func) { double }

        before do
          allow(Materialist).to receive(:configuration).and_return configuration
        end

        it 'calls the configured notice_error func' do
          expect(func).to receive(:call).with(error, event)
          expect{ perform }.to raise_error error
        end
      end
    end

    context 'when event has a timestamp' do
      let(:event) {{ 'topic' => :foobar, 'url' => source_url, 'type' => 'noop', 't' => '1519659773842' }}

      it 'logs latency to metrics' do
        expect(metrics_client).to receive(:histogram).with(
          "materialist.event_latency",
          instance_of(Float),
          tags: ["topic:foobar"]
        )
        perform
      end
    end
  end
end
