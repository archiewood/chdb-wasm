#!/usr/bin/env bash
# Assemble the Vercel static deploy from the chdb-wasm engine + web/.
#
#   build-vercel.sh [dist-dir] [web-dir] [out-dir]     (defaults shown below)
#
# Vercel runs the install step first (installs `chdb-wasm` from package.json deps), then
# runs this as the buildCommand. EVERYTHING — including the two ~100 MB .wasm — is emitted
# as static assets under <out>/ and served straight from Vercel's CDN. Vercel has no
# per-file size limit (unlike Cloudflare Pages' 25 MB), so there is no R2 bucket and no
# streaming Function: the wasm is just a same-origin static file, which also satisfies the
# COOP/COEP cross-origin isolation the multi-threaded build needs.
#
# The engine dir is content-hashed (dist-<hash>/) so it can be cached immutably: a new
# engine build => new hash => new URL => fresh fetch, with no stale-cache risk. The COOP/COEP
# and Cache-Control headers live in vercel.json.
set -euo pipefail

DIST="${1:-node_modules/chdb-wasm/dist}"
WEB="${2:-web}"
OUT="${3:-out}"
JS="index.js worker.js async.js bindings.js protocol.js status.js platform.js"

# Content-hashed dir name covering every engine file (glue + both wasm), so any engine
# change busts the immutable cache. 16 hex chars (64 bits) keep collisions negligible.
HASH_INPUT=""
for f in $JS chdb.mjs st/chdb.mjs chdb.wasm st/chdb.wasm; do HASH_INPUT="$HASH_INPUT $DIST/$f"; done
VER="dist-$(cat $HASH_INPUT | md5sum | cut -c1-16)"

rm -rf "$OUT"
mkdir -p "$OUT/$VER/st"
for f in $JS; do cp "$DIST/$f" "$OUT/$VER/$f"; done
cp "$DIST/chdb.mjs"     "$OUT/$VER/chdb.mjs"
cp "$DIST/chdb.wasm"    "$OUT/$VER/chdb.wasm"
cp "$DIST/st/chdb.mjs"  "$OUT/$VER/st/chdb.mjs"
cp "$DIST/st/chdb.wasm" "$OUT/$VER/st/chdb.wasm"

# Point the page at the hashed engine dir (source keeps ./dist).
sed "s#\./dist#./$VER#g" "$WEB/index.html" > "$OUT/index.html"

echo "Built $OUT/ (engine dir: $VER)" >&2
echo "$VER"
