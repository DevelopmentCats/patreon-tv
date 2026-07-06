// probe.js
//
// Exercises the Patreon API using tokens obtained via auth-server.js.
// Dumps every response to ./dumps/<mode>-<endpoint>.json so we can
// inspect exactly what the API returns for a real account.
//
// Usage:
//   node probe.js fan
//   node probe.js creator
//
// Goals (in order of priority):
//   1. Confirm the fan-side identity + memberships flow works and see
//      what campaigns/tiers a real fan sees.
//   2. On the creator side, confirm we can read posts on the campaign
//      the creator owns and INSPECT WHAT VIDEO CONTENT LOOKS LIKE.
//      This is the single biggest unknown from the docs.
//   3. Exercise pagination, includes, fields, and note any surprises.

import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { URL } from 'node:url';
import 'dotenv/config';

const mode = process.argv[2] === 'creator' ? 'creator' : 'fan';
const USER_AGENT = process.env.USER_AGENT || 'PatreonTVResearch/0.1';

const tokens = JSON.parse(await readFile(`./tokens/${mode}.json`, 'utf8'));
const AT = tokens.access_token;

await mkdir(`./dumps/${mode}`, { recursive: true });

async function call(name, path, { headers = {}, method = 'GET', body } = {}) {
  const url = path.startsWith('http') ? path : `https://www.patreon.com${path}`;
  console.log(`\n→ ${method} ${url.replace('https://www.patreon.com', '')}`);
  const t0 = Date.now();
  const resp = await fetch(url, {
    method,
    headers: {
      authorization: `Bearer ${AT}`,
      'user-agent': USER_AGENT,
      accept: 'application/json',
      ...headers,
    },
    body,
  });
  const dt = Date.now() - t0;
  const text = await resp.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }

  const dump = {
    request: { url, method, headers: { authorization: 'Bearer ***', ...headers } },
    response: {
      status: resp.status,
      duration_ms: dt,
      headers: Object.fromEntries(resp.headers.entries()),
      body: json ?? text,
    },
    at: new Date().toISOString(),
  };
  const file = `./dumps/${mode}/${name}.json`;
  await writeFile(file, JSON.stringify(dump, null, 2));
  console.log(`  status ${resp.status} in ${dt}ms → ${file}`);
  if (resp.status >= 400) {
    console.log('  ERROR body:', text.slice(0, 500));
  }
  return { status: resp.status, json, text, headers: resp.headers };
}

function q(obj) {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(obj)) p.set(k, v);
  return '?' + p.toString();
}

// ---------------------------------------------------------------------
// Common: fan-side identity flow (should work with FAN_SCOPES)
// ---------------------------------------------------------------------

console.log(`\n=== PROBING as mode=${mode} ===`);
console.log(`Scopes granted: ${tokens.scope}`);
console.log(`Token expires in: ${tokens.expires_in}s (obtained ${tokens._obtained_at})`);

// 1. Bare identity (should work with just `identity`)
await call('01-identity-bare', '/api/oauth2/v2/identity');

// 2. Identity with everything the fan flow needs
const identityFields = [
  'email', 'first_name', 'last_name', 'full_name', 'image_url',
  'thumb_url', 'about', 'created', 'social_connections', 'vanity',
  'url', 'is_email_verified', 'hide_pledges', 'can_see_nsfw',
].join(',');

const memberFields = [
  'patron_status', 'last_charge_status', 'last_charge_date',
  'lifetime_support_cents', 'currently_entitled_amount_cents',
  'pledge_relationship_start', 'is_follower', 'full_name',
].join(',');

const campaignFields = [
  'created_at', 'creation_name', 'currency', 'image_small_url',
  'image_url', 'is_monthly', 'is_nsfw', 'main_video_embed',
  'main_video_url', 'name', 'one_liner', 'patron_count', 'pledge_url',
  'published_at', 'summary', 'url', 'vanity', 'has_rss',
  'rss_feed_title', 'rss_artwork_url',
].join(',');

