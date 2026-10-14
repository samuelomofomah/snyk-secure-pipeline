# Snyk secure pipeline: a secure CI/CD demo with a lead engineer review

A small website with a pipeline that tests it, scans it with Snyk, waits for a
lead engineer to approve the release, and only then publishes it to AWS.
Nine safeguards, each of which you test by trying to get past it. Setup and
tests take about 35 minutes.

## The nine safeguards

| Safeguard | In plain English | Where it lives | How you test it |
|---|---|---|---|
| Automated testing and deployment | A robot checks every change and publishes the approved ones | `.github/workflows/pipeline.yml`, `tests/check.sh` | Merge a change, approve it, watch it go live |
| Lead engineer review | A person signs off every release before it goes live | GitHub environment `production` with a required reviewer | Reject one release and approve another |
| OIDC authentication | The robot signs in with a 15-minute visitor pass, not a stored key | `infra/main.tf` (trust policy), the "Sign in to AWS" step | No AWS key exists in GitHub, and a pull request is refused |
| IAM least privilege | The pass opens one door: the site's storage bucket | `infra/main.tf` (role policy), `tests/least_privilege.sh` | The pipeline tries five other things and AWS refuses each |
| Secrets management | Passwords live in a vault, never in the code | GitHub Actions secrets, `tests/secret_scan.sh` | The Slack address shows as `***` in logs, and a hard-coded password is blocked |
| Branch protection | Nobody, including the owner, can skip the checks | GitHub ruleset on `main` | A direct push to `main` is rejected |
| Vulnerability scanning (Snyk) | Third-party ingredients are checked against Snyk's recall list | `tests/snyk_scan.sh` | A change that uses a known-vulnerable library is blocked |
| Slack alerts | The team hears about every block, every review request, every rejection and every release | `scripts/notify.sh` | Messages arrive in Slack at each stage |
| Audit logging | AWS keeps its own record of every sign-in | AWS CloudTrail, `audit.sh` | Approved releases appear; the rejected one never signed in |

## How a release flows

1. You change the code on a branch and open a pull request.
2. **Test and scan** runs: password scan, Snyk, build, quality checks. A separate job proves the pull request cannot reach AWS.
3. When the checks are green you merge into `main`.
4. The checks run again on `main`. Slack asks the lead engineer to review, and the run page shows release notes: what changed, and the headline live now versus after this release.
5. **Deploy to AWS** waits. Nothing is published until the lead engineer clicks **Approve and deploy**. **Reject** stops it.
6. After approval, GitHub vouches for the job as `environment:production`, the only identity AWS trusts, and the site is published.

## What you need

- A GitHub account, and `git` on your computer
- An AWS account, with the AWS CLI signed in as a user who can create IAM roles, S3 buckets and CloudFront distributions. Check with `aws sts get-caller-identity`; if it says the session has expired, run `aws login` first
- Terraform (`brew install hashicorp/tap/terraform` on a Mac)
- A Slack workspace where you can add an app
- A free Snyk account (step 4)

Cost: effectively nothing. A few kilobytes in S3, a handful of CloudFront
requests, and Snyk's free plan.

If an earlier version of this project (for example Saturday or Friday) is
still running in the same AWS account, run its `bash teardown.sh` first. The
two would share GitHub's trust registration in AWS, and removing the older one
later would break this one.

## Setup

### 1. Create the repository (1 min)

Go to <https://github.com/new>. Name it `snyk-secure-pipeline`, set it to
**Public**, leave every checkbox empty, and click **Create repository**.

It has to exist before the next step, because AWS is going to be told to trust
this exact repository by its permanent ID. It has to be public because branch
protection and environment reviewers are free only on public repositories.

### 2. Build the AWS side (1 min of typing, about 4 min of waiting)

In a terminal, from inside this folder:

```bash
bash setup.sh YOUR-USERNAME/snyk-secure-pipeline
```

This creates a private storage bucket, a CloudFront address that serves it over
HTTPS, a trust relationship with GitHub, and a role that only an approved
production release can use. It ends by printing three values. Leave the
terminal open and carry on while it runs.

### 3. Create the Slack alert address (3 min)

1. Open <https://api.slack.com/apps?new_app=1>, choose **Blank app**, click **Continue**, name it `Pipeline alerts`, pick your workspace, and create it.
2. In the left menu click **Incoming Webhooks** and switch **Activate Incoming Webhooks** on.
3. Click **Add New Webhook to Workspace**, pick a channel (or yourself), click **Allow**.
4. Click **Copy** in the **Webhook URL** row. Treat it like a password. The sample command on that page contains it, so never screenshot that page.

