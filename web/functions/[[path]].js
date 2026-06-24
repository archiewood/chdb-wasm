// Pages Function: serve *.wasm from the R2 bucket (binding: WASM_BUCKET); everything
// else falls through to the static Pages assets. Same-origin, so cross-origin
// isolation (COEP) is satisfied. The ~95 MB wasm exceeds the Pages 25 MB/file limit,
// so it lives in R2 rather than in the Pages deployment.
//
// The wasm URL is content-hashed and immutable, so the response is cached in the
// Cloudflare edge cache (caches.default): the first request per edge location reads
// R2, the rest are served from cache without touching R2 — so R2 read ops stay tiny
// regardless of traffic. A new build => new hash => new URL => a fresh fetch, so there
// is no stale-cache risk. (Locally via serve.mjs this Function is never invoked; under
// `wrangler pages dev` caches.default is a no-op, so both still work.)
export async function onRequest(context) {
  const { request, env, next, waitUntil } = context;
  const url = new URL(request.url);
  if (!url.pathname.endsWith(".wasm")) return next();

  const cache = caches.default;
  const cacheKey = new Request(url.toString(), { method: "GET" });

  // 1) Serve from the edge cache if present (no R2 read).
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  // 2) Miss: read the object from R2.
  const key = url.pathname.replace(/^\/+/, "");          // e.g. "dist-XXXX/chdb.wasm"
  const obj = await env.WASM_BUCKET.get(key);
  if (!obj) return new Response("Not found: " + key, { status: 404 });

  const res = new Response(obj.body, {
    headers: {
      "Content-Type": "application/wasm",
      "Cache-Control": "public, max-age=31536000, immutable",
    },
  });

  // 3) Populate the edge cache after responding (body reads once, so clone).
  waitUntil(cache.put(cacheKey, res.clone()));
  return res;
}
