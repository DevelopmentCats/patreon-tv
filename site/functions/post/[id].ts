// functions/post/[id].ts
//
// Deep-link fallback for shared patreontv://post/<id> URLs.

import { renderShareFallback } from "../_lib/renderShareFallback";

export const onRequestGet: PagesFunction = async ({ params, request }) => {
  const raw = String(params.id ?? "");
  if (!/^\d+$/.test(raw)) {
    return Response.redirect(new URL("/", request.url).toString(), 302);
  }

  const html = renderShareFallback({
    kind: "post",
    title: "Open this post",
    subtitle:
      "If PatreonTV is installed on your Apple TV, tap Open. Otherwise you can view this post on patreon.com.",
    primaryLabel: "Open in PatreonTV",
    primaryHref: `patreontv://post/${raw}`,
    secondaryLabel: "View on Patreon",
    secondaryHref: `https://www.patreon.com/posts/${raw}`,
  });

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
    },
  });
};
