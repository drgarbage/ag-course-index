#!/usr/bin/env node
/*
 * Print one value from a credential-form.js-written .env file to stdout,
 * with no trailing newline.
 *
 * Usage: node read-env-value.js <env-file> <KEY>
 *
 * Deliberately does NOT go through a shell (no `source`, no `<<<`, no
 * command substitution) — values are secrets and may legitimately contain
 * `$(...)`, backticks, or other shell metacharacters that a shell would
 * otherwise try to execute. This script only ever JSON.parses the exact
 * substring after `KEY=`, so nothing in the value is ever interpreted.
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

const lines = fs.readFileSync(envFile, 'utf8').split('\n');
const prefix = `${key}=`;
const line = lines.find((l) => l.startsWith(prefix));
if (!line) {
  console.error(`Key not found: ${key}`);
  process.exit(1);
}

const raw = line.slice(prefix.length);
let value;
try {
  value = JSON.parse(raw);
} catch {
  // Not JSON-quoted (e.g. a line hand-edited by the user) — take it as-is.
  value = raw;
}

process.stdout.write(String(value));
