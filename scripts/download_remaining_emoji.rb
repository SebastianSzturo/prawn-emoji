#!/usr/bin/env ruby
# frozen_string_literal: true

# Download remaining fallback emojis with corrected slug names

require 'net/http'
require 'uri'
require 'fileutils'

$stdout.sync = true

CDN_BASE = "https://em-content.zobj.net/source/apple/419"
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)

# Corrected slug mappings based on actual CDN patterns
SLUG_MAP = {
  # Colored circles (need "large-" prefix)
  '1f534' => 'large-red-circle',
  '1f535' => 'large-blue-circle',
  '1f7e0' => 'large-orange-circle',
  '1f7e1' => 'large-yellow-circle',
  '1f7e2' => 'large-green-circle',
  '1f7e3' => 'large-purple-circle',
  '1f7e4' => 'large-brown-circle',

  # Colored squares (need "large-" prefix)
  '1f7e5' => 'large-red-square',
  '1f7e6' => 'large-blue-square',
  '1f7e7' => 'large-orange-square',
  '1f7e8' => 'large-yellow-square',
  '1f7e9' => 'large-green-square',
  '1f7ea' => 'large-purple-square',
  '1f7eb' => 'large-brown-square',

  # White shapes
  '25ab' => 'white-small-square',
  '25fb' => 'white-medium-square',
  '25fd' => 'white-medium-small-square',
  '2b1c' => 'white-large-square',

  # Face emojis
  '1f635' => 'dizzy-face',

  # Person emojis
  '1f6cc' => 'person-in-bed',
  '1f6cc-1f3fb' => 'person-in-bed_1f6cc-1f3fb',
  '1f6cc-1f3fc' => 'person-in-bed_1f6cc-1f3fc',
  '1f6cc-1f3fd' => 'person-in-bed_1f6cc-1f3fd',
  '1f6cc-1f3fe' => 'person-in-bed_1f6cc-1f3fe',
  '1f6cc-1f3ff' => 'person-in-bed_1f6cc-1f3ff',

  # Headscarf (uses "person-" not "woman-")
  '1f9d5' => 'person-with-headscarf',
  '1f9d5-1f3fb' => 'person-with-headscarf_1f9d5-1f3fb',
  '1f9d5-1f3fc' => 'person-with-headscarf_1f9d5-1f3fc',
  '1f9d5-1f3fd' => 'person-with-headscarf_1f9d5-1f3fd',
  '1f9d5-1f3fe' => 'person-with-headscarf_1f9d5-1f3fe',
  '1f9d5-1f3ff' => 'person-with-headscarf_1f9d5-1f3ff',

  # Two o'clock (special case)
  '1f551' => 'two-oclock',

  # Symbols
  '2753' => 'question-mark',
  '2757' => 'exclamation-mark',
  '2796' => 'heavy-minus-sign',
  '2640' => 'female-sign',
  '2642' => 'male-sign',
  '2695' => 'medical-symbol',

  # Miscellaneous
  '1f6f3' => 'passenger-ship',
  '1f7f0' => 'khanda',
  '1f1f9-1f1f7' => 'flag-turkey',

  # Person levitating (uses "person-in-suit-levitating")
  '1f574-200d-2640' => 'woman-in-suit-levitating',
  '1f574-200d-2642' => 'man-in-suit-levitating',
  '1f574-1f3fb-200d-2640' => 'woman-in-suit-levitating_1f574-1f3fb-200d-2640-fe0f',
  '1f574-1f3fb-200d-2642' => 'man-in-suit-levitating_1f574-1f3fb-200d-2642-fe0f',
  '1f574-1f3fc-200d-2640' => 'woman-in-suit-levitating_1f574-1f3fc-200d-2640-fe0f',
  '1f574-1f3fc-200d-2642' => 'man-in-suit-levitating_1f574-1f3fc-200d-2642-fe0f',
  '1f574-1f3fd-200d-2640' => 'woman-in-suit-levitating_1f574-1f3fd-200d-2640-fe0f',
  '1f574-1f3fd-200d-2642' => 'man-in-suit-levitating_1f574-1f3fd-200d-2642-fe0f',
  '1f574-1f3fe-200d-2640' => 'woman-in-suit-levitating_1f574-1f3fe-200d-2640-fe0f',
  '1f574-1f3fe-200d-2642' => 'man-in-suit-levitating_1f574-1f3fe-200d-2642-fe0f',
  '1f574-1f3ff-200d-2640' => 'woman-in-suit-levitating_1f574-1f3ff-200d-2640-fe0f',
  '1f574-1f3ff-200d-2642' => 'man-in-suit-levitating_1f574-1f3ff-200d-2642-fe0f',

  # Mx Claus (person + christmas tree) - This is Emoji 14.0
  '1f468-200d-1f384' => 'mx-claus',
  '1f469-200d-1f384' => 'mx-claus',  # Both man and woman use same image as gender-neutral
  '1f468-1f3fb-200d-1f384' => 'mx-claus_1f9d1-1f3fb-200d-1f384',
  '1f468-1f3fc-200d-1f384' => 'mx-claus_1f9d1-1f3fc-200d-1f384',
  '1f468-1f3fd-200d-1f384' => 'mx-claus_1f9d1-1f3fd-200d-1f384',
  '1f468-1f3fe-200d-1f384' => 'mx-claus_1f9d1-1f3fe-200d-1f384',
  '1f468-1f3ff-200d-1f384' => 'mx-claus_1f9d1-1f3ff-200d-1f384',
  '1f469-1f3fb-200d-1f384' => 'mx-claus_1f9d1-1f3fb-200d-1f384',
  '1f469-1f3fc-200d-1f384' => 'mx-claus_1f9d1-1f3fc-200d-1f384',
  '1f469-1f3fd-200d-1f384' => 'mx-claus_1f9d1-1f3fd-200d-1f384',
  '1f469-1f3fe-200d-1f384' => 'mx-claus_1f9d1-1f3fe-200d-1f384',
  '1f469-1f3ff-200d-1f384' => 'mx-claus_1f9d1-1f3ff-200d-1f384',
}

