require_relative 'workers/event'

# This class is here for backwards compatibility with pre 3.1 versions. It can be removed with the
# next major version (4.0)
module Materialist
  class EventWorker < Workers::Event
    def perform(event)
      super(event)
    end
  end
end
