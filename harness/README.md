# Patreon TV — live-testing harness

A tiny, no-magic OAuth + probe rig. Uses only Node stdlib + `dotenv`.

## What it does

1. `npm run auth -- fan` — opens the Patreon OAuth authorize URL,
   catches the redirect, exchanges the code for tokens, saves them.
2. `npm run auth -- creator` — same but with creator-side scopes.
3. `npm run probe:as-fan` — hits every endpoint a fan-scoped token can,
   plus the ones we EXPECT to fail (to see the error shapes).
4. `npm run probe:as-creator` — full creator-side sweep, especially
   scanning real posts for video content so we can see what
   `embed_url` / `embed_data` / `content` actually look like.

## Setup

```
cd harness
cp .env.example .env
# edit .env — set PATREON_CLIENT_ID, PATREON_CLIENT_SECRET,
# PATREON_REDIRECT_URI (must match what you set in the Patreon portal),
# and USER_AGENT
npm install
```

Register the OAuth client at:
https://www.patreon.com/portal/registration/register-clients

Set the redirect URI in Patreon's portal to exactly:
`http://localhost:8721/callback`

Note: Patreon requires a creator account to register OAuth clients.
Even for a pure consumer app.

## Running

```
# Fan-side flow — sign in as a Patreon user who supports at least one
# creator. This probes: identity, memberships, campaigns you support,
# and confirms that /posts and /members are denied without creator
# authorization.
node auth-server.js fan
node probe.js fan

# Creator-side flow — sign in as the OWNER of a campaign that has real
# posts (ideally including a member-only video post). This is where we
# find out what video content actually looks like in the API.
node auth-server.js creator
node probe.js creator
```

Every response is written to `./dumps/<mode>/*.json` so you can inspect
exactly what came back.

## What we're looking for

- `dumps/fan/02-identity-full.json` — the shape of the fan's data
- `dumps/fan/05-campaign-*-posts-DENIED.json` — the error shape when a
  fan tries to read another creator's posts
- `dumps/creator/10a-video-posts-summary.json` — the KEY file. What do
  video posts look like? Is there a playable URL? Is `embed_url`
  pointing at a Patreon CDN, Vimeo, YouTube, or something else?
- `dumps/creator/11-post-<id>.json` — a single deep-dive on one video
  post
- `dumps/creator/50-rss*.txt` — whether Patreon exposes a public RSS
  feed with playable enclosures (potential audio/video fallback)

## Safety

- Tokens land in `./tokens/` — gitignored. Do not commit.
- `.env` is gitignored.
- The probe never writes to Patreon — all reads are GET.
