# Patreon Platform — Evidence-Based Research for an Apple TV Client

Research window: **2026-07-06** (Pacific time). All URLs fetched with User-Agent
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15` unless noted.
Sources saved under `/tmp/patreon-research/`. Line numbers cite files
in `/tmp/patreon-docs/` (official docs, previously extracted) or files in
`/tmp/patreon-research/` (fetched here).

**Confidence rating legend**
- **HIGH** — official Patreon docs, or direct quote from a Patreon-staff-tagged forum post.
- **MEDIUM** — reproducible forum consensus, third-party code that clearly works, or
  Patreon-adjacent staff (e.g. WordPress-plugin dev @codebard).
- **LOW** — single source, inference, or reverse-engineering that could be stale.

---

## 0. Executive summary (read this first)

1. The **public API does not expose playable media URLs for post content.**
   - `Post v2` has attributes `content` (HTML), `embed_url`, `embed_data`, and no
     documented `media` / `audio` / `video` relationship.
     (`docs-main.md` lines 3059–3163.)
   - Patreon staff @noertap, 2026-06-19: "The embed_url returns the link attached
     to a post, if the post was a 'link' post type. **Media / images attached to
     the post is not available via the api.**" (topic 11355)
2. The **public API only exposes posts you own** (creator side).
   - `campaigns.posts` scope is described as "Provides read access to the posts
     on **a campaign**" (docs `campaigns/{id}/posts` requires that scope).
     There is no scope like `identity.posts` or `identity.feed`.
   - Patreon staff @noertap, 2025-12-15: **"There is no public api to list
     available posts / feed for patrons. Official android and iOS clients use
     internal apis which should not be used by 3rd parties — the endpoints may
     change and requests could get blocked by Patreon security rules."** (topic 11193)
   - When asked whether a hobbyist FOSS Patreon Android client could rely on
     the internal API "for reasonable use", @noertap replied: **"I would advise
     against any usage — there have been cases when 3rd party apps suddenly
     break because of security rules or changes to the non public APIs."**
3. Native-app OAuth is a second-class citizen.
   - `redirect_uri` must be pre-registered http/https; **custom URL schemes
     are rejected**. Multiple community reports 2018–2023, never contradicted.
   - **No PKCE.** Patreon-adjacent staff @codebard, 2022-02-07: "Some work on
     the api is being mulled, however implementing PKCE is not among the
     potential changes at this moment." (topic 5178)
   - No device-authorization-grant. No `mobile`/`native`-oriented flow.
4. The one **shipping** open-source Apple TV client (`kochj23/PatreonTV`, MIT,
   v3.0.0, 2026-05) works around every limit by running a **macOS relay** that
   logs into `patreon.com` in a `WKWebView`, stores the `session_id` cookie, and
   hits `https://www.patreon.com/api/…` (the same internal API) with that
   cookie. It also shells out to `yt-dlp` for YouTube/Vimeo embeds. Apple TV
   never talks to Patreon directly.
5. The **Apple ecosystem tension** is real and current. In October 2024, Patreon
   announced Apple compelled them onto IAP for new memberships in the
   Patreon iOS app; this has already reshaped Patreon's billing models (topic 9320).
   For a third-party consumer client on tvOS, this means anything that looks
   like "unlocking paid content" outside IAP will get scrutinized.
6. The **v2 Terms of Use** (updated 2026-05-27) grant fans a
   "non-exclusive, non-transferable, non-sublicensable, revocable, limited
   license to access and view those creations for your own **private, personal,
   non-promotional, non-commercial** use" (lines 172 of `legal-clean.txt`).
   Patreon's own IP (APIs, apps, embeds) may not be reproduced / prepared as
   derivative works "unless we give you permission in writing" (line 225).
7. The **API is in de-facto maintenance mode.** All non-WordPress client
   libraries had their last real commit in **2018–2019**; the "activity" in
   March 2026 was a single automated PR adding "API v1 deprecation notice" to
   READMEs. Patreon docs preamble (2026): "We are committed to ensuring
   continued access to the Patreon API. Existing API functionality will
   continue to be supported and maintained... we will have limited capacity in
   the near term to respond to questions through the developer forum."

---

## 1. Official docs recap (what the API actually is)

Source: `/tmp/patreon-docs/docs-main.md` (extracted from
`https://docs.patreon.com/` snapshot).

### 1.1 API surface (v2)

Endpoints (`docs-main.md` lines 157–213):

- `GET /api/oauth2/v2/identity`
- `GET /api/oauth2/v2/campaigns`
- `GET /api/oauth2/v2/campaigns/{campaign_id}`
- `GET /api/oauth2/v2/campaigns/{campaign_id}/members`
- `GET /api/oauth2/v2/members/{member_id}`
- `GET /api/oauth2/v2/campaigns/{campaign_id}/posts`
- `GET /api/oauth2/v2/posts/{id}`
- `POST /api/oauth2/v2/lives`, `GET /api/oauth2/v2/lives/{id}`, `PATCH …`
- Webhook CRUD

Notably absent: **any "fan feed" endpoint**, any "media" endpoint,
any post-creation endpoint, any comments/likes/tags endpoint.

### 1.2 Scopes (docs-main.md lines 1050–1109)

- `identity`, `identity[email]`, `identity.memberships`
- `campaigns`
- `w:campaigns.webhook`
- `campaigns.lives`, `w:campaigns.lives`
- `campaigns.members`, `campaigns.members[email]`, `campaigns.members.address`
- `campaigns.posts` — **"Provides read access to the posts on a campaign."**

There is no fan-side `identity.posts` or `identity.feed`. `campaigns.posts` is
only useful if the authenticated user owns the campaign in question. (This is
also why the fan-facing Apple TV use case has no direct public path.)

Also (lines 1112–1120): **scope union bug** — "During the OAuth2 authorization
flow, Patreon currently appends newly requested scopes to any scopes a user has
previously approved. Scopes are not overwritten or reduced." — reauthorizing
with fewer scopes doesn't reduce; be aware for permissions UX.

### 1.3 Post v2 attributes (docs-main.md lines 3059–3163)

| Attribute | Type | Notes |
|---|---|---|
| `app_id`, `app_status` | int / string | For posts created via API |
| `content` | string | "may include html tags" |
| `embed_data` | object | "if media is embedded in the post" |
| `embed_url` | string | "Embed media url. Can be null." |
| `is_paid` | bool | pay-per-post |
| `is_public` | bool | patron-only or not |
| `published_at` | string |  |
| `tiers` | collection | tier IDs that gate the post (added 2022-11-18 per topic 6491) |
| `title` | string |  |
| `url` | string | patreon.com URL |

**Post v2 relationships**: only `campaign` and `user`. **No `media`, no
`audio`, no `video`, no `attachments_media`.** `include=media` returns 400
`ParameterInvalidOnType` (topic 2670). **This is the single most important
fact about the API for a video client.**

### 1.4 Media resource (docs-main.md lines 2586–2685)

The `Media` resource exists in the docs but has no documented
relationship coming back from `Post`. Fields include:

- `download_url` — "The URL to download this media. **Valid for 24 hours.**"
- `image_urls` — "The resized image URLs for this media. **Valid for 2 weeks.**"
- `mimetype`, `size_bytes`, `state`, `metadata`, `file_name`
- `owner_id`, `owner_type`, `owner_relationship`
- `upload_url`, `upload_parameters`, `upload_expires_at` — for creator uploads

Because there is no `Post → Media` relationship in v2 today, **you cannot
reach these fields from a post via the public API.** (`docs-main.md` line
3142, `Post v2 Relationships`.)

### 1.5 Live (docs-main.md lines 2510–2583)

`Live` is producer-side only. `rtmp_url` and `stream_key` are for **publishing**
to Patreon, not consuming. Consumers get no playback URL from the public API.
Endpoint is marked "early-access, may be subject to change" (lines 1520, 1552).

### 1.6 Campaign has RSS metadata, no RSS URL

`Campaign v2` attributes include (lines 2167–2273):
- `has_rss` — "Whether this user has opted-in to rss feeds."
- `has_sent_rss_notify`
- `rss_artwork_url`
- `rss_feed_title`

**No `rss_feed_url` field.** The actual per-user tokenized RSS URL is
generated inside patreon.com and given to the patron in their account page;
it is **not exposed via the API**. Confirmed by community complaints from
2018 to 2021 (topic 432: "Access My Audio Rss Link via API", 3 years, no
resolution).

### 1.7 Rate limits (docs-main.md lines 935–1010)

- **Client**: 100 requests per **2 seconds**.
- **Access Token**: 100 requests per **minute**.
- "Refreshing an access token does not reset or bypass the rate limits."
- 429 responses may include `retry_after_seconds`.
- **Edge rate limit**: >2,000 4xx responses in 10 minutes → **30-minute block**.
- Triggered most by repeated 401 / 429. (Meaning: badly implemented auth
  handling can get you soft-banned for half an hour.)
- Change dates: rate limits updated 2024-10-14, edge rate limits added
  2025-07-04 (docs-main.md lines 437–441). Announcement topic 9459
  (@codebard, 2024-10-27) confirms these were newly imposed; before Oct 2024
  the limits weren't publicly documented.

### 1.8 Error codes (docs-main.md lines 872–933)

Standard 400/401/403/404/405/406/410/429/500/503. Nothing surprising.