### 4. Get a Snyk token (3 min)

1. Go to <https://app.snyk.io> and sign up with your GitHub account. If it offers to import or connect repositories, skip that: the pipeline runs Snyk itself.
2. Open **Account settings** (click your name or avatar, bottom left).
3. Under **General**, find **Auth Token**, click the hidden **KEY** to show it, and copy it.

Treat it like a password: it lets anyone run scans as you. If Snyk asked you
to pick a region other than the default (US), tell me, because the pipeline
then needs one extra setting.

### 5. Give GitHub three secrets and two variables (3 min)

In the repository: **Settings > Secrets and variables > Actions**.

- **Secrets** tab, **New repository secret**, three times:
  - `SLACK_WEBHOOK_URL`: the URL from step 3.
  - `SNYK_TOKEN`: the token from step 4.
  - `AWS_ROLE_ARN`: the value `setup.sh` printed.
- **Variables** tab, **New repository variable**, twice: `S3_BUCKET` and `SITE_URL`, with the values `setup.sh` printed.

If `setup.sh` said it saved its three values for you, only the Slack and Snyk
secrets are left to add. Notice what is missing: there is no AWS key.

### 6. Make yourself the lead engineer (3 min)

**Settings > Environments > New environment.** Name it `production` (all
lowercase, exactly) and click **Configure environment**.

1. Tick **Required reviewers**, type your GitHub username and select yourself.
2. Leave **Prevent self-review** unticked. You are the only reviewer, and you will be approving your own changes.
3. If you see **Allow administrators to bypass configured protection rules**, untick it, so even the owner must go through review.
4. Under **Deployment branches and tags**, change **No restriction** to **Selected branches and tags**. Click **Add deployment branch or tag rule**, keep **Branch**, type `main`, and click **Add rule**.
5. Click **Save protection rules**.

Do this before step 7. If the pipeline runs first, GitHub creates
`production` itself with no reviewers, and the first release goes out
unreviewed.

### 7. Push the project and approve the first release (4 min)

```bash
git init -b main
git add .
git commit -m "First release"
git remote add origin https://github.com/YOUR-USERNAME/snyk-secure-pipeline.git
git push -u origin main
```

Open the **Actions** tab and click the run.

- **Test and scan** and **Ask the lead engineer to approve** turn green, and a Slack message asks for your review.
- **Deploy to AWS** shows **Waiting**. The site address shows an error page for now, because nothing has been published yet.
- Click **Review deployments**, tick **production**, write a comment such as `First release, approved`, and click **Approve and deploy**.

When the run is green, open your `SITE_URL`: the page shows Release #1, and
Slack says it is live and who approved it.

### 8. Lock the main branch (3 min)

**Settings > Rules > Rulesets > New ruleset > New branch ruleset.**

1. Ruleset name: `protect-main`. Enforcement status: **Active**.
2. Target branches: **Add target > Include default branch**.
3. Tick **Restrict deletions** and **Block force pushes** (usually ticked already).
4. Tick **Require a pull request before merging**. Leave required approvals at 0, since you are working alone and GitHub does not let you approve your own pull request. On a team this would be 1 or more.
5. Tick **Require status checks to pass**, click **Add checks**, type `Test and scan`, select it.
6. Click **Create**.

From now on the only way onto `main` is a pull request whose checks are green,
and the only way onto the live site is your approval.

## The tests

### Test 1. Read the first release (2 min): review, OIDC, least privilege, secrets

Open run #1 in the Actions tab and click **Deploy to AWS**.

- **Show who approved this release**: `approved by YOUR-USERNAME`, with your comment.
- **Show the identity GitHub vouches for**: it ends in `:environment:production`. That identity only exists after approval, and it is the only one AWS trusts.
- **Sign in to AWS with a 15-minute pass**: no key was supplied.
- **Show who the pipeline is signed in as**: `snyk-secure-pipeline-deploy/release-1`. The AWS account number is never printed.
- **Prove the pipeline cannot do anything else in AWS**: five lines of `PASS  Refused`.

Then click **Tell the team on Slack** and open **Send the Slack alert**. The
webhook address appears as `***`.

### Test 2. Try to skip the checks (1 min): branch protection

```bash
git commit --allow-empty -m "Sneak past the checks"
git push
```

GitHub rejects the push with `GH013: Repository rule violations`. Undo the
local commit with `git reset --hard origin/main`. If the push goes through,
the ruleset from step 8 is missing or not **Active**.

### Test 3. Propose a known-vulnerable library (4 min): Snyk, alerts, OIDC lockdown

