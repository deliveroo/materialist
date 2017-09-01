module RspecSupportUsesRedis
  def uses_redis
    let(:redis) { ::Redis.new }

    before do
      redis.flushall
    end
  end
end

RSpec.configure { |c| c.extend RspecSupportUsesRedis }
