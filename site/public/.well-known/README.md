# apple-app-site-association

This file enables **Universal Links** on iOS/tvOS — tapping a
`https://patreontv.app/post/12345` URL opens the app directly instead of
falling through to the web page.

## Before it works

1. Replace `TEAMID` with your real Apple Developer Team ID.
2. Enable the Associated Domains capability on the tvOS target in Xcode
   with entry `applinks:patreontv.app`.
3. Ship the app to TestFlight/App Store.
4. Cloudflare Pages must serve this file with `content-type:
   application/json` and NO extension in the URL. See
   `functions/_middleware.ts` if we later need to force the content type.

Apple's docs on the format:
https://developer.apple.com/documentation/xcode/supporting-associated-domains
