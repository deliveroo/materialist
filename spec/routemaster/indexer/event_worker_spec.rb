require 'spec_helper'
require 'routemaster/indexer/event_worker'

RSpec.describe Routemaster::Indexer::EventWorker do
  describe "#perform" do
    let(:source_url) { 'https://service.dev/foobars/1' }
    let(:event) {{ 'topic' => :foobar, 'url' => source_url }}
    let!(:indexer_class) { class FoobarIndexer; end }

    before do
      allow(FoobarIndexer).to receive(:perform)
    end

    context "when run synchronously" do
      let(:perform) { subject.perform(event) }

      it "calls the relevant indexer" do
        expect(FoobarIndexer).to receive(:perform).with(source_url)
        perform
      end
    end
  end
end