### 1.9 OAuth (docs-main.md lines 605–870)

Server-side authorization-code flow only. `code`, `redirect_uri` (must be
pre-registered), token exchange requires `client_secret`. `refresh_token`
provided. No PKCE, no device grant, no implicit, no custom URL schemes.

**Confidence: HIGH** for everything in section 1 — quoted directly from docs
snapshot with line numbers.

---

## 2. Video playback — what we actually know

This is the biggest unknown, so it gets its own section.

### 2.1 Public API view

Everything a Post v2 tells you about media is:
- `embed_url` (nullable string)
- `embed_data` (nullable object, undocumented shape)
- `content` (may include HTML)

There is **no `media` relationship, no `attachments`, no signed CDN URL,
no HLS/DASH manifest URL, no MP4 URL** on the Post resource in v2.

### 2.2 What `embed_url` / `embed_data` actually is

Patreon staff @noertap, 2026-06-19 (topic 11355):
> "The `embed_url` returns the link attached to a post, if the post was a
> 'link' post type. Media / images attached to the post is not available via
> the api."

Practical implication (medium confidence, corroborated by @codebard 2022-01-20
in topic 2670 and 2020-07-13 in topic 3417):
- **Patreon-uploaded video posts** → `embed_url` and `embed_data` are
  effectively **null** in the public API.
- **YouTube-embed video posts** → `embed_url` holds the YouTube link and
  `embed_data` has the embed provider metadata (title, description, provider).
- **Vimeo-embed video posts** → same pattern as YouTube.
- **Audio uploads** → `embed_url` / `embed_data` are null. No `audio_url`
  from the public API.

Corroboration by direct observation from a paid partner project
(`podcastappmaker`, topic 2670, 2022-01-18):
> "For audio posts, there is the option to upload a file, or use an embedded
> link. Using the embedded route I am seeing data within `embed_data` and
> `embed_url`. With the file upload, these fields are null, and there does
> not appear to be an attribute for regular files within the post resource."

And @codebard's 2023-06-12 confirmation (topic 6158):
> "Currently the api does not provide detailed info like embeds, featured image
> and attachments, so these cannot be synced. If the video was put into the
> post's text as an embed code, it would have come in. But as it is now, it
> wouldn't be synced."

**Confidence: HIGH** on "public API returns nothing playable for
native/attachment uploads." **Confidence: MEDIUM** on the exact YouTube/Vimeo
shape (based on staff quotes + wp-plugin field selectors).

### 2.3 What the `content` HTML contains

For posts where video was embedded as raw HTML in the body, that HTML flows
through `content`. That's the ONLY current path for a public-API-only client
to see any playable link — and only if the creator used the "add URL" trick
inside a text body (@codebard, topic 6158 post 12; @codebard, topic 4723).

For posts where the creator used Patreon's native "video post" type OR
attached a file, `content` will not contain the URL. It will not be reachable
via the public API at all.

### 2.4 Reverse-engineering evidence: what the internal web API actually returns

Source: `miniBill/secretdemoclub` GitHub repo (referenced by the author in
forum topic 11355, 2026-05-27, as their workaround after "giving up on the
official API"). The repo contains an OpenAPI 3.1 spec (`cron/src/openapi.yaml`,
1179 lines) reverse-engineered against `https://www.patreon.com/api`. Also
matches what `kochj23/PatreonTV` uses.

**Server URL**: `https://www.patreon.com/api` (not `/api/oauth2/v2`).
**Auth**: session cookie (`session_id=…`), not `Bearer`.

**Post types observed (`sdc-openapi.yaml` lines 976–990):**
```
- post, podcast, livestream_youtube, text_only, image_file, link,
  video_embed, video_external_file, poll, livestream_crowdcast,
  audio_embed, audio_file
```

**Post → Media relationships (sdc-openapi.yaml lines 947–969):**
```
access_rules, attachments_media, audio, audio_preview, images,
video, media, user_defined_tags, content_unlock_options
```
All are `ListOfIdAndType`. Media is included via `include=media`,
`include=attachments_media`, `include=images`, `include=audio`, `include=video`.

**`IncludedMedia` attributes (sdc-openapi.yaml lines 412–474):**
```
display: PostFile (oneOf PostAudioVideo / PostImage / PostSize)
download_url: uri
file_name: string | null
image_urls: {default, default_blurred, default_blurred_small, default_large,
             default_small, original, thumbnail, thumbnail_large,
             thumbnail_small, url}
metadata: {variant, orientation, duration, duration_s,
           video_preview_end_ms, audio_preview_duration,
           video_preview_start_ms, audio_preview_start_time,
           start_position, dimensions {h, w}}
```

**`PostAudioVideo` (sdc-openapi.yaml lines 727–780):**
```
default_thumbnail.url, duration, full_content_duration, media_id,
state, url, width, height, progress {is_watched, watch_state},
closed_captions_enabled, video_issues, expires_at, viewer_playback_data,
storyboard, transcript_url
```

The **`url`** field on `PostAudioVideo` is what actually plays. Whether it's
a signed CDN URL, an HLS manifest, or a direct MP4 is not documented in the
schema, but `kochj23/PatreonTV`'s implementation treats it as a URL that
requires **cookie-based redirect resolution** — the relay follows the redirect
carrying the `session_id` cookie and captures the final CDN URL, then proxies
byte ranges to the Apple TV. That behavior is consistent with a signed /
cookie-gated CDN redirect (see next section).

**Confidence: MEDIUM** on the shape (single reverse-engineered source, but two
independent projects — miniBill's Elm code and kochj23's Swift code —
converged on it).

### 2.5 CDN URLs

- Public API sample response uses `https://c8.patreon.com/2/400/0000000` for a
  user avatar (`docs-main.md` lines 4035, 4051, 4271). `c8`/`c10.patreon.com`
  hosts show up in old forum posts (topics 4070, 1340, 4719 etc.) as legit
  Patreon-served image CDN.
- Nothing in the public API returns a `c*.patreon.com` **video** URL. All
  observed video URLs come from the internal-API `Media.display.url` path,
  which requires cookie-based redirect resolution (topic 4723 discussion of
  embedly + referrer-based access).
- `Media.download_url` (public API) has documented **24-hour validity**
  (`docs-main.md` line 2611). This implies it's a **signed / time-limited URL**
  when it exists — but again, you can't reach it from a Post today.
- `Media.image_urls` (public API) has documented **2-week validity**
  (`docs-main.md` line 2623). Also implies signed URLs.

**Confidence: MEDIUM** — extrapolating from documented TTLs. HIGH on the fact
that URLs expire.

### 2.6 What `kochj23/PatreonTV`'s architecture tells us (2026-05)

Source: `ghreadme-kochj23_PatreonTV.md`, `tmp-PatreonAPI.swift`,
`ptv-mediaproxy.swift`, `sdc-openapi.yaml`.

Endpoints used (from `Shared/Services/PatreonAPI.swift`):
- Base: `https://www.patreon.com/api` (internal, cookie-authed).
- `GET /api/current_user?include=memberships.campaign&fields[user]=…`
- `GET /api/current_user/memberships?include=campaign&fields[campaign]=…&fields[member]=…`
- `GET /api/stream?include=user,campaign,attachments_media,post_file,media,audio,images&fields[post]=…,post_file&fields[campaign]=name,avatar_photo_url,url&fields[media]=download_url,image_urls,media_type,file_name,metadata&page[count]=…`
- `GET /api/campaigns/{campaignId}/posts?include=…` (internal, not v2)
- `GET /api/posts/{postID}?include=campaign,attachments_media,post_file,audio,media,images&fields[post]=…,post_file,url,post_metadata,video_preview,current_user_can_view,content,teaser,embed`

Auth header used: **`Cookie: session_id=<sid>`** + `Referer: https://www.patreon.com`.

Media resolution (from `MediaProxyService.swift`):
1. Fetch `GET /api/posts/{id}` with session cookie.
2. Extract `post_file.url` (Patreon video) or `audio.url` (Patreon audio) or
   `embed_url` (YouTube/Vimeo).
3. For Patreon-hosted: issue a request to that URL with session cookie +
   Referer, follow the 3xx redirect, capture the final CDN URL, then proxy
   the response (chunked, with Range forwarded) to AVPlayer.
4. For YouTube/Vimeo: run `yt-dlp` locally, get HLS URL, 302-redirect
   AVPlayer to it.

Design choices worth internalizing:
- **HLS is 302-redirected, not proxied**, because rewriting HLS manifests
  breaks segment resolution.
- **CDN streams are proxied**, because AVPlayer can't carry the cookie.
- URL cache 5 min TTL.
- **7 rotating User-Agents** + web-player client for yt-dlp anti-throttling.
- Session tokens stored in Keychain on tvOS.
- Bonjour + subnet-scan pairing between Apple TV and Mac relay.
- MIT license, ~5300 LOC, 3 targets.

**Confidence: HIGH** — this is running code, well-documented in a shipping repo.

### 2.7 Summary of playback paths (with confidence)

