# Live API test samples (redacted)

Captured 2026-07-06 by the research subagent. 35 JSON files, one per HTTP
probe. All Mux JWT tokens, patreonusercontent.com CDN token-hash/token-time
query params, and user email addresses have been replaced with `<JWT_REDACTED>`,
`<REDACTED>`, and `<email_redacted>` respectively.

See §14 of `/tmp/patreon-research/FINDINGS.md` for the analysis. Probe number
maps to §14 subsection; e.g. `24-free-video-authed.json` corresponds to
Probe 24 in §14.3 (publicly-viewable video post, authenticated).

Files worth reading first:
- `02-identity-full-body.json` — full memberships + campaigns + tiers shape
- `24-free-video-authed.json` — the golden case: real Mux HLS URL for
  a publicly-viewable video (URLs redacted but structure preserved)
- `18-auth-full.json` — same call for a PAID video: `current_user_can_view: false`,
  no `display.url`
- `17-internal-full.json` — internal API richness (works without auth for public)
- `11-inc-*.json` — the 12 include-parameter tests on public v2 (11 of 12 → 400)
- `12-refresh.json` — refresh flow response (both tokens rotate; scope list)

Raw unredacted versions live in /tmp/patreon-testing/raw/ (not copied here);
tokens/creds live in /tmp/patreon-testing/secrets/creds.env (mode 600, not
copied here).