const tierFields = [
  'amount_cents', 'created_at', 'description', 'image_url',
  'patron_count', 'post_count', 'published', 'published_at', 'title', 'url',
].join(',');

const identityFull = await call(
  '02-identity-full',
  '/api/oauth2/v2/identity' + q({
    'include': 'memberships,memberships.currently_entitled_tiers,memberships.campaign,campaign',
    'fields[user]': identityFields,
    'fields[member]': memberFields,
    'fields[campaign]': campaignFields,
    'fields[tier]': tierFields,
  }),
);

// Extract campaign IDs from memberships for the fan
const memberships = (identityFull.json?.data?.relationships?.memberships?.data) || [];
const includedByType = {};
for (const inc of (identityFull.json?.included || [])) {
  (includedByType[inc.type] ||= {})[inc.id] = inc;
}
console.log(`\nFan has ${memberships.length} memberships.`);
const memberCampaignIds = new Set();
for (const m of memberships) {
  const memberObj = includedByType.member?.[m.id];
  const campRelId = memberObj?.relationships?.campaign?.data?.id;
  if (campRelId) memberCampaignIds.add(campRelId);
}
console.log('Supported campaign IDs:', Array.from(memberCampaignIds));

// ---------------------------------------------------------------------
// Fan-side: attempt endpoints that we EXPECT to require creator scope,
// to confirm the failure modes and error shapes.
// ---------------------------------------------------------------------

if (mode === 'fan') {
  // Try to list campaigns owned by this user (should return empty for a
  // pure fan account, or the user's own campaign if they happen to be a
  // creator too).
  await call('03-my-campaigns', '/api/oauth2/v2/campaigns' + q({
    'fields[campaign]': campaignFields,
  }));

  // For each campaign the fan supports, try to read basic campaign info,
  // then try to read posts (this SHOULD fail without campaigns.posts on
  // that specific campaign). Recording exact error shape is valuable.
  for (const cid of memberCampaignIds) {
    await call(`04-campaign-${cid}`, `/api/oauth2/v2/campaigns/${cid}` + q({
      'include': 'tiers,creator,benefits,goals',
      'fields[campaign]': campaignFields,
      'fields[tier]': tierFields,
    }));
    await call(`05-campaign-${cid}-posts-DENIED`, `/api/oauth2/v2/campaigns/${cid}/posts` + q({
      'fields[post]': 'title,content,embed_url,embed_data,is_paid,is_public,published_at,url,tiers',
    }));
    await call(`06-campaign-${cid}-members-DENIED`, `/api/oauth2/v2/campaigns/${cid}/members`);
  }
}

// ---------------------------------------------------------------------
// Creator-side: full exploration of a campaign we own.
// ---------------------------------------------------------------------

