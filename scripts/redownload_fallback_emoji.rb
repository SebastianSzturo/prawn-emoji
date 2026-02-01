#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-download emoji images that are too small (likely Twemoji fallbacks)
# These need to be replaced with Apple emoji images

require 'net/http'
require 'uri'
require 'yaml'
require 'fileutils'
require 'json'
require 'open-uri'

$stdout.sync = true

APPLE_VERSION = 419
CDN_BASE = "https://em-content.zobj.net/source/apple/#{APPLE_VERSION}"
EMOJI_DIR = File.expand_path('../emoji/images', __dir__)
INDEX_FILE = File.expand_path('../emoji/index.yml', __dir__)
EMOJI_TEST_CACHE = File.expand_path('../.context/emoji-test.txt', __dir__)
EMOJI_TEST_URL = "https://unicode.org/Public/emoji/16.0/emoji-test.txt"

THREAD_COUNT = 10
MIN_SIZE = 1000  # Images smaller than this are considered fallbacks

# Slug overrides for emojis with non-standard URL slugs
SLUG_OVERRIDES = {
  '2640' => 'female-sign',
  '2642' => 'male-sign',
  '2695' => 'medical-symbol',
  '2753' => 'red-question-mark',
  '2757' => 'red-exclamation-mark',
  '2796' => 'minus',
  '1f621' => 'pouting-face',
  '1f635' => 'face-with-crossed-out-eyes',
  '1f6b9' => 'mens-room',
  '1f6ba' => 'womens-room',
  '1f6f3' => 'passenger-ship',
  '1f7f0' => 'khanda',
  '1f534' => 'red-circle',
  '1f535' => 'blue-circle',
  '25ab' => 'white-small-square',
  '25fb' => 'white-medium-square',
  '25fd' => 'white-medium-small-square',
  '2b1c' => 'white-large-square',
  '1f1f9-1f1f7' => 'flag-turkiye',
  '1f452' => 'womans-hat',
  '1f45a' => 'womans-clothes',
  '1f45e' => 'mans-shoe',
  '1f461' => 'womans-sandal',
  '1f462' => 'womans-boot',
  # Clock faces
  '1f550' => 'one-oclock',
  '1f551' => 'two-oclock',
  '1f552' => 'three-oclock',
  '1f553' => 'four-oclock',
  '1f554' => 'five-oclock',
  '1f555' => 'six-oclock',
  '1f556' => 'seven-oclock',
  '1f557' => 'eight-oclock',
  '1f558' => 'nine-oclock',
  '1f559' => 'ten-oclock',
  '1f55a' => 'eleven-oclock',
  '1f55b' => 'twelve-oclock',
  # Colored shapes
  '1f7e0' => 'orange-circle',
  '1f7e1' => 'yellow-circle',
  '1f7e2' => 'green-circle',
  '1f7e3' => 'purple-circle',
  '1f7e4' => 'brown-circle',
  '1f7e5' => 'red-square',
  '1f7e6' => 'blue-square',
  '1f7e7' => 'orange-square',
  '1f7e8' => 'yellow-square',
  '1f7e9' => 'green-square',
  '1f7ea' => 'purple-square',
  '1f7eb' => 'brown-square',
  # Person in bed
  '1f6cc' => 'person-in-bed',
  '1f6cc-1f3fb' => 'person-in-bed-light-skin-tone',
  '1f6cc-1f3fc' => 'person-in-bed-medium-light-skin-tone',
  '1f6cc-1f3fd' => 'person-in-bed-medium-skin-tone',
  '1f6cc-1f3fe' => 'person-in-bed-medium-dark-skin-tone',
  '1f6cc-1f3ff' => 'person-in-bed-dark-skin-tone',
  # Woman with headscarf
  '1f9d5' => 'woman-with-headscarf',
  '1f9d5-1f3fb' => 'woman-with-headscarf-light-skin-tone',
  '1f9d5-1f3fc' => 'woman-with-headscarf-medium-light-skin-tone',
  '1f9d5-1f3fd' => 'woman-with-headscarf-medium-skin-tone',
  '1f9d5-1f3fe' => 'woman-with-headscarf-medium-dark-skin-tone',
  '1f9d5-1f3ff' => 'woman-with-headscarf-dark-skin-tone',
}

