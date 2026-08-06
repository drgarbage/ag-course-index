#!/usr/bin/env node
/*
 * Local, single-use credential collection form.
 *
 * Usage: node credential-form.js <fields.json> [--out .env.local]
 *
 * fields.json: [
 *   { "name": "FIREBASE_SERVICE_ACCOUNT", "label": "Firebase 服務帳戶金鑰 (JSON)",
 *     "help": "Firebase Console → 專案設定 → 服務帳戶 → 產生新的私密金鑰",
 *     "link": "https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk",
 *     "secret": true, "multiline": true },
 *   ...
 * ]
 *
 * Serves a 127.0.0.1-only HTML form for the given fields, tries to open it
 * in the user's default browser, writes submitted values straight into the
 * target .env file (never to stdout/stderr), and exits once the form has
 * been submitted successfully. Nothing entered by the user is printed.
 *
 * This process is meant to be launched in the background by the calling
 * agent and waited on — it exits on its own after a successful submit,
 * or after a 15-minute idle timeout if nobody fills the form in.
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const IDLE_TIMEOUT_MS = 15 * 60 * 1000;

function parseArgs(argv) {
  const args = { fieldsPath: null, out: '.env.local' };
  const rest = argv.slice(2);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--out') {
      args.out = rest[++i];
    } else if (!args.fieldsPath) {
      args.fieldsPath = rest[i];
    }
  }
  return args;
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function renderForm(fields) {
  const rows = fields.map((f, i) => {
    const inputId = `field_${i}`;
    const inputEl = f.multiline
      ? `<textarea id="${inputId}" name="${escapeHtml(f.name)}" rows="4" required></textarea>`
      : `<input id="${inputId}" name="${escapeHtml(f.name)}" type="${f.secret ? 'password' : 'text'}" autocomplete="off" required />`;
    const link = f.link
      ? `<a href="${escapeHtml(f.link)}" target="_blank" rel="noopener">前往取得 →</a>`
      : '';
    return `
      <div class="field">
        <label for="${inputId}">${escapeHtml(f.label || f.name)}</label>
        ${f.help ? `<p class="help">${escapeHtml(f.help)} ${link}</p>` : ''}
        ${inputEl}
      </div>`;
  }).join('\n');

  return `<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>設定金鑰</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 560px; margin: 40px auto; padding: 0 20px; color: #1a1a1a; background: #fafafa; }
  h1 { font-size: 1.3rem; }
  p.intro { color: #555; line-height: 1.6; }
  .field { margin-bottom: 22px; }
  label { display: block; font-weight: 600; margin-bottom: 4px; }
  .help { font-size: 0.85rem; color: #666; margin: 0 0 6px; }
  .help a { color: #2563eb; text-decoration: none; }
  input, textarea { width: 100%; box-sizing: border-box; padding: 10px; border: 1px solid #ccc; border-radius: 6px; font-size: 1rem; font-family: inherit; }
  button { background: #2563eb; color: white; border: none; padding: 12px 24px; border-radius: 6px; font-size: 1rem; cursor: pointer; }
  button:hover { background: #1d4ed8; }
  #status { margin-top: 16px; font-weight: 600; }
</style>
</head>
<body>
  <h1>🔑 請填寫以下設定值</h1>
  <p class="intro">這些內容只會存到你自己電腦上的設定檔，不會被上傳、不會出現在對話紀錄裡。填完送出後，這個視窗就可以關閉了。</p>
  <form id="f">
    ${rows}
    <button type="submit">送出並繼續</button>
  </form>
  <div id="status"></div>
  <script>
    document.getElementById('f').addEventListener('submit', async (e) => {
      e.preventDefault();
      const status = document.getElementById('status');
      const data = Object.fromEntries(new FormData(e.target).entries());
      status.textContent = '送出中…';
      try {
        const res = await fetch('/submit', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data),
        });
        if (res.ok) {
          document.body.innerHTML = '<h1>✅ 已完成</h1><p>設定值已儲存，這個視窗可以關閉了，請回到對話視窗繼續。</p>';
          setTimeout(() => window.close(), 1500);
        } else {
          status.textContent = '送出失敗，請重試一次。';
        }
      } catch (err) {
        status.textContent = '送出失敗，請確認網路連線後重試。';
      }
    });
  </script>
</body>
</html>`;
}

function openInBrowser(url) {
  const cmd = process.platform === 'darwin' ? 'open'
    : process.platform === 'win32' ? 'start'
    : 'xdg-open';
  try {
    execFile(cmd, process.platform === 'win32' ? ['', url] : [url], { shell: process.platform === 'win32' }, () => {});
  } catch {
    // Best-effort only — the URL printed to stdout is the real fallback.
  }
}

function appendToEnvFile(outPath, values) {
  // Every value is stored as a JSON string literal (not bash-quoted). This
  // file is never `source`d by a shell — see resources/read-env-value.js —
  // so JSON.stringify's escaping (quotes, backslashes, real newlines) is
  // both sufficient and lossless, with no risk of $(...) / `...` shell
  // command substitution triggering on secrets that happen to contain them.
  const absPath = path.resolve(outPath);
  let existingLines = [];
  try {
    existingLines = fs.readFileSync(absPath, 'utf8').split('\n');
  } catch {
    existingLines = [];
  }

  const newEntries = new Map(Object.entries(values));
  const updatedLines = existingLines.map((line) => {
    const m = line.match(/^([A-Z0-9_]+)=/);
    if (m && newEntries.has(m[1])) {
      const key = m[1];
      const rendered = `${key}=${JSON.stringify(newEntries.get(key))}`;
      newEntries.delete(key); // consumed — an in-place update, not an append
      return rendered;
    }
    return line;
  });

  const appendedLines = Array.from(newEntries.entries())
    .map(([k, v]) => `${k}=${JSON.stringify(v)}`);

  let finalContent = updatedLines.join('\n');
  if (appendedLines.length) {
    const header = finalContent.trim().length
      ? '\n\n# --- added by credential-form.js ---\n'
      : '# --- added by credential-form.js ---\n';
    finalContent = finalContent.trimEnd() + (finalContent.trim().length ? '\n' : '') + header + appendedLines.join('\n') + '\n';
  } else if (!finalContent.endsWith('\n')) {
    finalContent += '\n';
  }

  fs.writeFileSync(absPath, finalContent);
  return Object.keys(values);
}

function main() {
  const { fieldsPath, out } = parseArgs(process.argv);
  if (!fieldsPath) {
    console.error('Usage: node credential-form.js <fields.json> [--out .env.local]');
    process.exit(1);
  }
  const fields = JSON.parse(fs.readFileSync(fieldsPath, 'utf8'));
  if (!Array.isArray(fields) || fields.length === 0) {
    console.error('fields.json must be a non-empty array of field definitions.');
    process.exit(1);
  }

  const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(renderForm(fields));
      return;
    }
    if (req.method === 'POST' && req.url === '/submit') {
      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => {
        try {
          const values = JSON.parse(body);
          const savedKeys = appendToEnvFile(out, values);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
          // Print only key names, never values, so the caller can confirm
          // success without the secret ever touching stdout.
          console.log(`SAVED_KEYS=${savedKeys.join(',')}`);
          clearTimeout(idleTimer);
          setTimeout(() => { server.close(); process.exit(0); }, 300);
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false }));
        }
      });
      return;
    }
    res.writeHead(404);
    res.end();
  });

  // 127.0.0.1 only — never bind 0.0.0.0, this form must not be reachable
  // from other machines on the network.
  server.listen(0, '127.0.0.1', () => {
    const { port } = server.address();
    const url = `http://127.0.0.1:${port}/`;
    console.log(`FORM_URL=${url}`);
    openInBrowser(url);
  });

  const idleTimer = setTimeout(() => {
    console.error('Timed out waiting for form submission (15 min).');
    server.close();
    process.exit(1);
  }, IDLE_TIMEOUT_MS);
}

main();
