#!/usr/bin/env bash
# VULNERABILITY SCAN (Snyk): check every third-party library in requirements.txt
# against Snyk's database of known vulnerabilities. A known vulnerability of any
# severity blocks the change.
#
# Needs the libraries installed first (Snyk reads what pip installed) and the
# SNYK_TOKEN secret, which identifies your free Snyk account.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "FAIL  The SNYK_TOKEN secret is not set, so Snyk cannot run."
  echo "      Add it in GitHub: Settings > Secrets and variables > Actions > Secrets."
  exit 1
fi
if ! command -v snyk >/dev/null 2>&1; then
  echo "FAIL  The Snyk command-line tool is not installed."
  exit 1
fi

snyk test \
  --file=requirements.txt \
  --package-manager=pip \
  --command=python \
  --severity-threshold=low
code=$?

echo
case "$code" in
  0) echo "PASS  Snyk found no known vulnerabilities in the third-party libraries." ;;
  1) echo "FAIL  Snyk found known vulnerabilities (listed above). Upgrade to the versions it recommends." ;;
  *) echo "FAIL  Snyk could not finish the scan (exit code ${code}). Check the SNYK_TOKEN secret and the message above." ;;
esac
exit "$code"