# These codepoints don't have standalone Apple images (components only)
SKIP_CODEPOINTS = %w[
  1f1e6 1f1e7 1f1e8 1f1e9 1f1ea 1f1eb 1f1ec 1f1ed 1f1ee 1f1ef
  1f1f0 1f1f1 1f1f2 1f1f3 1f1f4 1f1f5 1f1f6 1f1f7 1f1f8 1f1f9
  1f1fa 1f1fb 1f1fc 1f1fd 1f1fe 1f1ff
]

def download_emoji_test
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
      codepoints = codepoints_raw.downcase.split(/\s+/).reject { |c| c == 'fe0f' }.join('-')
      slug = name.downcase.gsub(/[''`´]/, '').gsub(/[:\s]+/, '-').gsub(/[^a-z0-9\-]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
      if status == 'fully-qualified' || !mapping[codepoints]
        mapping[codepoints] = slug
      end
    end
  end
  mapping
end

def try_download(codepoint, slug)
  # Try multiple URL patterns
  urls = [
    "#{CDN_BASE}/#{slug}_#{codepoint}.png",
    "#{CDN_BASE}/#{slug}_#{codepoint.gsub('-', '-')}.png",
  ]

  urls.each do |url|
    uri = URI(url)
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15
      response = http.get(uri.path)
      if response.code == '200' && response.body.size > MIN_SIZE
        return response.body
      end
    rescue => e
      # Continue to next URL
    end
  end
  nil
end

def find_small_images
  small = []
  Dir.glob(File.join(EMOJI_DIR, '*.png')).each do |path|
    if File.size(path) < MIN_SIZE
      cp = File.basename(path, '.png')
      small << cp
    end
  end
  small
end

def main
  puts "=" * 60
  puts "Apple Emoji Fallback Re-downloader"
  puts "=" * 60

  # Find small images
  small_images = find_small_images
  puts "Found #{small_images.size} small/fallback images (<#{MIN_SIZE} bytes)"

  # Filter out skip codepoints
  to_download = small_images.reject { |cp| SKIP_CODEPOINTS.include?(cp) }
  puts "After filtering components: #{to_download.size} to download"

  # Load emoji name mapping
  emoji_test = download_emoji_test
  name_mapping = parse_emoji_test(emoji_test)
  puts "Loaded #{name_mapping.size} emoji name mappings"

  # Download
  success = 0
  failed = []

  to_download.each_with_index do |cp, idx|
    slug = SLUG_OVERRIDES[cp] || name_mapping[cp]

    unless slug
      puts "  [#{idx+1}/#{to_download.size}] #{cp}: No slug found, skipping"
      failed << { cp: cp, reason: 'no_slug' }
      next
    end

    print "  [#{idx+1}/#{to_download.size}] #{cp} (#{slug})... "

    data = try_download(cp, slug)
    if data
      output_path = File.join(EMOJI_DIR, "#{cp}.png")
      File.binwrite(output_path, data)
      puts "✓ #{data.size} bytes"
      success += 1
    else
      puts "✗ failed"
      failed << { cp: cp, slug: slug, reason: 'download_failed' }
    end
  end

  puts
  puts "=" * 60
  puts "Results:"
  puts "  Success: #{success}"
  puts "  Failed: #{failed.size}"
  puts "  Skipped (components): #{small_images.size - to_download.size}"

  if failed.any?
    puts
    puts "Failed downloads:"
    failed.each do |f|
      puts "  #{f[:cp]}: #{f[:reason]} #{f[:slug] ? "(#{f[:slug]})" : ''}"
    end
  end
end

main
