#!/bin/sh
# A release's Sparkle feed (appcast.xml) on stdout: one item, the zip at <url> with its EdDSA signature by the key in
# $SPARKLE_PRIVATE_KEY (Sparkle's base64 seed, as generate_keys exports it), and the notes as Markdown. Ed25519 signs
# the same bytes the same way every time, so OpenSSL 3's signature is the one sign_update makes.
# Usage: scripts/appcast.sh <name> <zip> <url> <version> <build> <notes.md>
set -eu
name=$1 zip=$2 url=$3 version=$4 build=$5 notes=$6
key=$(mktemp)
trap 'rm -f "$key" "$key.sig"' EXIT
# A DER Ed25519 private key is a fixed 16-byte header, then the 32-byte seed.
{
    printf '\060\056\002\001\000\060\005\006\003\053\145\160\004\042\004\040'
    printf '%s' "$SPARKLE_PRIVATE_KEY" | base64 -d
} >"$key"
openssl pkeyutl -sign -keyform DER -inkey "$key" -rawin -in "$zip" -out "$key.sig"
signature=$(base64 <"$key.sig" | tr -d '\n') length=$(wc -c <"$zip" | tr -d ' ')
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$name</title>
    <item>
      <title>$name $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$(cat "$notes")
]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream"
        sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF
