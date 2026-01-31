#!/usr/bin/env node

// Playwright script to scrape Apple emoji URLs from Emojipedia
// Run with: npx playwright install chromium && node scripts/scrape_emojis_playwright.js

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const https = require('https');

const FAILED_FILE = path.join(__dirname, '../.context/failed_emoji.txt');
const URLS_FILE = path.join(__dirname, '../.context/scraped_urls.json');
const EMOJI_DIR = path.join(__dirname, '../emoji/images');
const EMOJI_TEST_CACHE = path.join(__dirname, '../.context/emoji-test.txt');

// Parse emoji-test.txt to get codepoint -> name mappings
function parseEmojiTest() {
  if (!fs.existsSync(EMOJI_TEST_CACHE)) {
    console.log('emoji-test.txt not found, run download_apple_emoji.rb first');
    return {};
  }

  const content = fs.readFileSync(EMOJI_TEST_CACHE, 'utf-8');
  const mapping = {};

  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('#') || !trimmed) continue;

    const parts = trimmed.split(';');
    if (parts.length < 2) continue;

    const codepointsRaw = parts[0].trim();
    const rest = parts[1];

    const match = rest.match(/^\s*(fully-qualified|minimally-qualified|unqualified|component)\s*#\s*.+?\s+E[\d.]+\s+(.+)$/);
    if (match) {
      const status = match[1];
      const name = match[2].trim();
      const codepoints = codepointsRaw.toLowerCase().split(/\s+/).join('-');

      // Convert name to slug
      let slug = name.toLowerCase();
      slug = slug.replace(/[''`´]/g, '');
      slug = slug.replace(/[:\s]+/g, '-');
      slug = slug.replace(/[^a-z0-9-]/g, '-');
      slug = slug.replace(/-+/g, '-');
      slug = slug.replace(/^-|-$/g, '');

      if (status === 'fully-qualified' || !mapping[codepoints]) {
        mapping[codepoints] = slug;
      }
    }
  }

  return mapping;
}

// Special slug overrides
const SLUG_OVERRIDES = {
  '0023-20e3': 'keycap-number-sign',
  '002a-20e3': 'keycap-asterisk',
  '0030-20e3': 'keycap-digit-zero',
  '0031-20e3': 'keycap-digit-one',
  '0032-20e3': 'keycap-digit-two',
  '0033-20e3': 'keycap-digit-three',
  '0034-20e3': 'keycap-digit-four',
  '0035-20e3': 'keycap-digit-five',
  '0036-20e3': 'keycap-digit-six',
  '0037-20e3': 'keycap-digit-seven',
  '0038-20e3': 'keycap-digit-eight',
  '0039-20e3': 'keycap-digit-nine',
  '00a9': 'copyright',
  '00ae': 'registered',
  '1f170': 'a-button-blood-type',
  '1f171': 'b-button-blood-type',
  '1f17e': 'o-button-blood-type',
  '1f17f': 'p-button',
};

// Load previously scraped URLs
function loadScrapedUrls() {
  try {
    if (fs.existsSync(URLS_FILE)) {
      return JSON.parse(fs.readFileSync(URLS_FILE, 'utf-8'));
    }
  } catch (e) {}
  return {};
}

// Save scraped URLs
function saveScrapedUrls(urls) {
  fs.writeFileSync(URLS_FILE, JSON.stringify(urls, null, 2));
}

// Download image from URL
function downloadImage(url, outputPath) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(outputPath);
    https.get(url, (response) => {
      if (response.statusCode !== 200) {
        reject(new Error(`HTTP ${response.statusCode}`));
        return;
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve(true);
      });
    }).on('error', (err) => {
      fs.unlink(outputPath, () => {});
      reject(err);
    });
  });
}

async function main() {
  // Read failed codepoints
  if (!fs.existsSync(FAILED_FILE)) {
    console.log('No failed emoji file found');
    return;
  }

  const failedList = fs.readFileSync(FAILED_FILE, 'utf-8')
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0);

  console.log(`Found ${failedList.length} failed emojis to scrape`);

  // Parse emoji test file for name mappings
  const nameMapping = parseEmojiTest();
  console.log(`Loaded ${Object.keys(nameMapping).length} emoji name mappings`);

  // Load previously scraped URLs
  const scrapedUrls = loadScrapedUrls();
  const toScrape = failedList.filter(cp => !scrapedUrls[cp]);

  console.log(`Already scraped: ${Object.keys(scrapedUrls).length}`);
  console.log(`Still need to scrape: ${toScrape.length}`);

  if (toScrape.length === 0) {
    console.log('All URLs already scraped, downloading images...');
  } else {
    // Launch browser
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    let scraped = 0;
    let failed = 0;
    const notFound = [];

    for (const codepoint of toScrape) {
      try {
        // Get slug from overrides or mapping
        const slug = SLUG_OVERRIDES[codepoint] || nameMapping[codepoint];

        if (!slug) {
          // Try without leading zeros
          const altCodepoint = codepoint.split('-').map(cp => cp.replace(/^0+/, '') || '0').join('-');
          const altSlug = nameMapping[altCodepoint];
          if (!altSlug) {
            notFound.push(codepoint);
            continue;
          }
        }

        const finalSlug = SLUG_OVERRIDES[codepoint] || nameMapping[codepoint] ||
          nameMapping[codepoint.split('-').map(cp => cp.replace(/^0+/, '') || '0').join('-')];

        if (!finalSlug) {
          notFound.push(codepoint);
          continue;
        }

        const url = `https://emojipedia.org/apple/ios-18.4/${finalSlug}`;

        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await page.waitForTimeout(300);

        // Extract image URL
        const imgUrl = await page.evaluate(() => {
          const img = document.querySelector('img[alt="iOS 18.4"]');
          return img ? img.src : null;
        });

        if (imgUrl && imgUrl.includes('em-content.zobj.net')) {
          scrapedUrls[codepoint] = imgUrl;
          scraped++;

          if (scraped % 20 === 0) {
            console.log(`Scraped ${scraped}/${toScrape.length}...`);
            saveScrapedUrls(scrapedUrls);
          }
        } else {
          failed++;
          if (failed <= 10) console.log(`No image found for ${codepoint} (${finalSlug})`);
        }

        // Rate limiting
        await page.waitForTimeout(150);

      } catch (err) {
        failed++;
        if (failed <= 10) console.log(`Error scraping ${codepoint}: ${err.message}`);
      }
    }

    await browser.close();
    saveScrapedUrls(scrapedUrls);

    console.log(`\nScraping complete!`);
    console.log(`Scraped: ${scraped}`);
    console.log(`Failed: ${failed}`);
    console.log(`No slug found: ${notFound.length}`);
  }

  // Download images from scraped URLs
  console.log('\nDownloading images...');

  let downloaded = 0;
  let downloadFailed = 0;
  const stillFailed = [];

  for (const [codepoint, url] of Object.entries(scrapedUrls)) {
    const outputPath = path.join(EMOJI_DIR, `${codepoint}.png`);

    // Skip if already downloaded with good size
    if (fs.existsSync(outputPath)) {
      const stats = fs.statSync(outputPath);
      if (stats.size > 5000) {
        continue;
      }
    }

    try {
      await downloadImage(url, outputPath);
      downloaded++;

      if (downloaded % 50 === 0) {
        console.log(`Downloaded ${downloaded}...`);
      }
    } catch (err) {
      downloadFailed++;
      stillFailed.push(codepoint);
    }
  }

  console.log(`\nDownload complete!`);
  console.log(`Downloaded: ${downloaded}`);
  console.log(`Failed: ${downloadFailed}`);

  // Update failed list with emojis that couldn't be scraped
  const allFailed = failedList.filter(cp => {
    const outputPath = path.join(EMOJI_DIR, `${cp}.png`);
    return !fs.existsSync(outputPath) || fs.statSync(outputPath).size < 5000;
  });

  if (allFailed.length > 0) {
    fs.writeFileSync(FAILED_FILE, allFailed.join('\n'));
    console.log(`Updated failed list with ${allFailed.length} emojis`);
  } else {
    fs.unlinkSync(FAILED_FILE);
    console.log('All emojis downloaded successfully!');
  }
}

main().catch(console.error);
