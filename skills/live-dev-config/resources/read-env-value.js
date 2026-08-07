#!/usr/bin/env node
/*
 * Print one value from a .env file to stdout, with no trailing newline.
 *
 * Usage: node read-env-value.js <env-file> <KEY>
 *
 * Deliberately does NOT go through a shell (no `source`, no `<<<`, no
 * command substitution) — values are secrets and may legitimately contain
 * `$(...)`, backticks, or other shell metacharacters that a shell would
 * otherwise try to execute. This script only ever reads and JSON-decodes
 * the file directly, so nothing in the value is ever interpreted.
 *
 * Understands two shapes for a value, since this file may have been
 * written either by credential-form.js (always a single-line JSON string
 * literal) or hand-edited by a user who pasted a raw multi-line secret
 * (e.g. a Firebase service-account JSON block spanning several lines,
 * pasted exactly as copied):
 *   KEY="escaped single-line JSON string"      <- credential-form.js's format
 *   KEY={                                       <- a raw, unquoted multi-line
 *     "type": "service_account", ...               value pasted by a human
 *   }
 * A continuation block is read until the next `KEY=` line, a comment line,
 * or a blank line.
 *
 * Intended use: pipe straight into a CLI that reads its input from stdin,
 * e.g.:
 *   node read-env-value.js .env.local FIREBASE_SERVICE_ACCOUNT | vercel env add FIREBASE_SERVICE_ACCOUNT production
 *   node read-env-value.js .env.local FIREBASE_SERVICE_ACCOUNT | gh secret set FIREBASE_SERVICE_ACCOUNT
 */
'use strict';

const fs = require('fs');

const [, , envFile, key] = process.argv;
if (!envFile || !key) {
  console.error('Usage: node read-env-value.js <env-file> <KEY>');
  process.exit(1);
}

// Strip a trailing \r right at the split, not just at the edges of the
// extracted value — a Windows-edited file (CRLF) would otherwise leave a
// literal \r baked into the middle of a multi-line reconstructed value.
const lines = fs.readFileSync(envFile, 'utf8').split('\n').map((l) => l.replace(/\r$/, ''));
const prefix = `${key}=`;
const startIndex = lines.findIndex((l) => l.startsWith(prefix));
if (startIndex === -1) {
  console.error(`Key not found: ${key}`);
  process.exit(1);
}

const isBoundary = (l) => l.trim() === '' || /^\s*#/.test(l) || /^[A-Z0-9_]+=/.test(l);

const valueLines = [lines[startIndex].slice(prefix.length)];
for (let i = startIndex + 1; i < lines.length && !isBoundary(lines[i]); i++) {
  valueLines.push(lines[i]);
}
const raw = valueLines.join('\n');

let value;
try {
  const parsed = JSON.parse(raw);
  // credential-form.js always writes a JSON *string* on one line — if we
  // got a string back, that's the real value. If we got an object/array,
  // the user pasted raw unquoted JSON directly, so re-serialize it back
  // into the JSON text the downstream CLI (Vercel/GitHub) expects.
  value = typeof parsed === 'string' ? parsed : JSON.stringify(parsed);
} catch {
  // Not valid JSON at all (e.g. a plain token, or a PEM block) — take the
  // raw, trimmed text as-is.
  value = raw.trim();
}

process.stdout.write(value);
