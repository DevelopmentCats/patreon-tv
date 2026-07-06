// auth-server.js
//
// A minimal one-shot OAuth authorization-code server. Boots on
// localhost:8721, prints an authorize URL, waits for the redirect,
// exchanges the code for tokens, saves them to ./tokens/<mode>.json,
// then exits.
//
// Usage:
//   node auth-server.js fan       # requests FAN_SCOPES
//   node auth-server.js creator   # requests CREATOR_SCOPES
//
// Uses only Node stdlib + dotenv so it runs anywhere with `node >=20`.

import http from 'node:http';
import { URL } from 'node:url';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import 'dotenv/config';

const mode = process.argv[2] === 'creator' ? 'creator' : 'fan';

const {
  PATREON_CLIENT_ID,
  PATREON_CLIENT_SECRET,
  PATREON_REDIRECT_URI = 'http://localhost:8721/callback',
  FAN_SCOPES,
  CREATOR_SCOPES,
  USER_AGENT = 'PatreonTVResearch/0.1',
} = process.env;

if (!PATREON_CLIENT_ID || !PATREON_CLIENT_SECRET) {
  console.error('ERROR: set PATREON_CLIENT_ID and PATREON_CLIENT_SECRET in .env');
  process.exit(1);
}

const scopes = mode === 'creator' ? CREATOR_SCOPES : FAN_SCOPES;
if (!scopes) {
  console.error(`ERROR: no scopes set for mode=${mode}`);
  process.exit(1);
}

const state = Math.random().toString(36).slice(2);
const authorizeUrl = new URL('https://www.patreon.com/oauth2/authorize');
authorizeUrl.searchParams.set('response_type', 'code');
authorizeUrl.searchParams.set('client_id', PATREON_CLIENT_ID);
authorizeUrl.searchParams.set('redirect_uri', PATREON_REDIRECT_URI);
authorizeUrl.searchParams.set('scope', scopes);
authorizeUrl.searchParams.set('state', state);

console.log('\n=== Patreon OAuth harness ===');
console.log(`Mode: ${mode}`);
console.log(`Scopes: ${scopes}`);
console.log('\nOpen this URL in your browser and sign in with the Patreon account you want to test as:\n');
console.log(authorizeUrl.toString());
console.log('\nWaiting for redirect on', PATREON_REDIRECT_URI, '...\n');

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:8721`);
  if (url.pathname !== '/callback') {
    res.writeHead(404); res.end('not found'); return;
  }

  const code = url.searchParams.get('code');
  const returnedState = url.searchParams.get('state');
  const error = url.searchParams.get('error');

  if (error) {
    res.writeHead(400, { 'content-type': 'text/plain' });
    res.end(`OAuth error: ${error}\n${url.searchParams.get('error_description') || ''}`);
    console.error('OAuth error:', error, url.searchParams.get('error_description'));
    server.close();
    process.exit(1);
  }
  if (!code) {
    res.writeHead(400); res.end('no code'); return;
  }
  if (returnedState !== state) {
    res.writeHead(400); res.end('state mismatch');
    console.error('state mismatch — CSRF check failed');
    server.close();
    process.exit(1);
  }

  console.log('Received code:', code.slice(0, 8) + '...');
  console.log('Exchanging for tokens...');

  const body = new URLSearchParams({
    code,
    grant_type: 'authorization_code',
    client_id: PATREON_CLIENT_ID,
    client_secret: PATREON_CLIENT_SECRET,
    redirect_uri: PATREON_REDIRECT_URI,
  });

  const tokenResp = await fetch('https://www.patreon.com/api/oauth2/token', {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': USER_AGENT,
    },
    body,
  });
  const text = await tokenResp.text();
  if (!tokenResp.ok) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end(`Token exchange failed: ${tokenResp.status}\n${text}`);
    console.error('Token exchange failed:', tokenResp.status, text);
    server.close();
    process.exit(1);
  }

  const tokens = JSON.parse(text);
  tokens._obtained_at = new Date().toISOString();
  tokens._scopes_requested = scopes;
  tokens._mode = mode;

  await mkdir('./tokens', { recursive: true });
  const path = `./tokens/${mode}.json`;
  await writeFile(path, JSON.stringify(tokens, null, 2));

  console.log(`Saved tokens to ${path}`);
  console.log('Scopes granted:', tokens.scope);
  console.log('Expires in:', tokens.expires_in, 'seconds');

  res.writeHead(200, { 'content-type': 'text/html' });
  res.end(`<!doctype html><meta charset="utf-8"><title>Done</title>
    <body style="font: 15px/1.5 -apple-system, system-ui, sans-serif; max-width:640px; margin:60px auto; padding:0 20px;">
      <h1>Auth successful</h1>
      <p>Tokens saved to <code>tokens/${mode}.json</code>.</p>
      <p>Scopes granted: <code>${tokens.scope}</code></p>
      <p>You can close this tab and return to the terminal.</p>
    </body>`);

  setTimeout(() => { server.close(); process.exit(0); }, 500);
});

server.listen(8721);
