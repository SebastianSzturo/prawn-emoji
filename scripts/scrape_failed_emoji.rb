#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrape URLs for failed emoji from Emojipedia pages

require 'net/http'
require 'uri'
require 'fileutils'
require 'json'

$stdout.sync = true

APPLE_VERSION = 419
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)
FAILED_FILE = File.expand_path('../.context/failed_emoji.txt', __dir__)
CACHE_FILE = File.expand_path('../.context/emoji_cache.json', __dir__)

THREAD_COUNT = 10

def codepoint_to_char(codepoint)
  codepoint.split('-').map { |cp| cp.to_i(16) }.pack('U*')
end

def scrape_and_download(codepoint)
  chars = codepoint_to_char(codepoint)
  output_path = File.join(EMOJI_DIR, "#{codepoint}.png")

  # Try the Apple-specific emoji page
  encoded = URI.encode_www_form_component(chars)
  uri = URI("https://emojipedia.org/apple/ios-18.4/#{encoded}")

  http = Net::HTTP.new('emojipedia.org', 443)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 15

  begin
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    response = http.request(request)

    # Follow redirect
    if response.is_a?(Net::HTTPRedirection)
      location = response['location']
      if location
        redirect_uri = location.start_with?('http') ? URI(location) : URI("https://emojipedia.org#{location}")
        request = Net::HTTP::Get.new(redirect_uri)
        request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        response = http.request(request)
      end
    end

    if response.is_a?(Net::HTTPSuccess)
      body = response.body

      # Find the Apple emoji image URL
      if body =~ /https:\/\/em-content\.zobj\.net\/source\/apple\/#{APPLE_VERSION}\/([^"'\s]+\.png)/
        image_url = $&

        # Download the image
        img_uri = URI(image_url)
        img_http = Net::HTTP.new(img_uri.host, 443)
        img_http.use_ssl = true
        img_response = img_http.get(img_uri.path)

        if img_response.is_a?(Net::HTTPSuccess) && img_response.body.size > 100
          File.binwrite(output_path, img_response.body)
          return true
        end
      end
    end
  rescue => e
    # Silently fail
  end

  false
end

def load_cache
  return {} unless File.exist?(CACHE_FILE)
  JSON.parse(File.read(CACHE_FILE))
rescue
  {}
end

def save_cache(cache)
  File.write(CACHE_FILE, JSON.pretty_generate(cache))
end

def main
  unless File.exist?(FAILED_FILE)
    puts "No failed emoji file found"
    return
  end

  failed_list = File.readlines(FAILED_FILE).map(&:strip).reject(&:empty?)
  puts "Found #{failed_list.length} failed emojis to retry"

  cache = load_cache

  mutex = Mutex.new
  success = 0
  still_failed = []

  queue = Queue.new
  failed_list.each { |cp| queue << cp }
  THREAD_COUNT.times { queue << nil }

  threads = []
  THREAD_COUNT.times do
    threads << Thread.new do
      while (codepoint = queue.pop)
        if scrape_and_download(codepoint)
          mutex.synchronize do
            cache[codepoint] = true
            success += 1
            puts "✓ #{codepoint} (#{success}/#{failed_list.length})" if success % 50 == 0
          end
        else
          mutex.synchronize { still_failed << codepoint }
        end
        sleep(0.1)  # Rate limit
      end
    end
  end

  threads.each(&:join)
  save_cache(cache)

  puts "\n" + "=" * 50
  puts "Retry complete!"
  puts "Success: #{success}"
  puts "Still failed: #{still_failed.length}"

  if still_failed.any?
    File.write(FAILED_FILE, still_failed.join("\n"))
    puts "Updated failed list"
  else
    File.delete(FAILED_FILE) if File.exist?(FAILED_FILE)
  end
end

main
