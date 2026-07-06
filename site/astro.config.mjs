// astro.config.mjs
//
// Fully-static output. Dynamic endpoints live in `functions/` (Cloudflare
// Pages Functions) instead of Astro server routes. Removes the Astro
// Cloudflare adapter, which was tripping over reserved binding names in
// its auto-generated wrangler.json.

import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://patreontv.app",
  output: "static",
  compressHTML: true,
  build: {
    inlineStylesheets: "auto",
  },
  server: {
    port: 4321,
  },
});
