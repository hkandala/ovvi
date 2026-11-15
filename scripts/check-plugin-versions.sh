#!/bin/sh
# A published package's change reaches npm only with a new version (.github/workflows/plugins.yml): each package that
# changed since this branch left origin/main must have a new `version`. With no origin/main (CI's shallow checkout), no
# check.
base=$(git merge-base origin/main HEAD 2>/dev/null) || exit 0
status=0
for pair in web/ovvi:web/ovvi/ovvi.d.ts plugins/builtin/explorer: plugins/builtin/git:; do
  dir=${pair%%:*} watched=${pair#*:}
  git diff --quiet "$base" -- "${watched:-$dir}" && continue
  old=$(git show "$base:$dir/package.json" | jq -r .version) new=$(jq -r .version "$dir/package.json")
  if [ "$old" = "$new" ]; then
    echo "$dir changed since origin/main: bump its version in $dir/package.json (still $new)"
    status=1
  fi
done
exit $status