1. On GitHub, open `requirements.txt` and click the pencil.
2. Change `jinja2==3.1.6` to `jinja2==3.1.2`.
3. Click **Commit changes**, choose **Create a new branch for this commit and start a pull request**, then **Propose changes** and **Create pull request**.

Within a minute or two:

- **Test and scan** fails at **Scan third-party libraries with Snyk**. Open it: Snyk lists each known issue in `jinja2@3.1.2`, its severity, and the version that fixes it.
- **Prove pull requests cannot reach AWS** passes: AWS refused the pull request.
- The **Merge** button is blocked, a red message arrives in Slack, and the live site has not changed.

Click **Close pull request**.

### Test 4. Reject a release as the lead engineer (4 min)

This change passes every automated check, but it is not something the business
agreed to publish. Only a person can catch that.

1. Open `site/index.html.j2`, click the pencil, and change line 14 to `<h1>Everything 90% off, today only</h1>`.
2. Commit to a new branch, create the pull request, wait for green, then **Merge pull request > Confirm merge**.
3. Slack asks for your review. Open the run: its summary page shows the release notes, with **Headline live now** and **Headline after this release** side by side.
4. Click **Review deployments**, tick **production**, comment `No sale was agreed`, and click **Reject**.

- **Deploy to AWS** never runs, and the live site is unchanged.
- Slack says the release was rejected, by whom, and why.

The rejected text is now in `main` but not on the site. On a real team you
would revert it; here, Test 5 replaces it.

### Test 5. Approve a good release (3 min): the whole path

1. Change line 14 again, to a headline you are happy with.
2. Commit to a new branch, create the pull request, wait for green, merge.
3. Look at the live site: it has not changed. Green checks and a merge are not a release.
4. Read the release notes on the run's summary page, then **Review deployments > production > Approve and deploy**.

The deploy runs, Slack announces the release and who approved it. Refresh the
site with Cmd+Shift+R.

### Test 6. Read the audit log (1 min): audit logging

```bash
bash audit.sh
```

Each row is a sign-in that AWS recorded: the time, the pipeline run (for
example `release-1`) and the identity GitHub presented, ending in
`environment:production`. The release you rejected has no row: it never got a
pass. Records can take up to 15 minutes to appear, which is why this test is
last.

### Optional. Commit a password

Through a pull request, add a file `config.py` containing:

```python
DB_PASSWORD = "SuperSecret123"
```

**Test and scan** fails within seconds at "Scan the code for passwords and
keys". The log names the file and line, and does not print the password. Close
the pull request and delete its branch afterwards.

## Clean up

Do these in order. The first step needs the files in this folder.

1. `bash teardown.sh` deletes everything in AWS. CloudFront takes several minutes.
2. Delete the Slack app at <https://api.slack.com/apps>, which revokes the webhook.
3. In Snyk, **Account settings > General > Auth Token**, regenerate the token if you want the old one to stop working.
4. Delete the repository: **Settings > General > Danger Zone > Delete this repository**.
5. Delete this folder.

## If something goes wrong

- **Snyk fails with an authentication error, or "could not finish the scan".** The `SNYK_TOKEN` secret is missing or was pasted incompletely. Copy it again from Snyk and update the secret.
- **Snyk fails on the very first run.** A vulnerability may have been published for a pinned library since this project was written. Raise the version in `requirements.txt` to the one Snyk recommends.
- **Deploy to AWS never waits for approval.** The environment is not named exactly `production`, or **Required reviewers** was not saved. Check step 6.
- **You cannot approve your own release.** **Prevent self-review** is ticked. Untick it in the environment settings.
- **"Branch is not allowed to deploy to production".** The deployment branch rule must be the branch `main`. Check step 6.4.
- **`Not authorized to perform sts:AssumeRoleWithWebIdentity` after approval.** Compare the line **GitHub vouches for** in the deploy log with what AWS expects: it must end in `:environment:production` and name this repository. Re-running `setup.sh` refreshes the trust after a rename.
- **The deploy job cannot find the role, bucket or site.** `AWS_ROLE_ARN` must be under Secrets; `S3_BUCKET` and `SITE_URL` must be under Variables. Check the names for typos.
- **No Slack message.** The run shows a warning if `SLACK_WEBHOOK_URL` is missing. A 404 means the URL was pasted incompletely.
- **`setup.sh` fails on CloudFront with "account must be verified".** New AWS accounts sometimes need this. AWS Support lifts it on request.

## Run it on your own computer

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python3 build.py
bash tests/check.sh dist
bash tests/secret_scan.sh
```

With the Snyk CLI installed, `SNYK_TOKEN=your-token bash tests/snyk_scan.sh`
runs the same scan locally.
