# Seoul (prawn-emoji) Development Notes

## Apple Emoji Scraping Scripts

This gem uses Apple Color Emoji images from iOS 18.4 for PDF rendering. The emoji images are scraped from Emojipedia.

### Scripts in `/scripts`

**Primary download script:**
- `download_apple_emoji_fast.rb` - Fast parallel downloader using 20 threads. Downloads emojis directly from the Emojipedia CDN using the URL pattern: `https://em-content.zobj.net/source/apple/419/{slug}_{codepoint}.png`

**Fallback/retry scripts:**
- `scrape_failed_emoji.rb` - Retries failed downloads by scraping Emojipedia pages directly
- `scrape_emojis_playwright.js` - Playwright-based scraper for emojis that require JavaScript rendering
- `browser_scrape_emoji.rb` - Generates URL list for manual browser scraping

**Other:**
- `download_apple_emoji.rb` - Original single-threaded downloader
- `test_download.rb` - Test script for debugging downloads

### Cache Files (in `.context/`)

- `emoji-test.txt` - Unicode emoji-test.txt file for codepoint-to-name mapping
- `emoji_cache.json` - Cache of successfully downloaded emojis
- `failed_emoji.txt` - List of codepoints that failed to download
- `scraped_urls.json` - Cache of scraped CDN URLs from Playwright

### Adding New Emojis

When Unicode releases new emoji versions (e.g., Emoji 17.0), follow these steps:

1. Check https://emojipedia.org/apple for the latest iOS version with new emojis
2. Add new codepoints to `emoji/index.yml` (sorted by codepoint)
3. Download images using the CDN URL pattern:
   ```bash
   curl -sL "https://em-content.zobj.net/source/apple/419/{slug}_{codepoint}.png" \
     -o "emoji/images/{codepoint}.png"
   ```
4. For slug names, check Emojipedia or Unicode emoji-test.txt

### Current Status

- **Emoji Version:** Emoji 16.0 (as of iOS 18.4, March 2025)
- **Total Emojis:** 3,847 in index.yml
- **Apple Coverage:** ~93% (remaining are skin tone variants without Apple-specific pages)
- **Fallback:** Twemoji for unavailable variants
