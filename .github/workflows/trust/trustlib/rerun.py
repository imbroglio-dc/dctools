"""The review job (spec §5): rerun the head commit's `ownership` runs so a review changes their verdict.

GitHub requires every `ownership` run on the head to pass, and each workflow run is its own check suite, so a
second run started by the review would leave the first run's stale failure blocking the PR. Rerunning a
`pull_request_target` run replaces its result in place. It reruns all of the head's runs, not the newest alone:
an edit or a reopen of the PR leaves an older run on the same head, and its stale result would keep blocking
(or, after a dismissal, stay green). It lists by the head's sha and not by PR because two PRs can share a head,
and a dismissal on one must not leave the other's run green. A run from before a base retarget replays its old
base ref, which can only fail closed.

The job is named `ownership`, so it is one more run of the required check, and it fails closed: if it fails (no
run to rerun, a run still going after the timeout, a refused rerun, any error), the PR stays blocked instead of
standing on `ownership`'s last verdict, which after a dismissal or a requested change could be a stale green. Its
success adds nothing, since the head's other `ownership` runs must pass too. Once the cause has cleared, the user
reruns this `ownership-review` run from the Actions tab, or pushes a new commit to the PR (Update branch). Some
runs can never pass on a rerun: one past GitHub's 30-day limit on reruns, or one from before a retarget whose old
base branch has been deleted. Closing and reopening the PR adds a new run but leaves the stuck one; only a push,
which makes a new head, clears it.

Runs in GitHub Actions from the default branch's copy under .github/workflows/trust/, on the standard library
and `github` alone: the job installs nothing.
"""

import json
import os
import sys
import time

from .github import GitHub, GitHubError

WORKFLOW = "ownership.yml"
TITLE = "::error title=rerun-ownership::"
# The required checks rerun on a review: the workflow, the event its runs come from, and the check's name. The
# `release` check (release.yml) runs on `pull_request` because it runs the project's R code, which must not run
# with a `pull_request_target` token; its review job reruns its runs the same way.
CHECKS = {
    "ownership": ("ownership.yml", "pull_request_target"),
    "release": ("release.yml", "pull_request"),
}


def main(environ=None, client=GitHub, sleep=time.sleep, clock=time.monotonic, timeout=600, poll=10,
         check="ownership"):
    """0 once every `ownership` run on the head has been rerun; 1 when there is none or GitHub refused any
    rerun (the others are still rerun). Any other error propagates and the job shows red, with the earlier
    verdicts standing (see the module docstring)."""
    environ = os.environ if environ is None else environ
    with open(environ["GITHUB_EVENT_PATH"]) as handle:
        event = json.load(handle)
    repo = event["repository"]["full_name"]
    sha = event["pull_request"]["head"]["sha"]
    check = environ.get("TRUST_RERUN_CHECK", check)
    workflow, event = CHECKS[check]
    return rerun_head(client(environ["GH_TOKEN"]), repo, sha, sleep=sleep, clock=clock, timeout=timeout, poll=poll,
                      workflow=workflow, event=event, name=check,
                      title=TITLE if check == "ownership" else f"::error title=rerun-{check}::")


def rerun_head(gh, repo, sha, *, sleep=time.sleep, clock=time.monotonic, timeout=600, poll=10, out=print,
               title=TITLE, workflow=WORKFLOW, event="pull_request_target", name="ownership"):
    """Rerun every `ownership` run on `sha` once all have finished: 0 when each was rerun, 1 otherwise. The review
    job's body; `biostat-trust tag` calls it for each open PR after a gate tag lands (spec §11, gate-tag timing)."""
    listed = gh.paginate(f"/repos/{repo}/actions/workflows/{workflow}/runs",
                         {"event": event, "head_sha": sha}, key="workflow_runs")
    if not listed:
        out(f"{title}no {name} run on {sha[:7]}; close and reopen the PR to start one")
        return 1
    runs = {run["id"]: run for run in listed}   # GitHub documents no order, so the ids set it
    deadline = clock() + timeout
    # A run still going may have read the reviews before this one landed, so every run is rerun once all finish.
    while True:
        going = [i for i in sorted(runs) if runs[i]["status"] != "completed"]
        if not going:
            break
        if clock() >= deadline:
            out(f"{title}{name} run {going[0]} is still running after {timeout}s; "
                  "rerun it from the Actions tab once it finishes")
            return 1
        sleep(poll)
        for i in going:
            runs[i] = gh.get(f"/repos/{repo}/actions/runs/{i}")
    done, refused = [], False
    # Whatever each concluded: a dismissed approval must turn a passing check red. The reruns go back to back, which
    # is safe only because ownership.yml has no concurrency group: a rerun keeps its event, so a group would cancel
    # all but the last, and a cancelled run blocks the required check.
    for i in sorted(runs):
        try:
            gh.post(f"/repos/{repo}/actions/runs/{i}/rerun")
        except GitHubError as err:   # GitHub refuses runs older than 30 days
            out(f"{title}GitHub refused to rerun {name} run {i} (HTTP {err.status}); "
                  "rerun it from the Actions tab, or push a new commit to the PR (Update branch)")
            refused = True
        else:
            done.append(str(i))
    if done:
        out(f"reran {name} runs {', '.join(done)} on {sha[:7]}")
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main())
