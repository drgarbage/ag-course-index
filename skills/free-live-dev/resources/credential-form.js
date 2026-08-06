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
    // `-webkit-text-security` masks a <textarea> the way type="password"
    // masks an <input> (there's no native masked textarea). It's WebKit/
    // Blink-only — Firefox will show a multiline secret in plaintext — so
    // the show/hide toggle below is the real cross-browser control; the
    // masking is a bonus for the common case, not a guarantee.
    const inputEl = f.multiline
      ? `<textarea id="${inputId}" name="${escapeHtml(f.name)}" rows="4" required${f.secret ? ' class="masked"' : ''}></textarea>`
      : `<input id="${inputId}" name="${escapeHtml(f.name)}" type="${f.secret ? 'password' : 'text'}" autocomplete="off" required />`;
    const toggleBtn = f.secret
      ? `<button type="button" class="toggle-btn" data-target="${inputId}" aria-label="顯示/隱藏">👁 顯示</button>`
      : '';
    const link = f.link
      ? `<a href="${escapeHtml(f.link)}" target="_blank" rel="noopener">前往取得 →</a>`
      : '';
    return `
      <div class="field">
        <label for="${inputId}">${escapeHtml(f.label || f.name)}</label>
        ${f.help ? `<p class="help">${escapeHtml(f.help)} ${link}</p>` : ''}
        ${inputEl}
        ${toggleBtn}
      </div>`;
  }).join('\n');

  return `<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>設定金鑰</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", sans-serif;
    max-width: 560px;
    margin: 48px auto;
    padding: 0 20px 40px;
    color: #1e2330;
    background: #f6f7fb;
    line-height: 1.5;
  }
  .card {
    background: #ffffff;
    border: 1px solid #e5e7eb;
    border-radius: 14px;
    padding: 32px;
    box-shadow: 0 1px 3px rgba(16, 24, 40, 0.06), 0 8px 24px rgba(16, 24, 40, 0.04);
  }
  h1 { font-size: 1.25rem; margin: 0 0 8px; }
  p.intro { color: #5b6272; margin: 0 0 28px; font-size: 0.92rem; }
  .field { margin-bottom: 24px; }
  .field:last-of-type { margin-bottom: 28px; }
  label { display: block; font-weight: 600; margin-bottom: 4px; font-size: 0.95rem; }
  .help { font-size: 0.82rem; color: #6b7280; margin: 0 0 8px; }
  .help a { color: #4f46e5; text-decoration: none; font-weight: 500; }
  .help a:hover { text-decoration: underline; }
  input, textarea {
    width: 100%;
    padding: 10px 12px;
    border: 1px solid #d1d5db;
    border-radius: 8px;
    font-size: 0.95rem;
    font-family: inherit;
    background: #fbfbfd;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }
  textarea.masked { -webkit-text-security: disc; }
  input:focus, textarea:focus {
    outline: none;
    border-color: #6366f1;
    box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.15);
    background: #fff;
  }
  .toggle-btn {
    background: none;
    border: none;
    color: #4f46e5;
    font-size: 0.82rem;
    cursor: pointer;
    padding: 6px 0 0;
  }
  .toggle-btn:hover { text-decoration: underline; }
  button[type="submit"] {
    width: 100%;
    background: #4f46e5;
    color: white;
    border: none;
    padding: 13px 24px;
    border-radius: 9px;
    font-size: 1rem;
    font-weight: 600;
    cursor: pointer;
  }
  button[type="submit"]:hover { background: #4338ca; }
  #status { margin-top: 14px; font-weight: 600; font-size: 0.9rem; text-align: center; }
</style>
</head>
<body>
  <div class="card">
    <h1>🔑 請填寫以下設定值</h1>
    <p class="intro">這些內容只會存到你自己電腦上的設定檔，不會被上傳、不會出現在對話紀錄裡。填完送出後，這個視窗就可以關閉了。</p>
    <form id="f">
      ${rows}
      <button type="submit">送出並繼續</button>
    </form>
    <div id="status"></div>
  </div>
  <script>
    document.querySelectorAll('.toggle-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        const el = document.getElementById(btn.dataset.target);
        const showing = btn.textContent.includes('隱藏');
        if (el.tagName === 'TEXTAREA') {
          el.classList.toggle('masked', showing);
        } else {
          el.type = showing ? 'password' : 'text';
        }
        btn.textContent = showing ? '👁 顯示' : '🙈 隱藏';
      });
    });

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
          document.querySelector('.card').innerHTML = '<h1>✅ 已完成</h1><p class="intro">設定值已儲存，這個視窗可以關閉了，請回到對話視窗繼續。</p>';
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
    // Strip a trailing \r at the split — a Windows-edited file (CRLF) would
    // otherwise leave every line, including continuation lines, one \r longer
    // than expected, which throws off boundary detection below.
    existingLines = fs.readFileSync(absPath, 'utf8').split('\n').map((l) => l.replace(/\r$/, ''));
  } catch {
    existingLines = [];
  }

  // A prior manual edit (the guided-template fallback path) may have left a
  // raw, unquoted, multi-line value in the file (e.g. a pasted service
  // account JSON block spanning several physical lines). When we overwrite
  // that key we must remove ALL of its continuation lines too — replacing
  // only the first line would leave orphaned JSON fragments behind and
  // corrupt the file. A continuation block ends at the next `KEY=` line, a
  // comment line, or a blank line.
  const isBoundary = (l) => l.trim() === '' || /^\s*#/.test(l) || /^[A-Z0-9_]+=/.test(l);

  const newEntries = new Map(Object.entries(values));
  const updatedLines = [];
  for (let i = 0; i < existingLines.length; i++) {
    const line = existingLines[i];
    const m = line.match(/^([A-Z0-9_]+)=/);
    if (m && newEntries.has(m[1])) {
      const key = m[1];
      updatedLines.push(`${key}=${JSON.stringify(newEntries.get(key))}`);
      newEntries.delete(key); // consumed — an in-place update, not an append
      while (i + 1 < existingLines.length && !isBoundary(existingLines[i + 1])) {
        i++; // skip this key's old continuation lines
      }
      continue;
    }
    updatedLines.push(line);
  }

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
