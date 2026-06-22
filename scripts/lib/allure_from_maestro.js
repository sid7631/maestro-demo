#!/usr/bin/env node
/*
 * Convert a Maestro JUnit result + the run's screenshots into Allure's native
 * result format, so screenshots render inline in the Allure report.
 *
 * Allure's JUnit-XML reader cannot attach arbitrary files; its native
 * `*-result.json` format can. So we emit one result JSON per test case and copy
 * each screenshot in as a `*-attachment.png` referenced by that result.
 *
 * Usage:
 *   node allure_from_maestro.js --junit <file> --screenshots <dir> \
 *        --results <allure-results-dir> --app <name> --flow <path>
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

const junitPath = arg('junit');
const screensDir = arg('screenshots');
const resultsDir = arg('results');
const app = arg('app', 'app');
const flow = arg('flow', '');

if (!junitPath || !resultsDir) {
  console.error('[allure] missing --junit or --results');
  process.exit(0); // non-fatal: don't break the run
}
if (!fs.existsSync(junitPath)) {
  console.error(`[allure] no JUnit file at ${junitPath}, skipping conversion`);
  process.exit(0);
}
fs.mkdirSync(resultsDir, { recursive: true });

const sanitize = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');

// --- parse JUnit XML (simple, machine-generated structure) ------------------
const xml = fs.readFileSync(junitPath, 'utf8');
const cases = [];
const caseRe = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
const attrRe = /(\w+)="([^"]*)"/g;
let m;
while ((m = caseRe.exec(xml)) !== null) {
  const attrs = {};
  let a;
  while ((a = attrRe.exec(m[1])) !== null) attrs[a[1]] = a[2];
  const inner = m[3] || '';
  let status = 'passed';
  let message = '';
  if (/<failure\b/.test(inner)) {
    status = 'failed';
    message = (inner.match(/<failure\b[^>]*message="([^"]*)"/) || [])[1] || 'failed';
  } else if (/<error\b/.test(inner)) {
    status = 'broken';
    message = (inner.match(/<error\b[^>]*message="([^"]*)"/) || [])[1] || 'error';
  } else if (/<skipped\b/.test(inner)) {
    status = 'skipped';
  }
  cases.push({
    name: attrs.name || attrs.classname || path.basename(flow || 'flow'),
    time: parseFloat(attrs.time || '0') || 0,
    status,
    message: message.replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>'),
  });
}
if (cases.length === 0) {
  console.error('[allure] no <testcase> found in JUnit, skipping');
  process.exit(0);
}

// --- gather screenshots from this run --------------------------------------
let shots = [];
if (screensDir && fs.existsSync(screensDir)) {
  shots = fs.readdirSync(screensDir)
    .filter((f) => /\.(png|jpe?g)$/i.test(f))
    .map((f) => path.join(screensDir, f));
}

// Associate screenshots with a test case. With a single test (the common
// smoke case) attach them all; otherwise match by name, attaching a shot to a
// case when the case name appears in the screenshot filename (or vice versa).
function shotsForCase(c, idx) {
  if (cases.length === 1) return shots;
  const cn = sanitize(c.name);
  return shots.filter((s) => {
    const sn = sanitize(path.basename(s));
    return cn && (sn.includes(cn) || cn.includes(sn));
  });
}

const now = Date.now();
const feature = flow ? path.basename(path.dirname(flow)) : 'suite';

cases.forEach((c, idx) => {
  const attachments = [];
  for (const shot of shotsForCase(c, idx)) {
    const dst = `${crypto.randomUUID()}-attachment.png`;
    fs.copyFileSync(shot, path.join(resultsDir, dst));
    attachments.push({ name: path.basename(shot), source: dst, type: 'image/png' });
  }
  const uuid = crypto.randomUUID();
  const fullName = `${app} > ${c.name}`;
  const result = {
    uuid,
    historyId: crypto.createHash('md5').update(fullName).digest('hex'),
    name: c.name,
    fullName,
    status: c.status,
    statusDetails: c.message ? { message: c.message } : {},
    stage: 'finished',
    start: now - Math.round(c.time * 1000),
    stop: now,
    labels: [
      { name: 'suite', value: app },
      { name: 'feature', value: feature },
      { name: 'framework', value: 'maestro' },
    ],
    attachments,
    steps: [],
  };
  fs.writeFileSync(path.join(resultsDir, `${uuid}-result.json`), JSON.stringify(result, null, 2));
});

console.error(`[allure] wrote ${cases.length} result(s) with ${shots.length} screenshot(s) to ${resultsDir}`);
