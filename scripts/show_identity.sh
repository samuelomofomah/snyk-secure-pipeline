#!/usr/bin/env bash
# WHO GITHUB SAYS THIS RUN IS: print the "subject" of the identity pass GitHub
# issues for this job. AWS compares exactly this text with its trust policy.
#
# For the deploy job it ends in ":environment:production", which only exists
# once the lead engineer has approved. The pass itself is never printed.
set -euo pipefail

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  echo "No identity pass is available to this job (it needs 'id-token: write')."
  exit 0
fi

token="$(curl --silent --show-error --fail --max-time 15 \
  -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')"
echo "::add-mask::${token}"

subject="$(TOKEN="$token" python3 -c '
import base64, json, os
part = os.environ["TOKEN"].split(".")[1]
part += "=" * (-len(part) % 4)
print(json.loads(base64.urlsafe_b64decode(part))["sub"])
')"

echo "GitHub vouches for: ${subject}"