if (mode === 'creator') {
  // Which campaigns does this creator own?
  const myCampaigns = await call('03-my-campaigns', '/api/oauth2/v2/campaigns' + q({
    'include': 'tiers,creator,benefits,goals',
    'fields[campaign]': campaignFields,
    'fields[tier]': tierFields,
  }));

  const campaignIds = (myCampaigns.json?.data || []).map(d => d.id);
  const cid = process.env.PROBE_CAMPAIGN_ID || campaignIds[0];
  if (!cid) {
    console.error('No campaign_id available. Creator account has no campaign?');
    process.exit(1);
  }
  console.log(`\nProbing creator-side against campaign_id=${cid}`);

  // Posts — the critical endpoint. Include everything we can, and
  // request every attribute we know about, so we can see the shape of
  // real video posts.
  const postFields = [
    'app_id', 'app_status', 'content', 'embed_data', 'embed_url',
    'is_paid', 'is_public', 'published_at', 'tiers', 'title', 'url',
  ].join(',');

  const postsResp = await call('10-posts-full', `/api/oauth2/v2/campaigns/${cid}/posts` + q({
    'include': 'campaign,user',
    'fields[post]': postFields,
    'page[count]': '25',
  }));

  const posts = postsResp.json?.data || [];
  console.log(`\nGot ${posts.length} posts. Scanning for video content...`);

  // Look at every post's content/embed fields and flag those that
  // reference video.
  const videoPosts = posts.filter(p => {
    const a = p.attributes || {};
    const hay = (a.content || '') + ' ' + (a.embed_url || '') + ' ' + JSON.stringify(a.embed_data || {});
    return /video|\.mp4|\.m3u8|hls|vimeo|youtube|player\.patreon|c10\.patreon|dcpv\d|patreonusercontent|stream/i.test(hay);
  });
  console.log(`  ${videoPosts.length} posts appear to reference video.`);
  await writeFile(`./dumps/${mode}/10a-video-posts-summary.json`, JSON.stringify(
    videoPosts.map(p => ({
      id: p.id,
      title: p.attributes?.title,
      embed_url: p.attributes?.embed_url,
      embed_data: p.attributes?.embed_data,
      content_preview: (p.attributes?.content || '').slice(0, 2000),
      published_at: p.attributes?.published_at,
      is_paid: p.attributes?.is_paid,
      tiers: p.attributes?.tiers,
      url: p.attributes?.url,
    })), null, 2));

  // Also individually GET a specific post if provided
  const targetPost = process.env.PROBE_POST_ID || videoPosts[0]?.id || posts[0]?.id;
  if (targetPost) {
    console.log(`\nDeep-diving single post id=${targetPost}`);
    await call(`11-post-${targetPost}`, `/api/oauth2/v2/posts/${targetPost}` + q({
      'include': 'campaign,user',
      'fields[post]': postFields,
    }));
  }

  // Members
  await call('20-members-page1', `/api/oauth2/v2/campaigns/${cid}/members` + q({
    'include': 'currently_entitled_tiers,user',
    'fields[member]': memberFields,
    'fields[tier]': tierFields,
    'page[count]': '5',
  }));

  // Webhooks list
  await call('30-webhooks', '/api/oauth2/v2/webhooks');

  // Lives (early-access)
  await call('40-lives-list', `/api/oauth2/v2/campaigns/${cid}` + q({
    'include': 'live_access_rules',
    'fields[campaign]': campaignFields,
  }));

  // RSS feed URL — the docs say the campaign has has_rss / rss_feed_title.
  // Let's check whether the campaign has a public RSS URL by hitting
  // patreon.com/rss/<vanity> and /rss/campaign/<id> patterns.
  const camp = myCampaigns.json?.data?.[0]?.attributes;
  const vanity = camp?.vanity;
  if (vanity) {
    console.log(`\nProbing RSS variants for vanity=${vanity}`);
    for (const p of [
      `/rss/${vanity}`,
      `/rss/campaign/${cid}`,
      `/rss/user/${cid}`,
    ]) {
      const r = await fetch(`https://www.patreon.com${p}`, {
        headers: { 'user-agent': USER_AGENT, accept: 'application/rss+xml, application/xml, text/xml' },
        redirect: 'manual',
      });
      const t = await r.text();
      console.log(`  ${p} -> ${r.status} ${r.headers.get('location') || ''} (${t.length} bytes)`);
      await writeFile(`./dumps/${mode}/50-rss${p.replace(/[^a-z0-9]/gi, '_')}.txt`, `HTTP ${r.status}\n${JSON.stringify(Object.fromEntries(r.headers.entries()), null, 2)}\n\n${t.slice(0, 8000)}`);
    }
  }
}

// ---------------------------------------------------------------------
// Rate-limit probe: fire a few rapid requests and inspect headers.
// ---------------------------------------------------------------------

console.log('\n=== rate-limit probe (5 quick /identity calls) ===');
for (let i = 0; i < 5; i++) {
  const r = await call(`rl-${i}`, '/api/oauth2/v2/identity');
  // Print any rate-limit related headers
  const relevant = ['x-ratelimit-remaining', 'x-ratelimit-limit', 'retry-after', 'x-patreon-uuid'];
  for (const h of relevant) {
    const v = r.headers.get(h);
    if (v) console.log(`  ${h}: ${v}`);
  }
}

console.log('\n=== done ===');
console.log(`Dumps written under ./dumps/${mode}/`);
