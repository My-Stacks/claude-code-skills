#!/usr/bin/env node
// run-seo.mjs — extract and validate SEO/OG/Twitter/JSON-LD/headings/alt.

import { chromium } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const URL = process.env.DESIGN_QA_URL;
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL || !REPORT_DIR) {
  console.error('DESIGN_QA_URL and DESIGN_QA_REPORT_DIR are required');
  process.exit(1);
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  extraHTTPHeaders: BYPASS ? {
    'x-vercel-protection-bypass': BYPASS,
    'x-vercel-set-bypass-cookie': 'true'
  } : {}
});
const page = await context.newPage();

console.log(`[seo] fetching ${URL}...`);
await page.goto(URL, { waitUntil: 'networkidle', timeout: 30000 });

const data = await page.evaluate(() => {
  const meta = (selector) => document.querySelector(selector)?.getAttribute('content') ?? null;
  const attr = (selector, attribute) => document.querySelector(selector)?.getAttribute(attribute) ?? null;

  const ogTags = {};
  document.querySelectorAll('meta[property^="og:"]').forEach(el => {
    ogTags[el.getAttribute('property')] = el.getAttribute('content');
  });

  const twTags = {};
  document.querySelectorAll('meta[name^="twitter:"]').forEach(el => {
    twTags[el.getAttribute('name')] = el.getAttribute('content');
  });

  const jsonLd = [];
  document.querySelectorAll('script[type="application/ld+json"]').forEach(el => {
    try {
      jsonLd.push({ valid: true, data: JSON.parse(el.textContent) });
    } catch (e) {
      jsonLd.push({ valid: false, error: e.message, raw: el.textContent.slice(0, 200) });
    }
  });

  const headings = {
    h1: [...document.querySelectorAll('h1')].map(h => h.textContent.trim()),
    h2: [...document.querySelectorAll('h2')].map(h => h.textContent.trim()),
    h3: [...document.querySelectorAll('h3')].map(h => h.textContent.trim()),
    h4: [...document.querySelectorAll('h4')].map(h => h.textContent.trim())
  };

  const images = [...document.querySelectorAll('img')].map(img => ({
    src: img.getAttribute('src'),
    alt: img.getAttribute('alt'),
    hasAlt: img.hasAttribute('alt')
  }));

  const linksWithBlank = [...document.querySelectorAll('a[target="_blank"]')].map(a => ({
    href: a.getAttribute('href'),
    text: a.textContent.trim().slice(0, 50),
    rel: a.getAttribute('rel'),
    hasNoopener: (a.getAttribute('rel') || '').includes('noopener')
  }));

  return {
    title: document.title,
    htmlLang: document.documentElement.getAttribute('lang'),
    charset: attr('meta[charset]', 'charset'),
    viewport: meta('meta[name="viewport"]'),
    description: meta('meta[name="description"]'),
    canonical: attr('link[rel="canonical"]', 'href'),
    robots: meta('meta[name="robots"]'),
    og: ogTags,
    twitter: twTags,
    jsonLd,
    headings,
    images,
    linksWithBlank,
    favicon: attr('link[rel*="icon"]', 'href')
  };
});

await context.close();
await browser.close();

// Validate og:image dimensions if present
if (data.og['og:image']) {
  try {
    const imgRes = await fetch(data.og['og:image']);
    const buf = Buffer.from(await imgRes.arrayBuffer());
    data.og.imageActual = {
      mime: imgRes.headers.get('content-type'),
      size: buf.length,
      reachable: imgRes.ok
    };
  } catch (e) {
    data.og.imageActual = { reachable: false, error: e.message };
  }
}

// Build findings
const findings = [];
const add = (severity, category, message, detail) => findings.push({ severity, category, message, detail });

if (!data.title) add('blocker', 'seo', 'Missing <title>', null);
else if (data.title.length < 30 || data.title.length > 60) {
  add('medium', 'seo', `<title> length suboptimal (${data.title.length} chars; ideal 30–60)`, data.title);
}

if (!data.description) add('high', 'seo', 'Missing meta description', null);
else if (data.description.length < 70 || data.description.length > 160) {
  add('medium', 'seo', `Meta description length suboptimal (${data.description.length} chars; ideal 70–160)`, null);
}

if (!data.htmlLang) add('blocker', 'seo', 'Missing <html lang>', null);
if (!data.viewport) add('high', 'seo', 'Missing viewport meta', null);
else if (data.viewport.includes('user-scalable=no') || data.viewport.includes('user-scalable=0')) {
  add('high', 'a11y', 'viewport meta disables user scaling (a11y violation)', data.viewport);
}

if (!data.canonical) add('high', 'seo', 'Missing canonical URL', null);

// OG
const requiredOg = ['og:title', 'og:description', 'og:image', 'og:url', 'og:type'];
for (const tag of requiredOg) {
  if (!data.og[tag]) add(tag === 'og:image' ? 'high' : 'medium', 'og', `Missing ${tag}`, null);
}
if (data.og.imageActual && !data.og.imageActual.reachable) {
  add('high', 'og', 'og:image URL not reachable', data.og['og:image']);
}

// Twitter Card
if (!data.twitter['twitter:card']) add('medium', 'twitter', 'Missing twitter:card', null);

// JSON-LD validity
for (const ld of data.jsonLd) {
  if (!ld.valid) add('blocker', 'jsonld', 'Malformed JSON-LD block', ld.error);
}

// Headings
if (data.headings.h1.length === 0) add('high', 'headings', 'No <h1> on page', null);
else if (data.headings.h1.length > 1) add('high', 'headings', `Multiple <h1> tags (${data.headings.h1.length})`, data.headings.h1);

// Images alt
const missingAlt = data.images.filter(img => !img.hasAlt);
if (missingAlt.length > 0) {
  add('medium', 'a11y', `${missingAlt.length} <img> without alt attribute`, missingAlt.map(i => i.src).slice(0, 5));
}

// Target=_blank without noopener
const unsafeLinks = data.linksWithBlank.filter(l => !l.hasNoopener);
if (unsafeLinks.length > 0) {
  add('medium', 'security', `${unsafeLinks.length} target="_blank" links missing rel="noopener"`, unsafeLinks.slice(0, 5));
}

const report = {
  url: URL,
  scannedAt: new Date().toISOString(),
  data,
  findings,
  byCategory: {
    seo: findings.filter(f => f.category === 'seo'),
    og: findings.filter(f => f.category === 'og'),
    twitter: findings.filter(f => f.category === 'twitter'),
    jsonld: findings.filter(f => f.category === 'jsonld'),
    headings: findings.filter(f => f.category === 'headings'),
    a11y: findings.filter(f => f.category === 'a11y'),
    security: findings.filter(f => f.category === 'security')
  }
};

writeFileSync(join(REPORT_DIR, 'seo', 'report.json'), JSON.stringify(report, null, 2));

console.log(`\n[seo] ${findings.length} findings:`);
console.log(`  blockers: ${findings.filter(f => f.severity === 'blocker').length}`);
console.log(`  high: ${findings.filter(f => f.severity === 'high').length}`);
console.log(`  medium: ${findings.filter(f => f.severity === 'medium').length}`);
