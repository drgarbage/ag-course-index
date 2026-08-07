#!/usr/bin/env node
/*
 * Poll GitHub's Deployments API for the Vercel preview URL of the current
 * commit, and print it to stdout on success.
 *
 * Usage: node resolve-preview-url.js [--attempts N] [--interval-ms MS]
 *
 * Written in Node rather than a bash for-loop deliberately: the retry logic
 * (`for i in $(seq 1 N)`, `[ -n "$ID" ]`, `sleep`) only works in a POSIX
 * shell. That's true for Claude Code's own Bash tool (which requires Git
 * Bash on Windows), but this skill is meant to be portable to other agent
 * harnesses too, and a harness whose "Bash tool" maps to native cmd.exe or
 * PowerShell would silently fail on that syntax. Shelling out to `gh` for
 * each API call but keeping the loop/parsing in Node sidesteps the whole
 * shell-dialect question — this script runs the same way everywhere Node
 * and `gh` are already required to be installed.
 *
 * Exit codes: 0 with `PREVIEW_URL=<url>` printed on success; 1 if the
 * deployment never showed up within the attempt budget (prints nothing to
 * stdout in that case — the caller should fall back to `vercel list` or
 * report the timeout, per SKILL.md Section 5).
 */
'use strict';

const { execFileSync } = require('child_process');

function parseArgs(argv) {
  const args = { attempts: 12, intervalMs: 5000 };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--attempts') args.attempts = Number(argv[++i]);
    else if (argv[i] === '--interval-ms') args.intervalMs = Number(argv[++i]);
  }
  return args;
}

function gh(args) {
  try {
    const out = execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return JSON.parse(out);
  } catch {
    return null;
  }
}

function sleep(ms) {
  // A real blocking sleep with no external process — shelling out to
  // `sleep`/`timeout.exe` would work most of the time, but `timeout.exe`
  // specifically fails with "Input redirection is not supported" when it
  // isn't attached to a real console, which is exactly the case when a
  // parent process spawns it non-interactively (as here).
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function main() {
  const { attempts, intervalMs } = parseArgs(process.argv);
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();

  let deploymentId = null;
  for (let i = 0; i < attempts && !deploymentId; i++) {
    const deployments = gh(['api', `repos/{owner}/{repo}/deployments?sha=${sha}`]);
    if (Array.isArray(deployments) && deployments.length > 0) {
      deploymentId = deployments[0].id;
      break;
    }
    if (i < attempts - 1) sleep(intervalMs);
  }

  if (!deploymentId) {
    console.error('No deployment found for this commit within the attempt budget.');
    process.exit(1);
  }

  const statuses = gh(['api', `repos/{owner}/{repo}/deployments/${deploymentId}/statuses`]);
  const targetUrl = Array.isArray(statuses) && statuses.length > 0 ? statuses[0].target_url : null;
  if (!targetUrl) {
    console.error('Deployment found but it has no status/target_url yet.');
    process.exit(1);
  }

  console.log(`PREVIEW_URL=${targetUrl}`);
}

main();
