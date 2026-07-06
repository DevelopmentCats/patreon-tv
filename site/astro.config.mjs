// astro.config.mjs
//
// Astro + Cloudflare adapter. Static output by default; individual pages
// can opt in to server rendering by exporting `export const prerender = false`.

import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";

export default defineConfig({
  site: "https://patreontv.app",
  output: "static",           // default; server pages opt out per-page
  adapter: cloudflare({
    platformProxy: { enabled: true },
  }),
  compressHTML: true,
  build: {
    inlineStylesheets: "auto",
  },
  server: {
    port: 4321,
  },
});
