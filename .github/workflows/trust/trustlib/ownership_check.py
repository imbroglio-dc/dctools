"""The `ownership` required check (spec §5): gather a PR's facts from GitHub, apply the rules, report.

Runs in GitHub Actions from the default branch's copy under .github/workflows/trust/. It reads the API
and never checks out or runs the PR's code.
"""

import json
import os
import sys

from . import config as cfg, rules, verify
from .github import GitHub, GitHubError

NULL_SHA = "0" * 40
# GitHub stops listing here without saying so: a list this long may be cut short.
PR_FILES_CAP = 3000
PR_COMMITS_CAP = 250
COMMIT_FILES_CAP = 3000
COMPARE_COMMITS_CAP = 250


class Incomplete(Exception):
    """GitHub's listings cannot be trusted to show the whole PR, so the rules cannot judge it."""


def _names(entry):
    names = [entry["filename"]]
    if entry.get("previous_filename"):
        names.append(entry["previous_filename"])
    return names


def pushers_by_commit(gh, repo, branch, base_ref):
    """Commit sha -> login of whoever first pushed it to `branch`, from the Activity API."""
    found = {}
    events = gh.paginate(f"/repos/{repo}/activity", {"ref": f"refs/heads/{branch}", "direction": "asc"})
    for event in events:
        if event.get("activity_type") not in ("push", "force_push", "branch_creation"):
            continue
        before = event.get("before") or NULL_SHA
        start = base_ref if before == NULL_SHA else before
        actor = (event.get("actor") or {}).get("login")
        span = f"{start}...{event['after']}"
        listed = gh.get(f"/repos/{repo}/compare/{span}").get("commits", [])
        if len(listed) >= COMPARE_COMMITS_CAP:   # a dropped commit would be taken for someone else's later
            raise Incomplete(f"compare {start[:7]}...{event['after'][:7]} lists {len(listed)} commits; GitHub "
                             f"lists at most {COMPARE_COMMITS_CAP}, so the list may be cut short")
        for commit in listed:
            found.setdefault(commit["sha"], actor)   # first push wins: a later event may list it again
    return found


def _commit_files(gh, repo, sha):
    """(the files a commit changes, its author's login, its committer's login). A login is None when GitHub ties
    the commit's email to no account. `paginate` keeps only the file pages, so the commit's own fields come from
    one more read of its first page."""
    entries = gh.paginate(f"/repos/{repo}/commits/{sha}", key="files")
    if len(entries) >= COMMIT_FILES_CAP:
        raise Incomplete(f"commit {sha[:7]} lists {len(entries)} files; GitHub lists at most {COMMIT_FILES_CAP} "
                         "per commit, so the list may be cut short")
    commit = gh.get(f"/repos/{repo}/commits/{sha}")
    author, committer = ((commit.get(role) or {}).get("login") for role in ("author", "committer"))
    return tuple(name for entry in entries for name in _names(entry)), author, committer


