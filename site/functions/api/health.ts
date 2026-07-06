// functions/api/health.ts
//
// Simple health endpoint for uptime monitoring. Cloudflare Pages Function.

export const onRequestGet: PagesFunction = async () => {
  return new Response(
    JSON.stringify({
      status: "ok",
      service: "patreon-tv-site",
      time: new Date().toISOString(),
    }),
    {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    },
  );
};
