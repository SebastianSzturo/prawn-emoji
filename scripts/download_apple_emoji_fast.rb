#!/usr/bin/env ruby
# frozen_string_literal: true

# Fast parallel downloader for Apple emoji from Emojipedia CDN
# Uses thread pool for concurrent downloads

require 'net/http'
require 'uri'
require 'yaml'
require 'fileutils'
require 'json'
require 'open-uri'

$stdout.sync = true  # Unbuffered output

APPLE_VERSION = 419
CDN_BASE = "https://em-content.zobj.net/source/apple/#{APPLE_VERSION}"
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)
INDEX_FILE = File.expand_path('../emoji/index.yml', __dir__)
CACHE_FILE = File.expand_path('../.context/emoji_cache.json', __dir__)
FAILED_FILE = File.expand_path('../.context/failed_emoji.txt', __dir__)
EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
EMOJI_TEST_CACHE = File.expand_path('../.context/emoji-test.txt', __dir__)

THREAD_COUNT = 20

SLUG_OVERRIDES = {
  '0023-20e3' => 'keycap-number-sign',
  '002a-20e3' => 'keycap-asterisk',
  '0030-20e3' => 'keycap-digit-zero',
  '0031-20e3' => 'keycap-digit-one',
  '0032-20e3' => 'keycap-digit-two',
  '0033-20e3' => 'keycap-digit-three',
  '0034-20e3' => 'keycap-digit-four',
  '0035-20e3' => 'keycap-digit-five',
  '0036-20e3' => 'keycap-digit-six',
  '0037-20e3' => 'keycap-digit-seven',
  '0038-20e3' => 'keycap-digit-eight',
  '0039-20e3' => 'keycap-digit-nine',
  '00a9' => 'copyright',
  '00ae' => 'registered',
  '1f170' => 'a-button-blood-type',
  '1f171' => 'b-button-blood-type',
  '1f17e' => 'o-button-blood-type',
  '1f17f' => 'p-button',
  '1f1e6-1f1fd' => 'flag-aland-islands',
  '1f1e7-1f1f1' => 'flag-st-barthelemy',
  '1f1e8-1f1ee' => 'flag-cote-divoire',
  '1f1e8-1f1fc' => 'flag-curacao',
  '1f1f7-1f1ea' => 'flag-reunion',
  '1f1f8-1f1f9' => 'flag-sao-tome-principe',
  '1f1f9-1f1f7' => 'flag-turkiye',
  '1f1fa-1f1f2' => 'flag-us-outlying-islands',
  '1f1fb-1f1ee' => 'flag-us-virgin-islands',
}

SKIP_CODEPOINTS = %w[
  1f1e6 1f1e7 1f1e8 1f1e9 1f1ea 1f1eb 1f1ec 1f1ed 1f1ee 1f1ef
  1f1f0 1f1f1 1f1f2 1f1f3 1f1f4 1f1f5 1f1f6 1f1f7 1f1f8 1f1f9
  1f1fa 1f1fb 1f1fc 1f1fd 1f1fe 1f1ff
  1f3fb 1f3fc 1f3fd 1f3fe 1f3ff
]

def download_emoji_test
  FileUtils.mkdir_p(File.dirname(EMOJI_TEST_CACHE))
  unless File.exist?(EMOJI_TEST_CACHE)
    puts "Downloading Unicode emoji-test.txt..."
    content = URI.open(EMOJI_TEST_URL).read
    File.write(EMOJI_TEST_CACHE, content)
  end
  File.read(EMOJI_TEST_CACHE)
end

def parse_emoji_test(content)
  mapping = {}
  content.each_line do |line|
    line = line.strip
    next if line.start_with?('#') || line.empty?
    parts = line.split(';')
    next unless parts.length >= 2
    codepoints_raw = parts[0].strip
    rest = parts[1]
    if rest =~ /^\s*(fully-qualified|minimally-qualified|unqualified|component)\s*#\s*.+?\s+E[\d.]+\s+(.+)$/
      status = $1
      name = $2.strip
      codepoints = codepoints_raw.downcase.split(/\s+/).join('-')
      slug = name.downcase.gsub(/[''`´]/, '').gsub(/[:\s]+/, '-').gsub(/[^a-z0-9\-]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
      if status == 'fully-qualified' || !mapping[codepoints]
        mapping[codepoints] = slug
      end
    end
  end
  mapping
end

def download_single(codepoint, slug)
  url = "#{CDN_BASE}/#{slug}_#{codepoint}.png"
  output_path = File.join(EMOJI_DIR, "#{codepoint}.png")

  uri = URI(url)
  begin
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10
    response = http.get(uri.path)
    if response.code == '200' && response.body.size > 100
      File.binwrite(output_path, response.body)
      return true
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
  FileUtils.mkdir_p(File.dirname(CACHE_FILE))
  File.write(CACHE_FILE, JSON.pretty_generate(cache))
end

def main
  puts "=" * 60
  puts "Apple Emoji Fast Downloader (#{THREAD_COUNT} threads)"
  puts "=" * 60

  emoji_test = download_emoji_test
  name_mapping = parse_emoji_test(emoji_test)
  puts "Loaded #{name_mapping.size} emoji mappings"

  codepoints = YAML.load_file(INDEX_FILE)
  puts "Found #{codepoints.length} emojis in index"

  FileUtils.mkdir_p(EMOJI_DIR)
  cache = load_cache

  # Filter out skipped and already cached
  to_download = []
  codepoints.each do |cp|
    cp = cp.to_s.downcase
    next if SKIP_CODEPOINTS.include?(cp)
    output_path = File.join(EMOJI_DIR, "#{cp}.png")
    next if cache[cp] && File.exist?(output_path) && File.size(output_path) > 100
    slug = SLUG_OVERRIDES[cp] || name_mapping[cp]
    next unless slug
    to_download << [cp, slug]
  end

  puts "Need to download: #{to_download.length} emojis"
  puts "Starting download with #{THREAD_COUNT} threads..."

  mutex = Mutex.new
  success = 0
  failed = 0
  failed_list = []

  threads = []
  queue = Queue.new
  to_download.each { |item| queue << item }
  THREAD_COUNT.times { queue << nil }  # Sentinel values

  THREAD_COUNT.times do
    threads << Thread.new do
      while (item = queue.pop)
        cp, slug = item
        if download_single(cp, slug)
          mutex.synchronize do
            cache[cp] = true
            success += 1
            if success % 100 == 0
              puts "Downloaded #{success}/#{to_download.length}..."
              save_cache(cache)
            end
          end
        else
          mutex.synchronize do
            failed += 1
            failed_list << cp
          end
        end
      end
    end
  end

  threads.each(&:join)
  save_cache(cache)

  puts "\n" + "=" * 60
  puts "Download complete!"
  puts "Success: #{success}"
  puts "Failed: #{failed}"

  if failed_list.any?
    File.write(FAILED_FILE, failed_list.join("\n"))
    puts "Failed list saved to: .context/failed_emoji.txt"
  end
end

main
