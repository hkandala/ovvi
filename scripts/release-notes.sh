#!/bin/sh
# The release notes of a tag, in Markdown: its message, then the feat subjects since the previous release, then the
# fix and perf subjects folded. A final release counts from the last final release; the first lists no commits.
set -eu
tag=$1
case $tag in *-*) set -- ;; *) set -- --exclude 'v*-*' ;; esac
prev=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$@" "$tag^" 2>/dev/null) || prev=
git tag -l --format='%(contents:subject)' "$tag"
body=$(git tag -l --format='%(contents:body)' "$tag")
[ -z "$body" ] || printf '\n%s\n' "$body"
[ -n "$prev" ] || exit 0

# `type(scope): summary` becomes `- summary (scope)`.
subjects() {
    git log --no-merges --format=%s "$prev..$tag" | sed -nE "s/^($1)(\(([^)]*)\))?: (.*)$/- \4 (\3)/p" | sed 's/ ()$//'
}
new=$(subjects feat) fixes=$(subjects 'fix|perf')
[ -z "$new" ] || printf '\n### New\n\n%s\n' "$new"
[ -z "$fixes" ] || printf '\n<details><summary>Fixes (%s)</summary>\n\n%s\n\n</details>\n' \
    "$(printf '%s\n' "$fixes" | wc -l | tr -d ' ')" "$fixes"