| Path | What you get | Confidence | Notes |
|---|---|---|---|
| Public API `/posts/{id}` + `embed_url` (YouTube/Vimeo) | Third-party embed URL only | HIGH | You still need yt-dlp / an official player to actually stream |
| Public API `/posts/{id}` + `embed_url` (Patreon-native video) | `null` | HIGH | Not returned |
| Public API `/posts/{id}` + `Media.download_url` | Not reachable from Post | HIGH | Post→Media relationship not exposed |
| Public API `/posts/{id}` + HTML-embed in `content` | Whatever URL creator pasted | MEDIUM | Only if creator used a text body with embed HTML |
| Internal `/api/posts/{id}` + `post_file.url` + session cookie | Direct playable CDN redirect | MEDIUM | What kochj23/PatreonTV uses; explicitly discouraged by staff |
| RSS feed (per-user token, audio-only) | Enclosure MP3 URLs | MEDIUM | Not accessible via API; must be provided by user (see §5) |

---

## 3. OAuth, authentication, mobile / native / tvOS

### 3.1 Only server-side authorization code flow is officially supported

`docs-main.md` lines 626–800 describe the classic OAuth 2.0 code flow:
`response_type=code`, exchange at `POST /api/oauth2/token` with `client_secret`.

**Historical staff position (Patreon, @phildini, 2018-04-23, topic 498):**
> "as of today the Patreon API does not support native apps for any platform,
> we only support server-side applications that can follow the server-side
> OAuth flow."

**Also historical staff position (Patreon, @telaviv, 2017-11-22, topic 110):**
> "we don't currently support an oauth type that can be used in mobile. Our
> current oauth type requires using sending us your client secret and on
> mobile it's not secure to store that. This is on our TODO list but we don't
> really have a timetable for you unfortunately. One option that may work for
> you is to have web app embedded in a webview that does the normal oauth flow."

Nine years later, this is still true. The 2025 topic 11057 shows a developer
successfully doing a **PKCE-style public client** flow, but their app's
"Connected Apps" page shows a broken-token warning, suggesting Patreon's
backend doesn't fully recognize public clients — the *auth* worked but the
account UI didn't (topic 11057, unresolved).

**Confidence: HIGH.**

### 3.2 No PKCE (as of 2022-02-07)

@codebard (Patreon-adjacent), topic 5178:
> "Some work on the api is being mulled, however implementing PKCE is not
> among the potential changes at this moment."

**No later contradiction found** in the 2023–2026 forum. Given the March 2026
docs preamble ("Our team is focused on developing our core product at this
time") the odds of PKCE landing soon are low.

**Confidence: MEDIUM** (absence of evidence, plus 2022 staff-adjacent quote).

### 3.3 No device authorization grant

Nothing in `docs-main.md` (searched: `device`, `oauth`, `grant`). No forum
thread references it. `search-device.json` returned 12 hits, none about the
OAuth 2.0 Device Authorization Grant (RFC 8628).

**Confidence: HIGH** (documented absence).

### 3.4 `redirect_uri` restrictions

- Must be pre-registered.
- Must be `http` or `https`.
- **Custom URL schemes** (e.g. `myapp://callback`) are rejected. Multiple
  reports 2018 (topic 498, UWP `ms-app://`), 2022 (topic 6023, Android),
  2023 (topic 7527, Flutter). Never confirmed to work. `amirsaam`'s
  PatreonAPI-Swift README (2024) still says "Patreon doesn't support App
  URL Scheme."
- **App-links / universal-links** (https URLs claimed by the app via a
  `.well-known/apple-app-site-association` file) are the recommended workaround.
  Topic 6023 (2022) uses Firebase Dynamic Links; topic 7527 (2023) had
  problems because their host didn't allow `.well-known` directories.

**Practical implication for tvOS**: tvOS does not have a browser tab you can
redirect back from. The community pattern is:
- **Option A**: an intermediary web app catches the redirect and pushes the
  code to the device via Firebase Cloud Messaging / server push / QR polling.
- **Option B (kochj23/PatreonTV):** an accompanying **macOS relay app** does
  a `WKWebView` login and holds the session, Apple TV never touches OAuth.
- **Option C (shizukusoft/PatronArchiver):** embed a `WKWebView` inside the
  app (tvOS supports `WKWebView` since tvOS 14 for text/limited UI, but full
  WebView-based login on tvOS is UX-hostile; typically requires a companion
  device flow).

**Confidence: HIGH** (multiple corroborating threads + third-party code).

### 3.5 Scope union bug

Docs (lines 1112–1120) note that scopes granted via multiple authorizations
**union**, never subtract. So requesting a smaller scope set at re-auth does
not reduce the token's actual scopes. Design implication: don't rely on
narrow scopes for privilege gating; the token may have more than you asked
for.

**Confidence: HIGH.**

### 3.6 One-token-per-client-per-user (historical)

Topic 1641 ("[RESOLVED] API token invalidated when second client
authenticates as same user", 2019). Historical, but suggests two devices of
the same client authenticating the same user would step on each other. Not
re-tested here; **flag for live testing**.

**Confidence: LOW.**

### 3.7 Patreon's own mobile apps — how do they auth?

- No public evidence of how the official Patreon iOS/Android apps auth.
- Staff @noertap (2025-12-15, topic 11193): "Official android and iOS clients
  use internal apis which should not be used by 3rd parties."
- Web-session-based auth (session cookie) is what `kochj23/PatreonTV` and
  `miniBill/secretdemoclub` observed. Patreon's own apps almost certainly
  use a session-token flavor internally, plus IAP receipt validation for
  payments (see §6 & §9).
- **No public network-capture / reverse-engineering write-up** found in the
  time budget for this research.

**Confidence: LOW** (inference from third-party reverse-engineering and the
staff quote about "internal apis").

---

## 4. Real API response shapes — what actual posts look like

### 4.1 Sample /identity (docs-main.md lines 1186–1221)

```json
{
  "data": {
    "attributes": { "email": "[email protected]", "full_name": "Platform Team" },
    "id": "id",
    "relationships": {
      "campaign": {
        "data": { "id": "id", "type": "campaign" },
        "links": { "related": "https://www.patreon.com/api/oauth2/v2/campaigns/id" }
      }
    },
    "type": "user"
  },
  "included": [ { "attributes": {"is_monthly": true, "summary": "Hi There"}, "id":"id", "type":"campaign" } ]
}
```

### 4.2 Sample campaign (docs-main.md lines 1247–1276)

Shows `main_video_embed: null` and `main_video_url: "https://example.url"`
being possible. These fields exist only on the Campaign (the creator's
splash video), not on posts.

### 4.3 Sample webhook payload (docs-main.md lines 1795–1837)

Standard JSON:API envelope. `X-Patreon-Signature` = HEX(HMAC-MD5(body, secret))
(line 1792). Uses MD5 which is disappointing in 2026 but that's what's documented.

### 4.4 What a real post looks like from the community

From topic 5785 (@chockenberry, 2022-07-14), an actual /posts/{id} response
before he added `fields[post]=`:

```json
{
  "data" : {
    "attributes" : {},
    "id" : "<post_id>",
    "type" : "post"
  },
  "links" : {
    "self" : "https://www.patreon.com/api/oauth2/v2/posts/<post_id>"
  }
}
```

Without `fields[post]=…` **you get no attributes at all**. Common trap: URL-
encoding the `=` sign in the query string yields the same empty response.
Correct form (topic 5785 post 4):
```
fields%5Bpost%5D=title,content,is_paid,is_public,published_at,url,embed_data,embed_url,app_id,app_status
```
(brackets encoded, `=` and commas kept literal).

### 4.5 Recommended field selector (from Patreon WordPress plugin)

@codebard's canonical post-details fields (topic 3006, 2020-04-13):

```
?fields[post]=title,content,is_paid,is_public,published_at,url,embed_data,embed_url,app_id,app_status
```

Note the **absence of** any media / attachment / featured-image / video URL
fields — because those don't exist on Post v2.

### 4.6 Pagination reality (topic 4340)

- Default page size returns **20 posts**.
- **Ordering (`sort`) may not be implemented for posts**; you may just get
  "the oldest 20." Workaround: paginate via `links.next` (JSON:API cursor)
  until it disappears. @codebard, 2021-04-07: "Yeah. That's the way to do it.
  The next cursor."
- `page[count]=1000` is **not honored**. You still get ~20.

**Confidence: HIGH** on all of §4 (docs + reproduced by many devs).

---

## 5. RSS feeds

### 5.1 What Patreon exposes

- On Campaign: `has_rss`, `has_sent_rss_notify`, `rss_feed_title`,
  `rss_artwork_url`. **No `rss_feed_url`.** (docs-main.md lines 2167–2273)
- Nothing on Post about RSS.

### 5.2 Community history

- Topic 432 (2018-04-04, "Access My Audio Rss Link via API") — never resolved.
- Topic 400 (2018), 2522 (2019), 840 (2018), 3658 (2020), 8955 (2024), etc:
  all about creators' inability to programmatically obtain, filter, or
  protect the RSS feed.
- Topic 1659 (2019): "Accessing Patreon-only feed via API" — no reply,
  no product change since.

### 5.3 What RSS is (from creator-facing knowledge, MEDIUM confidence)

- Patreon generates **per-patron tokenized RSS URLs** for creators who
  opt in. These are given to the patron via the patreon.com UI (My
  Memberships → RSS), not the API.
- Format is standard podcast RSS 2.0 with `<enclosure>` tags for audio.
- **Audio-only.** No video enclosures.
- Includes patron-only episodes gated by the per-patron token.
- The `help.patreon.com` article (218725006) is the canonical explanation
  but was **not reachable** from this workspace's DNS (`Could not resolve
  host: help.patreon.com`), so I couldn't fetch it here. Flag as an item
  to check with the fresh browser during live testing.

### 5.4 Implication for the Apple TV client

RSS is a plausible **audio-only side path** for podcasters, but:
- It requires each user to paste their own RSS URL (like a podcast app).
- No video content.
- No creator/tier structure — it's a flat feed per creator.
- Not a general answer for a Patreon Apple TV video client.

**Confidence: MEDIUM.**

---

## 6. App Directory (integrations page) and getting approved

### 6.1 The page

- `https://www.patreon.com/apps` (200 OK) is the "Partnerships and App
  Integrations" page. Lists partners like Vimeo, Discord, Discourse, itch.io,
  ConvertKit, Zapier, Keeper, Bonjoro, Codebard WordPress Plugins, Crowdcast,
  Format, MailChimp, etc. (`legal-www.patreon.com_apps.html`).
- `https://www.patreon.com/appdirectory` — 404.
- `https://www.patreon.com/app-directory` — 404.
- The developer portal's "Submitting an Integration" page (`portal-submit.html`,
  `p-applications-submitting-an-integration.html`, etc.) is **empty**
  (0 bytes on disk). Docs preamble says "app directory" but with limited
  process explanation.

### 6.2 Docs preamble on the app directory (docs-main.md lines 471–498)

> "If you are a third party developer looking to get your app added to our
> app directory, follow the instructions here."
>
> "Public API v1 is no longer maintained and will be deprecated soon."
>
> "We are committed to ensuring continued access to the Patreon API. Existing
> API functionality will continue to be supported and maintained... we will
> have limited capacity in the near term to respond to questions through the
> developer forum."

The "instructions here" link goes to the portal submit page — which currently
404s / returns empty. **In practice, the App Directory acceptance process is
opaque and undocumented.** Look at the partners listed: they are almost all
**creator-side tools** (Wordpress, Discord, email marketing, taxes, insurance,
merch), not **fan-side content clients**. There is no example of a "third-
party consumer app" like a Patreon Apple TV client in the current directory.

### 6.3 Partner-tier / private-API access

- No public information about a partner tier that grants richer API access.
- Older docs and forum messages (2018–2019) reference `[email protected]`
  for "organization looking to partner", still present in current docs (line
  468). No documented tier / SLA / private endpoints.

**Confidence: MEDIUM** (absence of evidence + status of `/apps` page).

---

## 7. Terms of Service — implications for a third-party consumer app

Source: `https://www.patreon.com/policy/legal` (`legal-clean.txt`, fetched
2026-07-06, ToS "Last Updated" May 27, 2026). Community Guidelines at
`/policy/guidelines` (`guidelines-clean.txt`).

### 7.1 Fan license to view creations (line 172 of legal-clean.txt)

> "…to the extent a subscription or offering includes access to one or more
> of a creator's creations, that creator grants you a non-exclusive,
> non-transferable, non-sublicensable, revocable, limited license to access
> and view those creations for your own **private, personal, non-promotional,
> non-commercial use**."

Implication: A viewer app that lets an authenticated fan watch their own
paid-for content is **within the license**. Redistribution, sharing to
other users, or commercial resale is not.

### 7.2 Patreon's IP (line 225 of legal-clean.txt)

> "Our creations are protected by copyright, trademark, patent, and trade
> secret laws. Some examples of our creations are the text on the
> www.patreon.com site, the text on Patreon's other websites, **our iOS and
> Android apps, our APIs, our embeds, our logo, and our codebase.** We grant
> creators a license to use our logo and other trademarks to promote their
> Patreon pages. **You may not otherwise use, reproduce, distribute, perform,
> publicly display, or prepare derivative works of our creations unless we
> give you permission in writing.** Please ask if you have any questions."

Implications:
- The public API itself is Patreon IP; consuming it per docs terms is fine.
- Their embed HTML is Patreon IP — copying / redistributing the embed player
  is not fine.
- Their iOS/Android app code is IP; reverse-engineering the internal API
  routes it uses is legally grey (see §7.4).

### 7.3 Third-party access is user-authorized (line 221)

> "You may grant third-party apps and services access to your Patreon
> account, and you may grant Patreon access to third-party apps and services.
> You may also revoke this access."

That is the explicit permission slip for our OAuth-based app.

### 7.4 API terms

- `https://www.patreon.com/policy/legal/api-terms` → **404**.
- `https://www.patreon.com/policy/api-terms` → not found.
- **No dedicated developer-terms document is publicly linked.**
- The main ToU is the operative agreement. It contains no explicit "you may
  not use the internal, undocumented API" clause. However, ToS section on
  Patreon IP (line 225) + the docs-page preamble "the public API endpoints
  documented here" + staff quote @noertap "should not be used by 3rd parties"
  taken together add up to a **soft prohibition** without a hard legal one.

**Confidence: HIGH** on absence of documented dev-terms; **MEDIUM** on the
inferred position.

### 7.5 App Store implications (lines 136–147, 195)

The ToU repeatedly acknowledges that "certain platforms (like the App
Store)" impose fees, handle chargebacks/refunds, and require Patreon to
"automatically increase the prices of offerings to members to account for
the fees imposed by the platforms (like the App Store) on which the
associated purchases were made."