def download(codepoint, slug)
  # Try different URL patterns
  urls = []

  if slug.include?('_')
    # Already has codepoint in slug
    urls << "#{CDN_BASE}/#{slug}.png"
  else
    urls << "#{CDN_BASE}/#{slug}_#{codepoint}.png"
    urls << "#{CDN_BASE}/#{slug}_#{codepoint}-fe0f.png"
  end

  urls.each do |url|
    uri = URI(url)
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15
      response = http.get(uri.path)

      if response.code == '200' && response.body.size > 1000
        output_path = File.join(EMOJI_DIR, "#{codepoint}.png")
        File.binwrite(output_path, response.body)
        return response.body.size
      end
    rescue => e
      # Continue
    end
  end
  nil
end

def main
  puts "=" * 60
  puts "Downloading remaining emojis with corrected slugs"
  puts "=" * 60

  success = 0
  failed = []

  SLUG_MAP.each do |codepoint, slug|
    # Check if we already have a good image
    path = File.join(EMOJI_DIR, "#{codepoint}.png")
    if File.exist?(path) && File.size(path) > 1000
      puts "  #{codepoint}: already have (#{File.size(path)} bytes)"
      next
    end

    print "  #{codepoint} (#{slug})... "
    size = download(codepoint, slug)
    if size
      puts "✓ #{size} bytes"
      success += 1
    else
      puts "✗"
      failed << codepoint
    end
  end

  puts
  puts "=" * 60
  puts "Results: #{success} downloaded, #{failed.size} failed"

  if failed.any?
    puts "\nFailed:"
    failed.each { |cp| puts "  #{cp}" }
  end
end

main
