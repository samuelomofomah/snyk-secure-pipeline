#!/usr/bin/env bash
# THE LEAD ENGINEER'S DECISION: read GitHub's own record of who approved or
# rejected this run's production deployment.
#
# Prints one line: <approved|rejected> <github-username> <comment>
# Prints nothing if nobody has decided yet, or the record cannot be read.
set -euo pipefail

[[ -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]] || exit 0

api="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/approvals"

json="$(curl --silent --show-error --fail --max-time 15 \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$api")" || exit 0

jq -r 'if length == 0 then empty
       else .[0] | "\(.state) \(.user.login) \((.comment // "") | gsub("[\r\n]+"; " "))"
       end' <<<"$json"