**This means Patreon has already made the concessions Apple demands for
their own iOS app** — and the Announcement in topic 9320 (2024-10-01) makes
clear those concessions include:
- **All new memberships purchased in the Patreon iOS app must go through
  Apple IAP starting November 2024.**
- Only subscription billing is supported by Apple IAP; per-creation and
  first-of-the-month billing had to be migrated.

For a third-party tvOS app:
- If it never sells/renews/upgrades a membership in-app (only lets already-
  paying patrons view content), Apple IAP is not triggered.
- If it lets users pledge / upgrade tier / one-time-purchase via a redirect
  to patreon.com in a WebView, Apple's "reader-app" rules (App Store
  Guideline 3.1.3(a)) *may* permit this — but Apple has been aggressive
  about payment-flow steering. Precedents: Netflix, Kindle. This is an
  App Review risk, not a Patreon-API risk.

### 7.6 NSFW / Adult content policy

Source: `guidelines-clean.txt` (Community Guidelines, `/policy/guidelines`).

- Patreon does host **Adult / 18+** creators (guidelines line 224–260).
- Adult / 18+ works "featuring nudity, sexual activity, or sexually explicit
  imagery and themes must reside behind a Patreon subscription paywall, and
  may only be accessible by the creator's paying members." (line 243)
- Public-facing spaces (profile image, banner, free-tier posts) must be
  SFW (line 243).
- Only **AI-generated or illustrated / animated** Adult content is
  permitted; hyperrealistic AI porn and deepfakes are banned.
- Real-person sexual activity is prohibited (line 259).
- Users must be 18+ to subscribe to Adult creators (line 125).

Public API exposes `is_nsfw` on Campaign (`docs-main.md` line 2210):
> "true if the creator has marked the campaign as containing nsfw content."

**But there is no per-post NSFW flag** in Post v2. So a third-party client
that wants to hide NSFW from minors can only do it at the campaign level.

**Apple's implications**:
- If our app shows Adult creators to signed-in adults, Apple requires 17+
  age rating and clear NSFW content warnings.
- Reviewer discretion is significant. Historical: Patreon's own iOS app
  gates or blurs adult content.
- Simplest path for App Store approval: **exclude NSFW campaigns entirely**
  (filter by `is_nsfw == false`).

**Confidence: HIGH** on the guidelines quotes; **MEDIUM** on Apple review
consequences (inferred from Apple policy, not tested).

### 7.7 Caching / redistribution

ToU has no explicit "you may not cache API responses" clause. Standard
industry norms apply. The 24-hour and 2-week TTLs on `Media.download_url`
and `image_urls` (docs lines 2611, 2623) mean any caching layer must
**re-fetch before the TTL** and cannot durably store media URLs.

**Confidence: MEDIUM.**

---

## 8. Rate limits in practice + webhook reliability

### 8.1 Documented (repeat from §1.7)

- Client: 100 req / 2s.
- Access token: 100 req / min.
- Edge: 30-min block after >2000 4xx in 10 min.

### 8.2 Announced 2024-10 (topic 9459, @codebard)

> "To secure and protect the public API and improve its stability, we will be
> rolling out rate limiting around a month or so. The limits are designed to
> ensure the smooth operation of all existing integrations, and the logs
> show that this should not affect any integration but a handful."

So rate limits are recent (Nov 2024 rollout). Historical apps didn't hit them.
There are **no forum reports of hitting the per-token 100/min limit for
normal fan-side apps**. The edge 30-min ban shows up in Cloudflare-related
threads only.

### 8.3 Cloudflare interference (major and recurring)

Multiple threads: 2019 (topic 2213, 2025), 2020 (topic 1349-related),
2024-07 (topic 8990), 2026-04 (topic 11316), 2026-04–05 (topic 11337).

Pattern: Patreon puts everything behind Cloudflare, and periodically
adjusts rules. Legitimate API traffic gets 403 responses with an HTML
Cloudflare challenge body.

- 2020-01-14, Patreon Security Lead @Jackie_Bow (topic 2213):
  > "we moved to challenge (serve Captcha) to requests that do not include
  > a user agent. This is because historically, there have been a large
  > number of badware or malware that omits user agents. Adding a proper
  > user agent will circumvent this."