def gather(gh, repo, pr_event, config):
    number = pr_event["number"]
    head_repo = (pr_event["head"].get("repo") or {}).get("full_name")
    entries = gh.paginate(f"/repos/{repo}/pulls/{number}/files")
    if len(entries) >= PR_FILES_CAP:
        raise Incomplete(f"the PR lists {len(entries)} changed files; GitHub lists at most {PR_FILES_CAP}, "
                         "so the list may be cut short")
    changed = tuple(name for entry in entries for name in _names(entry))
    shas = [c["sha"] for c in gh.paginate(f"/repos/{repo}/pulls/{number}/commits")]
    if len(shas) >= PR_COMMITS_CAP:
        raise Incomplete(f"the PR lists {len(shas)} commits; GitHub lists at most {PR_COMMITS_CAP}, "
                         "so the list may be cut short")
    head = pr_event["head"]["sha"]
    if head not in shas:   # GitHub documents no order, so membership is all that can be asked
        raise Incomplete(f"the PR's head commit {head[:7]} is not in its commit listing, "
                         "which may be stale or cut short")
    pushers = pushers_by_commit(gh, repo, pr_event["head"]["ref"], pr_event["base"]["ref"])
    bots = set(rules.app_logins(config).values())
    commits = []
    for sha in shas:
        files, author, committer = _commit_files(gh, repo, sha)
        commits.append(rules.Commit(sha, pushers.get(sha), files, made_by_app=bool({author, committer} & bots)))
    commits = tuple(commits)
    # The rules attribute each changed path through the commits that list it. A path no commit lists is
    # one the listings disagree about, so it cannot be attributed. A commit listing more than the PR
    # changes (a file a later commit reverts) is ordinary.
    listed = {name for commit in commits for name in commit.files}
    unlisted = [name for name in changed if name not in listed]
    if unlisted:
        shown = ", ".join(f"`{name}`" for name in unlisted[:3])
        more = f" and {len(unlisted) - 3} more" if len(unlisted) > 3 else ""
        raise Incomplete(f"the PR changes {shown}{more}, which no commit's file list includes, "
                         "so the changes cannot be attributed to commits")
    reviews = tuple(rules.Review(r["user"]["login"], r["state"], r.get("commit_id") or "")
                    for r in gh.paginate(f"/repos/{repo}/pulls/{number}/reviews") if r.get("user"))
    return rules.PR(number, pr_event["head"]["sha"], head_repo != repo, changed, commits, reviews)


def bypass_note(gh, repo):
    try:
        suites = gh.paginate(f"/repos/{repo}/rulesets/rule-suites",
                             {"rule_suite_result": "bypass", "time_period": "month"})
    except GitHubError as err:
        return f"bypasses: listing unavailable to this token (HTTP {err.status})"
    if not suites:
        return "bypasses: none in the last month"
    return "bypasses in the last month: " + "; ".join(
        f"{s.get('actor_name')} on {s.get('ref')} at {s.get('pushed_at')}" for s in suites)


def _report(environ, text):
    print(text)
    if environ.get("GITHUB_STEP_SUMMARY"):
        with open(environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(text)


def error_command(finding):
    """The workflow command that puts a failed rule on the check run as an annotation titled `ownership`.

    It is how a reader (the sandbox probe included) tells the rules' verdict from a crash: a crashed
    check also ends red, but it never prints this. One line; `%` is the command syntax's escape character."""
    reason = " ".join(f"{finding.rule}: {finding.message}".split()).replace("%", "%25")
    return f"::error title=ownership::{reason}"


def main(environ=None, client=GitHub):
    """0 when the PR passes; 1 when the rules fail it or GitHub's listings cannot show all of it.
    Any other error is a crash and propagates: a crashed check is a red check. Only a rules failure prints
    an error annotation."""
    environ = os.environ if environ is None else environ
    with open(environ["GITHUB_EVENT_PATH"]) as handle:
        event = json.load(handle)
    repo = event["repository"]["full_name"]
    owner = event["repository"]["owner"]["login"]
    config = cfg.load(environ["TRUST_CONFIG"])
    gh = client(environ["GH_TOKEN"])
    try:
        pr = gather(gh, repo, event["pull_request"], config)
    except Incomplete as err:
        _report(environ, f"ownership: failed — {err}\n")
        return 1
    tags = [ref["ref"].removeprefix("refs/tags/") for ref in gh.paginate(f"/repos/{repo}/git/matching-refs/tags/")]
    problems, notes = verify.verify_rulesets(gh, repo, config)
    problems += verify.check_manifest(environ["TRUST_REPO_ROOT"])
    notes.append(bypass_note(gh, repo))
    findings = rules.evaluate(pr, config, tags, owner, problems)
    _report(environ, rules.summary(findings, pr) + "".join(f"\n- {note}" for note in notes) + "\n")
    if rules.passed(findings):
        return 0
    print(error_command(next(f for f in findings if f.fatal)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
