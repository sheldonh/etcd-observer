#!/usr/bin/env ruby

require 'logger'
require 'net/http'

require 'rubygems'
require 'json'

def get_peers_from_env(env)
  if env['ETCD_PEERS']
    env['ETCD_PEERS'].split
  else
    address = env['ETCD_PORT_4001_TCP_ADDR'] || '127.0.0.1'
    port = env['ETCD_PORT_4001_TCP_PORT'] || '4001'
    [ 'http://' + address + ':' + port ]
  end
end

def get_notify_url_from_env(env)
  if env['NOTIFY_URL']
    env['NOTIFY_URL']
  else
    address = env['NOTIFY_PORT_8080_TCP_ADDR'] || '127.0.0.1'
    port = env['NOTIFY_PORT_8080_TCP_PORT'] || '8080'
    path = env['NOTIFY_PATH'] || '/'
    'http://' + address + ':' + port + path
  end
end

key = ENV['ETCD_KEY'] or raise "no ETCD_KEY given"
peers = get_peers_from_env(ENV).map { |x| URI(x + '/v2/keys' + key) }
notify_url = URI(get_notify_url_from_env(ENV))
logger = Logger.new($stderr)

watch = false
loop do
  begin
    key_url = peers.sample.dup
    if watch
      logger.info "watching #{key_url}"
      key_url = URI.join(key_url, "?wait=true")
    else
      logger.info "fetching #{key_url}"
    end
    json = Net::HTTP.get(key_url)
    value = JSON.parse(json)['node']['value']

    Net::HTTP.start(notify_url.host, notify_url.port) do |http|
      logger.info "notifying #{notify_url}:\n#{value.chomp}"
      req = Net::HTTP::Put.new(notify_url)
      req.body = value
      res = http.request(req)
      if res.code[0] == '2'
        logger.info "notification receiver success: #{res.body.chomp}"
        watch = true
      else
        logger.error "notification receiver error: #{res.body.chomp}"
        watch = false
      end
    end
  rescue Exception => e
    logger.error "#{e.class}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
    sleep 1
    watch = false
    next
  end
end
