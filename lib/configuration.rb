module Materialist
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def configure
      yield(self.configuration)
    end
  end

  class Configuration
    attr_accessor :topics, :sidekiq_options, :metrics_client

    def initialize
      @topics = []
      @sidekiq_options = {}
      @metrics_client = NullMetricsClient
    end

    class NullMetricsClient
      def self.increment(_, tags:); end
      def self.histogram(_, _v, tags:); end
    end
  end
end
