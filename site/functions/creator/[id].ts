// functions/creator/[id].ts

import { renderShareFallback } from "../_lib/renderShareFallback";

export const onRequestGet: PagesFunction = async ({ params, request }) => {
  const raw = String(params.id ?? "");
  if (!/^\d+$/.test(raw)) {
    return Response.redirect(new URL("/", request.url).toString(), 302);
  }

  const html = renderShareFallback({
    kind: "creator",
    title: "Open creator",
    subtitle:
      "Tap below to jump straight to this creator in PatreonTV on your Apple TV.",
    primaryLabel: "Open in PatreonTV",
    primaryHref: `patreontv://creator/${raw}`,
    secondaryLabel: "Get PatreonTV",
    secondaryHref: "/",
  });

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
    },
  });
};
