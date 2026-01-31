#!/usr/bin/env ruby
# frozen_string_literal: true

# Browser-based scraper for Apple emoji using Playwright
# This script reads the list of failed emoji codepoints and scrapes their image URLs

require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'yaml'

$stdout.sync = true

APPLE_VERSION = 419
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)
INDEX_FILE = File.expand_path('../emoji/index.yml', __dir__)
FAILED_FILE = File.expand_path('../.context/failed_emoji.txt', __dir__)
SCRAPED_URLS_FILE = File.expand_path('../.context/scraped_urls.json', __dir__)

# Skip component emoji that don't have images
SKIP_CODEPOINTS = %w[
  1f1e6 1f1e7 1f1e8 1f1e9 1f1ea 1f1eb 1f1ec 1f1ed 1f1ee 1f1ef
  1f1f0 1f1f1 1f1f2 1f1f3 1f1f4 1f1f5 1f1f6 1f1f7 1f1f8 1f1f9
  1f1fa 1f1fb 1f1fc 1f1fd 1f1fe 1f1ff
  1f3fb 1f3fc 1f3fd 1f3fe 1f3ff
]

def codepoint_to_char(codepoint)
  codepoint.split('-').map { |cp| cp.to_i(16) }.pack('U*')
end

def load_scraped_urls
  return {} unless File.exist?(SCRAPED_URLS_FILE)
  JSON.parse(File.read(SCRAPED_URLS_FILE))
rescue
  {}
end

def save_scraped_urls(urls)
  File.write(SCRAPED_URLS_FILE, JSON.pretty_generate(urls))
end

def download_image(url, output_path)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 15

  begin
    response = http.get(uri.path)
    if response.code == '200' && response.body.size > 100
      File.binwrite(output_path, response.body)
      return true
    end
  rescue => e
    puts "  Download error: #{e.message}"
  end
  false
end

def main
  # Load failed codepoints
  if File.exist?(FAILED_FILE)
    failed_list = File.readlines(FAILED_FILE).map(&:strip).reject(&:empty?)
  else
    # If no failed file, check which emojis are still small (Twemoji)
    codepoints = YAML.load_file(INDEX_FILE).map { |cp| cp.to_s.downcase }
    failed_list = codepoints.select do |cp|
      next false if SKIP_CODEPOINTS.include?(cp)
      path = File.join(EMOJI_DIR, "#{cp}.png")
      !File.exist?(path) || File.size(path) < 10000
    end
  end

  puts "Found #{failed_list.length} emojis to scrape"

  # Load previously scraped URLs
  scraped_urls = load_scraped_urls

  # Output list for manual browser scraping
  output_file = File.expand_path('../.context/emoji_urls_to_scrape.txt', __dir__)

  puts "\nGenerating URL list for browser scraping..."

  lines = failed_list.reject { |cp| SKIP_CODEPOINTS.include?(cp) }.map do |codepoint|
    next if scraped_urls[codepoint]

    chars = codepoint_to_char(codepoint)
    encoded = URI.encode_www_form_component(chars)
    url = "https://emojipedia.org/apple/ios-18.4/#{encoded}"
    "#{codepoint}\t#{url}"
  end.compact

  File.write(output_file, lines.join("\n"))
  puts "Wrote #{lines.length} URLs to #{output_file}"

  # Now download any previously scraped URLs
  scraped_count = 0
  scraped_urls.each do |codepoint, url|
    output_path = File.join(EMOJI_DIR, "#{codepoint}.png")
    next if File.exist?(output_path) && File.size(output_path) > 100

    if download_image(url, output_path)
      scraped_count += 1
      puts "Downloaded: #{codepoint}" if scraped_count % 50 == 0
    end
  end

  puts "\nDownloaded #{scraped_count} emojis from cached URLs"
  puts "\nTo complete scraping, run Playwright to visit each URL and extract image URLs"
end

main
