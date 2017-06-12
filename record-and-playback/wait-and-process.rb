require 'redis'
require 'json'

RECORDINGS_CHANNEL = "bigbluebutton:from-rap"

redis_host = ENV['REDIS_HOST'] || '127.0.0.1'
redis_port = ENV['REDIS_PORT'] || 6379

# Set the environment variables in the configuration file
config = 'bigbluebutton.yml'
text = File.read(config)
new_contents = text.gsub(/redis_host:.*$/, "redis_host: #{redis_host}")
                   .gsub(/redis_port:.*$/, "redis_port: #{redis_port}")
File.open(config, 'w') {|file| file.puts new_contents }

puts "Connecting to redis on #{redis_host}:#{redis_port}"
redis = Redis.new(:host => redis_host, :port => redis_port)

# Wrapper to simplify getting an attribute from the redis data
def msg_attr(message, attr)
  case attr
  when 'name'
    message["header"] ? message["header"]["name"] : nil
  when 'id'
    message["payload"] ? message["payload"]["meeting_id"] : nil
  end
end

# Listen to redis and process a recording when it's available for processing
redis.subscribe(RECORDINGS_CHANNEL) do |on|
  on.message do |channel, message|
    data = JSON.parse(message)
    puts "Got event: #{channel}, #{data}"

    if msg_attr(data, 'name') == 'sanity_ended'
      id = msg_attr(data, 'id')
      puts "Detected recording #{id}, will process it"
      pid = spawn("ruby rap-process-worker.rb -m #{id} && ruby rap-publish-worker.rb -m #{id}")
      puts "Spawned process #{pid} to process #{id}"
    end
  end
end
