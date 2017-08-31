require 'spec_helper'
require 'materialist/event_worker'

RSpec.describe Materialist::EventWorker do
  describe "#perform" do
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:event) {{ 'topic' => :foobar, 'url' => source_url, 'type' => 'noop' }}
    let!(:materializer_class) { class FoobarMaterializer; end }

    before do
      allow(FoobarMaterializer).to receive(:perform)
    end

    context "when run synchronously" do
      let(:perform) { subject.perform(event) }

      it "calls the relevant materializer" do
        expect(FoobarMaterializer).to receive(:perform).with(source_url, :noop)
        perform
      end
    end
  end
end
