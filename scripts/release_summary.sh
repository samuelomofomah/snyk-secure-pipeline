#!/usr/bin/env bash
# RELEASE NOTES FOR THE LEAD ENGINEER: what this release would change, written
# to the top of the pipeline run's page, so whoever approves it can decide in a
# minute. Runs after every test and scan has passed on main.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# The text between <h1> and </h1>, with any | removed so it fits in a table.
headline() {
  python3 -c '
import re, sys
m = re.search(r"<h1[^>]*>(.*?)</h1>", sys.stdin.read(), re.S)
print((m.group(1).strip() if m else "(no headline found)").replace("|", "/"))
'
}

new_headline="$(headline < dist/index.html)"

live_headline="(the live site could not be reached)"
if [[ -n "${SITE_URL:-}" ]]; then
  page="$(curl --silent --fail --max-time 10 "$SITE_URL" || true)"
  [[ -n "$page" ]] && live_headline="$(printf '%s' "$page" | headline)"
fi

# A merged pull request's message starts "Merge pull request #N from ...";
# its second paragraph is the pull request's title, which says more.
change_title() {
  local first rest
  first="$(head -n 1 <<<"$1")"
  if [[ "$first" == "Merge pull request"* ]]; then
    rest="$(tail -n +2 <<<"$1" | awk 'NF { print; exit }')"
    [[ -n "$rest" ]] && { printf '%s\n' "$rest"; return; }
  fi
  printf '%s\n' "$first"
}
change="$(change_title "${CHANGE_TITLE:-}" | tr '|' '/')"

{
  echo "## Release #${RUN_NUMBER} is waiting for the lead engineer"
  echo
  echo "Every test and scan passed. Nothing goes live until a lead engineer approves the **production** deployment."
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Change | ${change:-(no message)} |"
  echo "| Merged by | ${ACTOR:-unknown} |"
  echo "| Commit | \`${COMMIT_SHA:0:7}\` |"
  echo "| Headline live now | ${live_headline} |"
  echo "| Headline after this release | ${new_headline} |"
  echo
  echo "### What changed"
  echo
  if git rev-parse --quiet --verify HEAD~1 >/dev/null; then
    echo '```diff'
    git diff HEAD~1 HEAD | head -n 150 || true
    echo '```'
  else
    echo "This is the first release, so there is nothing to compare it with."
  fi
  echo
  echo "### To decide"
  echo
  echo "Scroll to the top of this run page, click **Review deployments**, tick **production**, add a comment, then click **Approve and deploy** or **Reject**."
} >> "$out"

echo "Release notes written to the run's summary page."
