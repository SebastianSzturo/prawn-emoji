#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to download Apple emoji from Emojipedia CDN
# Uses Unicode emoji-test.txt to map codepoints to names
# Falls back to scraping Emojipedia pages for failed downloads

require 'net/http'
require 'uri'
require 'yaml'
require 'fileutils'
require 'json'
require 'open-uri'

APPLE_VERSION = 419 # iOS 18.4
CDN_BASE = "https://em-content.zobj.net/source/apple/#{APPLE_VERSION}"
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)
INDEX_FILE = File.expand_path('../emoji/index.yml', __dir__)
CACHE_FILE = File.expand_path('../.context/emoji_cache.json', __dir__)
EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
EMOJI_TEST_CACHE = File.expand_path('../.context/emoji-test.txt', __dir__)

# Special name overrides where Unicode names don't match Emojipedia slugs
SLUG_OVERRIDES = {
  # Keycaps
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

  # Special symbols
  '00a9' => 'copyright',
  '00ae' => 'registered',

  # Blood type buttons
  '1f170' => 'a-button-blood-type',
  '1f171' => 'b-button-blood-type',
  '1f17e' => 'o-button-blood-type',
  '1f17f' => 'p-button',

  # Flags with special characters
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

# Codepoints that are component emoji without standalone images
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

      # Convert to slug
      slug = name.downcase
      slug = slug.gsub(/[''`´]/, '')          # Remove apostrophes
      slug = slug.gsub(/[:\s]+/, '-')         # Spaces/colons to hyphens
      slug = slug.gsub(/[^a-z0-9\-]/, '-')    # Other chars to hyphens
      slug = slug.gsub(/-+/, '-')             # Collapse hyphens
      slug = slug.gsub(/^-|-$/, '')           # Trim hyphens

      if status == 'fully-qualified' || !mapping[codepoints]
        mapping[codepoints] = slug
      end
    end
  end

  mapping
end

def download_image(url, output_path)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10

  begin
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess) && response.body.size > 100
      File.binwrite(output_path, response.body)
      return true
    end
  rescue => e
    # Silently fail
  end

  false
end

def scrape_image_url(codepoint)
  # Convert codepoint to emoji character
  chars = codepoint.split('-').map { |cp| cp.to_i(16) }.pack('U*')

  uri = URI("https://emojipedia.org/apple/ios-18.4/#{URI.encode_www_form_component(chars)}")

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10

  begin
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'
    response = http.request(request)

    # Follow redirect if needed
    if response.is_a?(Net::HTTPRedirection)
      location = response['location']
      if location
        redirect_uri = location.start_with?('http') ? URI(location) : URI("https://emojipedia.org#{location}")
        request = Net::HTTP::Get.new(redirect_uri)
        request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'
        response = http.request(request)
      end
    end

    if response.is_a?(Net::HTTPSuccess)
      body = response.body
      if body =~ /https:\/\/em-content\.zobj\.net\/source\/apple\/#{APPLE_VERSION}\/[^"'\s]+\.png/
        return $&
      end
    end
  rescue => e
    # Silently fail
  end

  nil
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
  puts "Apple Emoji Downloader"
  puts "=" * 60

  # Download and parse Unicode emoji data
  emoji_test = download_emoji_test
  name_mapping = parse_emoji_test(emoji_test)
  puts "Loaded #{name_mapping.size} emoji name mappings from Unicode data"
  puts "Added #{SLUG_OVERRIDES.size} manual slug overrides"
  puts "Skipping #{SKIP_CODEPOINTS.size} component codepoints"

  # Load emoji index
  puts "\nLoading emoji index..."
  codepoints = YAML.load_file(INDEX_FILE)
  puts "Found #{codepoints.length} emojis in index"

  FileUtils.mkdir_p(EMOJI_DIR)

  cache = load_cache

  success = 0
  failed = 0
  skipped = 0
  scraped = 0
  failed_list = []

  codepoints.each_with_index do |codepoint, index|
    codepoint = codepoint.to_s.downcase

    # Skip component emoji
    if SKIP_CODEPOINTS.include?(codepoint)
      skipped += 1
      next
    end

    output_path = File.join(EMOJI_DIR, "#{codepoint}.png")

    # Skip if already downloaded and in cache
    if cache[codepoint] && File.exist?(output_path) && File.size(output_path) > 100
      skipped += 1
      next
    end

    # Get slug from override or mapping
    slug = SLUG_OVERRIDES[codepoint] || name_mapping[codepoint]

    downloaded = false

    if slug
      # Try URL construction first
      url = "#{CDN_BASE}/#{slug}_#{codepoint}.png"
      downloaded = download_image(url, output_path)
    end

    # Fallback: scrape the page
    unless downloaded
      scraped_url = scrape_image_url(codepoint)
      if scraped_url
        downloaded = download_image(scraped_url, output_path)
        scraped += 1 if downloaded
      end
    end

    if downloaded
      cache[codepoint] = true
      success += 1

      if success % 100 == 0
        puts "[#{index + 1}/#{codepoints.length}] Downloaded #{success} emojis (#{scraped} via scraping)..."
        save_cache(cache)
      end
    else
      failed += 1
      failed_list << codepoint
    end
  end

  save_cache(cache)

  puts "\n" + "=" * 60
  puts "Download complete!"
  puts "=" * 60
  puts "Success: #{success} (#{scraped} via page scraping)"
  puts "Skipped (cached/components): #{skipped}"
  puts "Failed: #{failed}"

  if failed_list.any?
    puts "\nFailed codepoints (first 30):"
    failed_list.first(30).each { |cp| puts "  - #{cp}" }
    puts "  ... and #{failed_list.size - 30} more" if failed_list.size > 30

    # Save failed list for debugging
    File.write(File.expand_path('../.context/failed_emoji.txt', __dir__), failed_list.join("\n"))
  end
end

main if __FILE__ == $0