- 2024-07 and 2026-04 recurrences suggest new rules occasionally over-block
  the OAuth-authenticated `/api/oauth2/v2/…` endpoints from server IPs
  (particularly VPS providers, Python `requests` default UA, etc.).
- 2026-04-22, staff @noertap (topic 11316):
  > "Can you please DM me a ray-id? … a fix should be out. Lmk if you are
  > still seeing this."
- Community workaround: `curl-cffi` (browser-impersonating TLS) fingerprinting
  library (topic 11337, @kamejosh, 2026-05-13):
  > "so i switched to curl-cffi for my http client, which is no longer
  > getting blocked by cloudflare."

**Implication for our app**: server-side integration must set a real UA,
possibly use JA3-fingerprint-friendly clients, and monitor for CF 403s.
Client-side (native iOS/tvOS URLSession with default UA) is *usually*
allowed.

### 8.4 Webhook reliability

- Docs (lines 1789–1838) describe the payload format and signature (MD5 HMAC).
- @codebard, 2025-01-07 (topic 9535): "If a webhook can't get a 200 response
  from your side, it backs off and retries later. If your app/site keeps
  giving non-200 responses to consecutive retries, the webhooks can wait up
  to a week to get retried."
- Topic 11231 (2026-01-23): "Webhook has been broken since 12 december. Can't
  receive any events." Un-answered by staff as of the fetch date. Suggests
  webhook delivery is not bulletproof.
- Topic 9535 (2024-11): late "declined_patron" webhooks days after the fact
  — not fully explained by staff.
- Topic 8259 (2023-10): `currently_entitled_tiers` missing from PayPal-
  triggered `members:pledge:create` payloads.

**Common design pattern (topic 8646, @ParoX 2024-03-03, confirmed by
@codebard 2024-10-18):**
> "Ideally you would use webhooks, but also supplement it with a cron that
> regularly syncs your campaign members to your app so that you can check
> for their entitlements."

For our fan-side use case, this maps to: **poll `/identity` and
`/identity?include=memberships` regularly**; do not trust that any
webhook has fired.

**Confidence: HIGH** on the pattern; MEDIUM on the specific reliability
numbers.

---

## 9. Historical context and risk profile (2–3 year outlook)

### 9.1 Signals of API neglect

- **Client library commit history** (from `github.com/patreon/*` via GitHub API):

  | Lib | Last real commit | Recent activity |
  |---|---|---|
  | patreon-python | **2019-01-17** | none |
  | patreon-php | **2021-07-13** | none since |
  | patreon-js | **2018-07-10** | Mar 2026: PR adding "API v1 deprecation notice" only |
  | patreon-ruby | **2019-01-16** | same |
  | patreon-java | **2018-11-01** (with a 2024 readme tweak) | Mar 2026: same |
  | patreon-wordpress | ongoing | Active (weekly releases from Jekabs) |

  The March 2026 "Add API v1 deprecation notice to README" PRs on JS/Ruby/
  Java (by user `Jekabs`) are the only sign of Patreon touching these
  libs in 5+ years.

- **Docs preamble** (docs-main.md lines 484–491): "we will have limited
  capacity in the near term to respond to questions through the developer
  forum." Same message on `/portal/oauth` and `/portal/register` pages
  (`portal-oauth.txt`, `portal-register.txt`): "Our team is focused on
  developing our core product at this time."

- **Staff departures**: @DisappointedDev, topic 8867, 2024-05-28:
  > "I have just viewed the official libraries for the Patreon API. The JS,
  > Python, and Ruby libraries haven't been touched in 6 years. The Java
  > library seems to have been officially abandoned, and the PHP library
  > has similar levels of inactivity… @phildini, maintainer of many of
  > these libraries, no longer works at Patreon."
  @codebard (2024-05-30) confirmed: "Libraries other than PHP are not
  maintained at the moment."

- **Staff forum presence has dwindled**. In 2018–2019, active staff on the
  forum: `@tal`, `@telaviv`, `@drk`, `@phildini`, `@nsethi`, `@buster`,
  `@Jen_Yee`. In 2025–2026 the only visible admin/staff replies come from
  `@noertap` (rare, mostly acknowledgements of Cloudflare / bug reports).

### 9.2 Signals the API is not going away

- API v2 still functions; endpoints have not been removed.
- 2022-11-18 shipped a small enhancement: `tiers` field on Post v2 (topic 6491).
- 2025-2026 changelog (docs-main.md lines 420–441):
  - `2026-05-26` Member identity masking
  - `2026-03-25` V1 Client Creation Restriction
  - `2026-03-11` Live Resources and Endpoints
  - `2026-03-09` Name and Currency Added to Campaign Resource
  - `2025-07-04` Edge Rate Limiting
  - `2024-10-14` Rate Limits Updated
- These are all **small, mostly-defensive** changes: privacy hardening,
  security hardening (rate limits, edge rules), one new producer-side
  feature (Lives). Nothing new for consumer / fan apps.
- V1 will be deprecated but there's no fixed sunset date in the docs.

### 9.3 Risk profile for a 2–3 year build

**Rug-pull risk** (a documented endpoint disappears): **LOW** for OAuth v2
identity/campaigns/members/posts. Patreon has kept these stable for 7+ years
even after they cut staff.

