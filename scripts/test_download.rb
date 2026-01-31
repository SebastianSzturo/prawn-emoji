#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "yaml"
require "open-uri"
require "fileutils"

APPLE_VERSION = 419
CDN_BASE = "https://em-content.zobj.net/source/apple/#{APPLE_VERSION}"
EMOJI_DIR = File.expand_path("../emoji/images", __dir__)
EMOJI_TEST_CACHE = File.expand_path("../.context/emoji-test.txt", __dir__)

FileUtils.mkdir_p(File.dirname(EMOJI_TEST_CACHE))

# Download emoji-test.txt if needed
unless File.exist?(EMOJI_TEST_CACHE)
  puts "Downloading emoji-test.txt..."
  content = URI.open("https://unicode.org/Public/emoji/latest/emoji-test.txt").read
  File.write(EMOJI_TEST_CACHE, content)
end

# Parse to get codepoint -> slug mapping
mapping = {}
File.readlines(EMOJI_TEST_CACHE).each do |line|
  line = line.strip
  next if line.start_with?("#") || line.empty?

  parts = line.split(";")
  next unless parts.length >= 2

  codepoints_raw = parts[0].strip
  rest = parts[1]

  if rest =~ /^\s*(fully-qualified|minimally-qualified|unqualified|component)\s*#\s*.+?\s+E[\d.]+\s+(.+)$/
    status = $1
    name = $2.strip
    codepoints = codepoints_raw.downcase.split(/\s+/).join("-")

    # Convert to slug
    slug = name.downcase
    slug = slug.gsub(/[''`´]/, "")       # Remove apostrophes
    slug = slug.gsub(/[:\s]+/, "-")       # Spaces to hyphens
    slug = slug.gsub(/[^a-z0-9\-]/, "-")  # Other chars to hyphens
    slug = slug.gsub(/-+/, "-")           # Collapse hyphens
    slug = slug.gsub(/^-|-$/, "")         # Trim hyphens

    if status == "fully-qualified" || !mapping[codepoints]
      mapping[codepoints] = slug
    end
  end
end

puts "Loaded #{mapping.size} mappings"

# Test download 5 emojis
test_cps = ["1f600", "1f990", "1f1fa-1f1f8", "2764-fe0f", "1f4a9"]
test_cps.each do |cp|
  slug = mapping[cp]
  if slug
    url = "#{CDN_BASE}/#{slug}_#{cp}.png"
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.get(uri.path)
    if response.code == "200"
      output = File.join(EMOJI_DIR, "#{cp}.png")
      File.binwrite(output, response.body)
      puts "✓ #{cp}: #{slug} (#{response.body.size} bytes)"
    else
      puts "✗ #{cp}: #{slug} - HTTP #{response.code}"
    end
  else
    puts "? #{cp}: no mapping"
  end
end
