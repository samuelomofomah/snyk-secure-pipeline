#!/usr/bin/env bash
# SLACK ALERT: tell the team what just happened.
#
#   STAGE=review  -> a release passed every check and needs the lead engineer
#   (default)     -> the final result: blocked, rejected, or live
#
# The webhook URL is a secret. It arrives as an environment variable from
# GitHub's encrypted secret store and is never written to a file or printed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::warning::SLACK_WEBHOOK_URL secret is not set, so no Slack alert was sent."
  exit 0
fi

# Slack treats & < > as formatting characters, so escape them in free text.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }
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
title="$(esc "$(change_title "${CHANGE_TITLE:-a change}")")"
actor="$(esc "${ACTOR:-someone}")"

is_failed() { [[ "$1" == "failure" || "$1" == "cancelled" ]]; }

if [[ "${STAGE:-}" == "review" ]]; then
  text=":eyes: *Release #${RUN_NUMBER} needs the lead engineer.* \"${title}\" by ${actor} passed every test and scan. Nothing is live until it is approved. <${RUN_URL}|Review and approve>"

elif is_failed "${CHECK_RESULT:-}" || is_failed "${LOCKDOWN_RESULT:-}"; then
  failed=()
  is_failed "${CHECK_RESULT:-}" && failed+=("Test and scan")
  is_failed "${LOCKDOWN_RESULT:-}" && failed+=("Pull request lockdown proof")
  stage="$(printf '%s, ' "${failed[@]}")"
  stage="${stage%, }"
  text=":x: *Blocked.* \"${title}\" by ${actor} did not pass: ${stage}. Nothing was published. <${RUN_URL}|See why>"

elif [[ "${DEPLOY_RESULT:-}" == "success" ]]; then
  read -r _state approver _comment <<<"$(bash scripts/approval.sh)" || true
  by=""
  [[ -n "${approver:-}" ]] && by=", approved by $(esc "$approver")"
  text=":white_check_mark: *Release #${RUN_NUMBER} is live*${by}. \"${title}\" by ${actor}. <${SITE_URL:-$RUN_URL}|Open the site> · <${RUN_URL}|Pipeline run>"

elif [[ "${EVENT:-}" == "push" ]]; then
  # On main, a deploy that did not succeed was either rejected by the lead
  # engineer or failed. GitHub's approval record tells the two apart.
  read -r state approver comment <<<"$(bash scripts/approval.sh)" || true
  if [[ "${state:-}" == "rejected" ]]; then
    reason=""
    [[ -n "${comment:-}" ]] && reason=" Reason: \"$(esc "$comment")\"."
    text=":no_entry: *Release #${RUN_NUMBER} was rejected* by lead engineer $(esc "$approver").${reason} \"${title}\" was not published; the live site is unchanged. <${RUN_URL}|Details>"
  else
    text=":x: *Release #${RUN_NUMBER} did not go live.* The deploy of \"${title}\" failed or was cancelled. <${RUN_URL}|See why>"
  fi

else
  text=":white_check_mark: *Checks passed.* \"${title}\" by ${actor} is safe to merge. <${RUN_URL}|Details>"
fi

payload="$(jq -n --arg text "$text" '{text: $text}')"

curl --silent --show-error --fail --max-time 15 \
  -X POST -H 'Content-type: application/json' \
  --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null

echo "Slack alert sent."