**Feature-parity risk** (new products in Patreon UI don't get API surface):
**HIGH**. Video posts, Shop, Chats, Communities, Drops — none of these have
first-class API representation. If we build around what's public today,
Patreon will keep adding new content surfaces that we can't reach.

**Cloudflare / edge risk**: **MEDIUM**. Recurring flareups (Jan 2020, Jul
2024, Apr 2026); each was eventually patched within days once escalated by
partners. Would break our production once every 6–18 months.

**Internal-API risk** (if we go the kochj23 route): **HIGH**. Staff have
explicitly told hobbyists not to; endpoints change without notice; user IPs
can get blocked by CF; violates spirit if not letter of ToU.

**Apple-App-Store risk**: **MEDIUM–HIGH**. IAP mandate for Patreon's own app
suggests Apple watches this space. Reader-app rules are our friend, but not
guaranteed. NSFW filtering will be required.

**Confidence: HIGH** on the observations; MEDIUM on the forward-looking
risk ratings.

---

## 10. Existing third-party clients (evidence of what's possible)

### 10.1 kochj23/PatreonTV (Swift, MIT, tvOS 17+ / macOS 14+, v3.0.0 2026-05)

Already covered in §2.6. Key facts:
- **Split architecture**: Apple TV app + macOS relay app. The relay is the
  cheat code — it can run a `WKWebView`, hold cookies, run yt-dlp, and
  proxy media chunks.
- **No public-API dependency**. Everything goes through the internal web
  API with session cookies.
- **No IAP handling** (users must already have Patreon memberships; the app
  only plays what they can already see on patreon.com).
- **Zero external Swift package dependencies** (all native frameworks).
- Includes a Top Shelf extension. Includes Continue Watching. Includes
  QR-code pairing for the tvOS↔macOS handshake.
- Explicit disclaimer: "This is an unofficial app and is not affiliated
  with or endorsed by Patreon."

**Confidence: HIGH** — code inspected.

### 10.2 shizukusoft/PatronArchiver (Swift, MPL-2.0, macOS 15.6+ / iOS 18.6+)

- Ships in the **App Store** (asserted by README: `apps.apple.com/app/id6760197229`;
  direct fetch of App Store page returned 404 from this host — flag for
  confirmation).
- Archives posts from Patreon, pixivFANBOX, SubscribeStar to MHTML + PDF +
  media files.
- Uses an "embedded `WKWebView` to access creator platform websites; cookies
  set during sign-in are stored locally within that web view and are sent
  only to their originating sites."
- **Precedent** that an App Store app can log into Patreon via WKWebView
  and consume patreon.com content on a fan's behalf.
- Not fan-viewer; archiver.

**Confidence: MEDIUM** (README verified; App Store presence not
independently confirmed by this research pass).

### 10.3 amirsaam/PatreonAPI-Swift (Swift, 2024-07)

- Wraps the **public** OAuth v2 API. `getUserIdentity`, `getUserOwnedCampaigns`,
  `getDataForCampaign`, `getMembersForCampaign`, `getMemberForCampaignByID`.
- Explicitly notes "Patreon doesn't support App URL Scheme" — the OAuth
  redirect must go to a web URL first.
- Not fan-facing.

### 10.4 fotiDim/Patreon-iOS-SDK (Swift, 2018-03)

- Old, unmaintained. Says "The SDK does not handle authentication. You are
  responsible of authenticating the user."

### 10.5 miniBill/secretdemoclub (Elm + Rust, active 2026-05)

- **Reverse-engineered OpenAPI 3.1 spec** for `https://www.patreon.com/api`
  (the internal one).
- Cron job to fetch feed + RSS generator.
- Author's forum quote (topic 11355, 2026-05-27):
  > "I've given up on the official API and I'm just [using] the API the
  > website uses with my own credentials."

**Confidence: HIGH** (repo inspected).

### 10.6 Patreon official GitHub org

- 62 public repos. Only `patreon-wordpress` is actively developed
  (weekly commits in 2026 by @Jekabs).
- Most other repos are dormant vendored dependencies or archived
  experiments.

---

## 11. Miscellaneous forum-verified reliability & UX gotchas

Aggregated from the threads I dumped:

- **Post fields must be requested explicitly** or you get empty attributes
  (topic 5785, 3006).
- **Sorting on `/posts` may not be honored** (topic 4340).
- **Free-member webhook payloads omit `currently_entitled_tiers`** (topic 8259).
- **PayPal-flow `members:pledge:create` differs from card-flow** (topic 8259).
- **Gifted subscriptions have no expiry field** — `next_charge_date` is null,
  `pledge_cadence` null (topic 9808).
- **`currently_entitled_amount_cents` returns 0 for gifted patrons** (bug per
  @codebard, topic 9808).
- **`/identity` with `include=memberships.pledge_history` can 504** for users
  with long histories (topic 11362, un-fixed as of 2026-06-09).
- **`/identity` occasionally misses paid patrons** (topic 11318, un-fixed as
  of 2026-05-11).
- **User `about` field became always-null since 2023-07** (topic 7811, never
  fixed).
- **`is_follower` deprecated** (docs-main.md line 2730) — "This will always
  be false, following has been replaced by free membership."
- **OTP (one-time purchases) not in API**; only `is_gifted` on Member
  indicates gifts (topic 11371, @noertap 2026-06-19).
- **Comments, likes, tags, polls, attachments, featured images, native
  video URLs, native audio URLs — all missing from Post v2.**

**Confidence: HIGH** (all quoted directly).

---

## 12. Open questions that only live API testing can answer

This is what should be tried with real credentials before committing to an
architecture.

### 12.1 Public API v2

1. **What does `embed_data` actually contain for each of the following?**
   - YouTube-embed post (paste a YT URL into a video post)
   - Vimeo-embed post
   - Patreon-native uploaded video post
   - Native audio post
   - Native image post
   - Text post with an inline `<video>` tag in body
   - Text post with an `<iframe>` embed in body
2. **For each of the above, does `/posts/{id}?include=<foo>` accept any
   include that yields a `media`, `attachments`, or media-adjacent
   relationship?** Try:
   - `include=campaign,user` (documented)
   - `include=media`, `include=attachments`, `include=attachments_media`,
     `include=post_file`, `include=audio`, `include=video`, `include=images`
     (all expected to fail with `ParameterInvalidOnType`, but verify —
     Patreon has been known to quietly add includes)
3. **What happens when you request a post from a campaign you're a member
   of but do NOT own with `campaigns.posts` scope?** Is the entire endpoint
   scoped to campaigns you own, or does it work as long as you can see the
   post on the website? Test with a patron-only token.
4. **Do `/campaigns/{id}/posts` and `/posts/{id}` respect `is_public` /
   `tiers` when called by a fan token?** i.e., can a patron actually list
   the posts they have access to via the public API, or only public posts?
   (Docs say `campaigns.posts` scope — but that scope description says
   "posts on a campaign", which suggests creator-owned.)
5. **What does `Live.stream_key` / `rtmp_url` look like on the consumer side?**
   Or is `GET /lives/{id}` also creator-only? Test as a member.
6. **What are the observable rate-limit headers?** Is there an
   `X-RateLimit-Remaining`? Or only `retry_after_seconds` on 429?
7. **How does refresh-token rotation behave?** Docs say access tokens
   expire; test the refresh cadence and whether refresh_token itself
   rotates.
8. **Can you register a client with just `identity` and `identity.memberships`
   scopes and use it as a fan-only reader token?** i.e., can we ship a client
   whose OAuth request never asks for `campaigns`?
9. **Confirm that a `https://` universal-link `redirect_uri` claimed by an
   iOS app entitlements works** end-to-end. Some 2022–2023 reports suggest
   it does; some suggest issues with Firebase dynamic links.
10. **Does `is_nsfw` on Campaign actually work reliably?** Any way to know
    per-post that content is NSFW (given no per-post flag)?

### 12.2 RSS

11. **What is the exact URL format** of a per-patron RSS feed? Is the token
    a session ID or a per-feed opaque token? What's the rotation policy?
12. **Is the RSS feed's `<enclosure url="">` an MP3 CDN URL with a token
    embedded, or a redirect through patreon.com?**
13. **Are there any video enclosures**, or is RSS strictly audio-only?
14. **How does an unsubscribed fan getting cut off** manifest — 401 on the
    feed URL, or the feed just stops updating?

### 12.3 Internal API (only if we're willing to go that route)

15. **Session cookie lifetime** for `session_id`? Renewal mechanism?
16. **Are the `Media` includes reliable across all post types** (as
    miniBill's OpenAPI + kochj23's Swift assume)?
17. **Is there a 2FA / captcha challenge triggered** for WKWebView login
    programmatically?
18. **What's the actual signed CDN URL structure** for Patreon-hosted video
    and how long is it valid after the internal API returns it? Is it
    tied to a specific cookie / IP?
19. **What throttling does the internal API impose** if a single account
    fetches feeds aggressively (e.g., every 15 min)?
20. **What does Patreon's Cloudflare do to residential IPs vs. datacenter
    IPs** — does an Apple TV on home Wi-Fi get less scrutiny than a VPS?

### 12.4 App-Store / product

21. **Does Apple accept a "reader" style tvOS app** that never sells
    membership in-app but plays paid Patreon content the user already has?
    Best proxy: watch PatronArchiver's App Store lifecycle.
22. **How does Apple treat NSFW gates** on Patreon-Adult content? Blur?
    17+ rating? Reject?
23. **Does IAP have to be offered** if the app has an "Upgrade tier" button
    that deep-links to patreon.com? (Reader-app rules say no; App Review
    varies.)

---

## 13. Sources (all files in /tmp/patreon-research/, fetched 2026-07-06)

- Official docs snapshot: `/tmp/patreon-docs/docs-main.md`
  (5075 lines; source: `https://docs.patreon.com/`)
- Official portal pages: `/tmp/patreon-docs/portal-oauth.txt`,
  `portal-register.txt` (both note "Our team is focused on developing our
  core product at this time. Endpoints will continue to function as
  normal.")
- Forum: `https://www.patreondevelopers.com/` (Discourse install).
  Fetched via `.json` API endpoints — see `forum-latest.json`,
  `forum-categories.json`, `topic-*.json`, `search-*.json`. Human-readable
  dump: `threads-dump.txt`.
- ToS: `https://www.patreon.com/policy/legal` → `legal-clean.txt`
  (Last Updated: 2026-05-27).
- Community Guidelines: `https://www.patreon.com/policy/guidelines` →
  `guidelines-clean.txt`.
- App Directory listing: `https://www.patreon.com/apps` →
  `legal-www.patreon.com_apps.html`.
- Patreon GitHub org listing: `gh-patreon-org.json`
  (`https://api.github.com/orgs/patreon/repos?per_page=100`).
- Recent commits on `patreon-{python,php,js,ruby,java,wordpress}`: inline
  in this session.
- Reverse-engineered internal API spec: `sdc-openapi.yaml` and `sdc-main.elm`
  (from `github.com/miniBill/secretdemoclub`).
- Swift tvOS+macOS reference implementation:
  `ghreadme-kochj23_PatreonTV.md`, `tmp-PatreonAPI.swift` (source
  `github.com/kochj23/PatreonTV`, main branch, MIT, v3.0.0).
- Swift SDKs / archivers:
  `ghreadme-shizukusoft_PatronArchiver.md`, `ghreadme-amirsaam_PatreonAPI-Swift.md`,
  `ghreadme-fotiDim_Patreon-iOS-SDK.md`.
- Media proxy implementation: `ptv-mediaproxy.swift`.
- Blog / news: `https://blog.patreon.com/introducing-the-patreon-app-directory`
  and `.../tag/developer` — both returned generic news-index HTML with **no
  post content matching the requested topic**. No blog post about the App
  Directory was found in this pass; the introductory blog post at
  `/introducing-the-patreon-app-directory` did not have retrievable body
  content (returns the news home page, likely a redirect).
- **Could not resolve** `help.patreon.com` from this workspace (DNS
  restriction). The help articles about RSS feeds and app-directory
  submission were therefore **not fetched**. Flag as follow-up.
- **Could not confirm** shizukusoft/PatronArchiver's App Store listing —
  the direct `apps.apple.com/app/id6760197229` and JP-region URL returned
  404 to this UA. README asserts the app is available; treat as
  MEDIUM confidence until re-checked from a browser.

---

*End of report.*

---

# §14. Live API test results (2026-07-06)

Test account: user id `8462900`, vanity `Subarashii`, owns campaign
`1335234` "Cheshire" (0 patrons, unpublished).

**Active paying memberships** (from `/identity?include=memberships`):
- Cold Ones (campaign `2211846`) — 500 cents/mo, last_charge=Paid, tier `Level 2`
- Reckless Ben (campaign `4270549`) — 1000 cents/mo, last_charge=Paid

Client token had **all documented scopes plus several undocumented ones**:
`identity, identity[email], identity.memberships, campaigns, campaigns.posts,
campaigns.members, campaigns.members[email], campaigns.members.address,
campaigns.lives, campaigns.webhook, apps.tiers, w:campaigns.posts,
w:campaigns.lives, w:campaigns.webhook, w:campaigns.apps, w:campaigns.benefits,
w:identity.clients`. (The undocumented scopes are Creator-Access-Token defaults.)

Redacted JSON dumps saved under `/tmp/patreon-testing/samples/`.

## §14.1 Public v2 API confirmations

### The `/posts/{id}` endpoint returns 403 for paid content on campaigns you're a patron of

**Confidence: HIGH (empirically confirmed)**

```
GET /api/oauth2/v2/posts/162743341 (Reckless Ben, I'm a paying patron)
  → HTTP 403 ViewForbidden
     "You do not have permission to view post with id 162743341."

GET /api/oauth2/v2/posts/162840446 (Cold Ones, I'm a paying patron)
  → HTTP 403 ViewForbidden (same)
```

Neither the `campaigns.posts` scope nor the `identity.memberships` scope
grants a fan the right to read individual posts on campaigns they're a
member of via the public API. Confirmed with a token that has all documented
scopes.

### `/campaigns/{id}/posts` silently returns empty for campaigns you're a patron of but don't own

**Confidence: HIGH**

```
GET /api/oauth2/v2/campaigns/2211846/posts  → HTTP 200, {"data":[], "total":0}
GET /api/oauth2/v2/campaigns/4270549/posts  → HTTP 200, {"data":[], "total":0}
```

Not 403, not error — just empty. Meaning the endpoint is scoped to **posts
you own as a campaign administrator**, not posts you have entitlement to view.
Docs description "Provides read access to the posts on a campaign" is
literally correct but misleading.

### The Post v2 resource accepts only 2 includes

**Confidence: HIGH — exhaustively tested**

```
include=campaign        → 200 (or 403 if not viewable)
include=user            → 200 (or 403)
include=media           → 400 ParameterInvalidOnType
include=attachments     → 400
include=attachments_media→ 400
include=post_file       → 400
include=audio           → 400
include=video           → 400
include=images          → 400
include=access_rules    → 400
include=content_unlock_options → 400
include=poll            → 400
include=tiers           → 400
```

No hidden includes reveal media, attachments, or entitled tiers on the public
v2 endpoint. This confirms the FINDINGS §1.3 conclusion.

### Refresh-token flow rotates BOTH access_token and refresh_token

**Confidence: HIGH**

```
POST /api/oauth2/token grant_type=refresh_token
  → HTTP 200
     access_token: NEW (was xMa-...I; now DumjH...o)
     refresh_token: NEW (was _D5b-...U; now d4sES...k)
     expires_in: 2678400  # 31 days
     token_type: Bearer
     scope: <space-delimited full scope list>
```

**Design implication**: our app must persist both `access_token` and
`refresh_token` from every token response, not just access. The 31-day
expiry means fresh installs need refresh long before daily use would
normally trigger one — plan for refresh on any 401.

### Rate-limit headers are NOT exposed

**Confidence: HIGH**

Full response headers on `/identity`:

```
HTTP/2 200
date: Mon, 06 Jul 2026 03:42:49 GMT
content-type: application/vnd.api+json
cf-ray: a16b9a052bf3cb99-STL
cf-cache-status: DYNAMIC
cache-control: private
server: cloudflare
x-patreon-uuid: ebead223-808a-43b6-b4a8-595b9a408dbc
x-envoy-upstream-service-time: 68
x-patreon-sha: af5454543bd6270a3c40599fec906ee053276c69
strict-transport-security: max-age=2592000
```

No `X-RateLimit-Remaining`, no `X-RateLimit-Limit`, no `Retry-After` header
on successful responses. You only get `retry_after_seconds` in a **429 body**
per the docs. This means the client must:
- Guess-and-retry with exponential backoff
- Not attempt any header-driven pre-throttling
- Include `x-patreon-uuid` in error reports (it's per-request; useful for
  Patreon staff to trace)

### Cloudflare cookies are set on API responses

Every response sets `__cf_bm` (Cloudflare bot management), `patreon_device_id`,
and `a_csrf`. Native URLSession clients will accept these into cookie jars
by default. Not a problem for tvOS (cookie jar is per-app-per-domain), but
worth knowing.

## §14.2 Identity + memberships works cleanly

**Confidence: HIGH — this is the golden path for our app**

`/identity?include=memberships,memberships.campaign,memberships.currently_entitled_tiers`
with rich fields returns:
- User attributes (`full_name`, `email` (with scope), `image_url`,
  `thumb_url`, `url`, `vanity`, `created`, `is_email_verified`)
- 21 `member` records (subset per campaign: patron_status, entitled amount,
  last_charge_status/date, lifetime_support_cents, is_gifted, is_free_trial,
  pledge_relationship_start, next_charge_date, will_pay_amount_cents)
- 21 `campaign` records (name, vanity, url, is_nsfw, creation_name,
  summary (with scope), patron_count, image_url, image_small_url, has_rss,
  rss_feed_title, rss_artwork_url, main_video_url, main_video_embed)
- 6 `tier` records (title, amount_cents, description)

**Every campaign avatar/image URL uses the signed `c10.patreonusercontent.com`
CDN pattern** with `token-hash=` and `token-time=` query params:
```
https://c10.patreonusercontent.com/4/patreon-media/p/campaign/4270549/
  bc4e5c9777d1402bbfee1cde9eb4272d/eyJ3Ijo2MjB9/4.png
  ?token-hash=<b64>&token-time=<unix>
```
The `token-time` embedded in the URL is a **unix timestamp for expiry**
(observed values were ~2 weeks out). Clients must not persist these
URLs beyond expiry.

**User's own profile image** (`data.attributes.image_url`) uses the same
`c10.patreonusercontent.com` pattern; not `c8.patreon.com` as the older
docs samples suggested. Docs sample data is stale.

**Free memberships are surfaced** alongside paid ones — 21 memberships for
2 paid + many free follow-only. The client needs to filter on
`currently_entitled_amount_cents > 0` if we want to hide free follows.

## §14.3 Internal `/api/*` endpoint — critical findings

**Confidence: HIGH — direct evidence.**

### The internal API accepts OAuth Bearer tokens

Base URL: `https://www.patreon.com/api` (not `/api/oauth2/v2`).
This is the **same OAuth Bearer token** used for the public v2 API — no
separate credential needed. Sending the Bearer worked on every internal
endpoint tested.

### It also accepts NO auth for public content

Both authenticated and unauthenticated requests returned **identical
responses** for a publicly-viewable post. This means:
- The internal API has a public-facing surface
- Anyone on the internet can retrieve rich metadata for public posts

### Post v2 (internal) accepts many more includes than public v2

Working includes on `/api/posts/{id}`:
- `campaign` ✓
- `user` ✓
- `media` ✓ (returns full Media object with `display`, `mimetype`, etc.)
- `video` ✓ (single Media)
- `audio` ✓ (single Media or null)
- `images` ✓ (list of Media)
- `attachments_media` ✓ (list of Media)
- `post_file` — appears in **response attributes**, not as an include

Post attributes available include: `title`, `content` (HTML), `teaser`,
`post_type`, `post_file` (object, includes `url`), `url`, `video_preview`,
**`current_user_can_view`** (critical boolean), `thumbnail`, `image`,
`meta_image_url`.

### Post types observed

| post_type | Notes |
|---|---|
| `video_external_file` | Native Patreon video upload (Mux-hosted) |
| `text_only` | Text posts |
| `image_file` | Image posts |
| `link` | External link posts (embed_url set) |

Others per the reverse-engineered spec (not seen live yet): `podcast`,
`livestream_youtube`, `video_embed`, `poll`, `livestream_crowdcast`,
`audio_embed`, `audio_file`.

### For a viewable video post, `Media.display.url` is a signed Mux HLS manifest

**Confidence: HIGH — playback URL captured empirically.**

For public post `86262355` (Reckless Ben, "Mckamey Manor Repload"):

```json
{
  "type": "media",
  "id": "216581623",
  "attributes": {
    "mimetype": "application/x-mpegURL",
    "state": "ready",
    "download_url": "https://c10.patreonusercontent.com/4/patreon-media/p/post/86262355/.../1?token-hash=<REDACTED>&token-time=1783468800",
    "display": {
      "duration": 1653.8522,
      "full_content_duration": 1653.8522,
      "url": "https://stream.mux.com/jaLVL2rXj9tyI4c02HyuG1Xtdi024iEAydrMl00n3yWjS8.m3u8?token=<JWT>",
      "viewer_playback_data": {
        "playback_id": "jaLVL2rXj9tyI4c02HyuG1Xtdi024iEAydrMl00n3yWjS8",
        "playback_token": "<JWT>",
        "url": "https://stream.mux.com/...",
        "playback_token_expiry": <unix>
      },
      "expires_at": "2026-07-07T04:00:00.000+00:00",  // ~24h TTL
      "width": 1920, "height": 1080,
      "storyboard": {"vtt_url": "https://image.mux.com/.../storyboard.vtt?token=<JWT>", "json_url": "..."},
      "default_thumbnail": {"url": "https://image.mux.com/.../thumbnail.jpg?token=<JWT>", "position": 3.0},
      "progress": {"is_watched": false, "watch_state": "is_not_watched"},
      "closed_captions_enabled": true,
      "state": "ready"
    }
  }
}
```

**Key facts:**
1. Video is hosted on **Mux.com** (`stream.mux.com`), not Patreon CDN
2. `mimetype: application/x-mpegURL` → **HLS**
3. The manifest URL includes a **signed JWT** (`?token=eyJ...`). JWT payload
   contains `sub` (Mux asset ID), `exp` (expiry unix ts), `aud: "v"` (video)
4. Same asset also exposes `viewer_playback_data.playback_token` — Mux's
   Signed Playback SDK envelope
5. **Storyboard VTT** for AVPlayer seek-preview
6. **Closed captions** flag
7. `download_url` (separate signed URL on `c10.patreonusercontent.com`) —
   presumably direct MP4 download
8. **Both are valid for ~24 hours** (`expires_at`)

This means: **for content the current session is entitled to view, AVPlayer
can play the HLS URL directly.** No proxy, no yt-dlp, no cookie-following
redirect. Just paste the URL into `AVPlayer`.

### But `current_user_can_view` is FALSE for OAuth Bearer tokens on gated content

**Confidence: HIGH — the critical restriction.**

For the two posts the user actually cares about
(`162840446` Cold Ones, `162743341` Reckless Ben) — both are patron-only
video posts, both on campaigns the user is a paying member of:

```
GET /api/posts/162743341?include=media  (with OAuth Bearer)
  → HTTP 200
  → current_user_can_view: FALSE
  → post_file: null
  → content: null
  → teaser: null
  → media.display.url: NOT PRESENT (only metadata: duration, thumbnail, expires_at)
```

**Same call with no auth at all** returned the identical response
(current_user_can_view: false). The OAuth Bearer token from the paying
patron is treated as anonymous/logged-out for entitlement purposes.

The `display.url` (HLS manifest) is **omitted from the response** when
`current_user_can_view` is false. The client cannot construct it — the
Mux JWT is signed server-side.

**Implication**: OAuth-Bearer + internal-API alone is not enough to unlock
paid content. Patreon's entitlement layer requires a **web session cookie**
(`session_id`) — the same one kochj23/PatreonTV extracts via WKWebView.

### `/api/stream` (fan home feed) — Bearer alone returns EMPTY

```
GET /api/stream (with OAuth Bearer)
  → HTTP 200
  → {"data":[], "meta":{"posts_count":0, ...}}
```

Even with `identity.memberships`, the stream endpoint requires session
cookies to return anything. This matches kochj23/PatreonTV's need for a
real logged-in web session.

### `/api/campaigns/{id}/posts` (internal, Bearer) returns only publicly-viewable posts

```
GET /api/campaigns/4270549/posts  → posts_count: 3
  All 3 posts have is_paid=false, current_user_can_view=true

GET /api/campaigns/2211846/posts  → returned 20 posts (page[count]=20)
  All 20 have is_paid=false, current_user_can_view=true
  None are the paid video the user referenced
```

Same behavior as the public v2 endpoint but *without* the "only if you own
it" restriction. Non-owner Bearer tokens can list a campaign's PUBLIC posts.
No paid content leaks.

Note: internal `/api/campaigns/{id}/posts` includes richer per-post metadata:
`likes` relationship (with cursors!), `content_locks`, `attachments`,
`attachments_media`, `user_defined_tags`.

## §14.4 What this means for the Apple TV app architecture

**Confidence: HIGH** — this is the empirical bottom line.

### Path 1 — Pure public v2 API (what the docs promise)

**Verdict: doesn't work for a video client.**

Even a fully-scoped OAuth token cannot read the body, media, or playback
URL of ANY paid post the user is entitled to view. The `/posts/{id}`
endpoint 403s. Only YouTube/Vimeo `embed_url` for public posts would
be reachable, and even then only on campaigns the user administers.

### Path 2 — Public v2 API + user-provided per-creator RSS URL

Works for **audio podcasts only**, and only for creators who both (a) have
enabled RSS and (b) hand the user their personal RSS URL. No video.

### Path 3 — Internal API + OAuth Bearer only

**Verdict: works for public content only.** Every paid post returns
`current_user_can_view: false` and omits `display.url`. Same result as
being anonymous.

Useful for:
- Showing a browse view of what creators the user follows publish publicly
- Playing free preview clips / public videos (Mux HLS directly)
- Showing thumbnails, metadata, duration

Not useful for: unlocking paid content.

### Path 4 — Internal API + browser session cookie (kochj23/PatreonTV pattern)

**Verdict: works. This is the only path that gets a video client to actual
paid content.**

Requires:
- A real logged-in web session (WKWebView + Patreon login)
- Extract `session_id` cookie from the WebView
- Send `Cookie: session_id=...` on every `/api/*` call
- The response will then include `display.url` for content the session's
  patron is entitled to
- AVPlayer plays the Mux HLS URL directly (no proxying needed —
  `stream.mux.com` doesn't require cookies)

**On tvOS specifically:**
- tvOS `WKWebView` is available but the UX is hostile (no keyboard by
  default, requires companion device for text entry)
- kochj23's answer: use a macOS relay app that does the login and hands
  the session_id to the Apple TV over LAN
- Alternative: use a companion iOS app (Continuity keyboard, TV Remote
  app for pairing)
- Alternative: implement Patreon's own device-flow (they don't offer one)

**Explicitly discouraged by staff (topic 11193, @noertap, 2025-12-15):**
"I would advise against any usage — there have been cases when 3rd party
apps suddenly break because of security rules or changes to the non
public APIs."

The internal endpoints DO have a public-facing surface (no auth needed for
public content) but Patreon has no obligation to keep the shape stable.

### Path 5 — Hybrid (recommended for MVP)

Use the **public v2 API + `identity.memberships`** to:
- Authenticate the user via OAuth (server-side flow, universal-link
  redirect_uri, backend to exchange code for tokens)
- List the user's memberships and campaigns (this WORKS reliably)
- Show creator branding, tier information, campaign metadata

Then for the actual video content:
- Use the **internal API `/api/campaigns/{id}/posts`** + **`/api/posts/{id}?include=media`** with the OAuth Bearer to enumerate and play PUBLIC content
- Explain honestly in the app that "paid content access requires signing in through your browser" and open a Safari view for the user to sign in on patreon.com
- Store the resulting session_id and use it for `/api/*` calls thereafter

This is a middle path: uses the documented API for the "safe" 80%, uses the
internal-web API for the "risky but necessary" 20%. Both AVPlayer paths
(HLS direct-play) are the same.

### The Mux hosting is a big architectural win

Because Patreon video runs on Mux and returns a **standard HLS URL with
signed JWT**, AVPlayer on tvOS can play it natively with:
```swift
let asset = AVURLAsset(url: URL(string: displayUrl)!)
let item = AVPlayerItem(asset: asset)
player.replaceCurrentItem(with: item)
```
No proxying, no re-signing, no yt-dlp for Patreon-native video. Just play
the URL directly. This is much better than kochj23's cookie-carrying proxy
approach for their case — probably because they built before Patreon moved
to Mux, or because they didn't realize display.url was directly playable.

**Only YouTube/Vimeo embed posts need yt-dlp or a similar extractor** —
and only if we want to play them in-app rather than deep-linking out.

## §14.5 Post-test cleanup — REQUIRED

The four tokens you pasted are compromised (in chat transcripts). Please:
1. Go to https://www.patreon.com/portal/registration/clients
2. Click your PatreonTV client
3. Hit **Reset** on both the Client Secret and the Creator's Tokens
   (or delete and re-create the client)

The rotated tokens issued during Probe 12 (in `/tmp/patreon-testing/secrets/creds.env`)
are also now stale after this report is shared. Same recommendation.

## §14.6 Answered vs. still-open from §12

Now-answered:
- §12.1 Q3: Fan token gets **empty list** from `/campaigns/{id}/posts`,
  **not 403**. (§14.1)
- §12.1 Q4: Public v2 `/posts/{id}` for patron-only posts returns **403
  ViewForbidden** regardless of `campaigns.posts` scope. (§14.1)
- §12.1 Q2: Only `include=campaign` and `include=user` work on public v2
  Post. All media includes 400. (§14.1)
- §12.1 Q6: **No rate-limit headers** on success responses. Only
  `retry_after_seconds` in 429 body. (§14.1)
- §12.1 Q7: Refresh rotates **both** access and refresh tokens. Access
  token lifetime = 31 days. (§14.1)
- §12.1 Q8: Client with all scopes is what Patreon gives Creator Access
  Tokens by default. Undocumented scopes exist (`apps.tiers`,
  `w:campaigns.apps`, `w:campaigns.benefits`, `w:identity.clients`,
  `w:campaigns.posts`, `campaigns.webhook`). (§14.1)
- §12.1 Q1 (partial): For **native video post + no view permission**,
  `embed_data`/`embed_url` on public v2 are null. For same post on internal
  API, we get full media metadata but no playable URL until
  `current_user_can_view=true`. Still need to verify YouTube-embed and
  Vimeo-embed cases with actual example posts.
- §12.2 Q13 (partial): Patreon video is delivered as **HLS on Mux**, not
  in RSS enclosures. So RSS remains audio-only.

Still open (need more test posts or a session cookie):
- §12.1 Q1: `embed_data` shape for YouTube-embed, Vimeo-embed, audio-embed,
  image-post, text-with-inline-embed cases
- §12.1 Q5: `/lives/{id}` from a fan token
- §12.1 Q9: Universal-link redirect_uri end-to-end
- §12.1 Q10: Per-post NSFW detection
- §12.2 all RSS questions
- §12.3 all internal-API-with-cookie questions (didn't test — no session
  cookie provided)
- §12.4 all App Store / product questions

