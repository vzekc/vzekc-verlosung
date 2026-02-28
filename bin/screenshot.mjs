#!/usr/bin/env node
// Take a screenshot of a page on the local dev server via Chrome CDP.
// Usage: node bin/screenshot.mjs <path> [output.png] [--width=1280] [--height=800]
// Example: node bin/screenshot.mjs /verlosungen /tmp/verlosungen.png
// Requires: Chrome running with --remote-debugging-port=9222 (use bin/chrome-debug.sh)

import puppeteer from "puppeteer-core";

const args = process.argv.slice(2);
const flags = args.filter((a) => a.startsWith("--"));
const positional = args.filter((a) => !a.startsWith("--"));

const pagePath = positional[0] || "/";
const output = positional[1] || "/tmp/screenshot.png";
const width = parseInt(
  flags.find((f) => f.startsWith("--width="))?.split("=")[1] || "1280",
  10
);
const height = parseInt(
  flags.find((f) => f.startsWith("--height="))?.split("=")[1] || "800",
  10
);
const port = parseInt(
  flags.find((f) => f.startsWith("--port="))?.split("=")[1] || "9222",
  10
);

const baseUrl = `http://127.0.0.1:4200`;
const url = pagePath.startsWith("http") ? pagePath : `${baseUrl}${pagePath}`;

try {
  const browser = await puppeteer.connect({
    browserURL: `http://127.0.0.1:${port}`,
  });

  const page = await browser.newPage();
  await page.setViewport({ width, height });
  await page.goto(url, { waitUntil: "networkidle2", timeout: 15000 });
  await page.screenshot({ path: output, fullPage: false });

  console.log(output);

  await page.close();
  browser.disconnect();
} catch (err) {
  console.error(`Error: ${err.message}`);
  process.exit(1);
}
