"""The ownership check's rules (spec §5), as a pure function of facts gathered from GitHub.

Copied into each repo by `biostat-trust apply`.
"""

from dataclasses import dataclass

from . import config as cfg

AUDIT_PATHS = "tests/audit/**"
DECISIVE = ("APPROVED", "CHANGES_REQUESTED", "DISMISSED")


@dataclass(frozen=True)
class Commit:
    sha: str
    pusher: str | None
    files: tuple
    # Its author or committer is an App's bot (`app_logins`): the owner's push of it is not the owner's change.
    made_by_app: bool


@dataclass(frozen=True)
class Review:
    login: str
    state: str
    commit_id: str


@dataclass(frozen=True)
class PR:
    number: int
    head_sha: str
    from_fork: bool
    changed_files: tuple
    commits: tuple
    reviews: tuple


@dataclass(frozen=True)
class Finding:
    rule: str
    message: str
    fatal: bool


def app_logins(config):
    """The bot logins the support and critique Apps act as on GitHub: `<slug>[bot]`."""
    return {role: f"{config.apps[role]}[bot]" for role in ("support", "critique")}


def owner_approved_head(pr, owner):
    """The owner's latest decisive review approves the head commit. A dismissal, a request for
    changes, or an approval of an older commit leaves the PR unapproved; a comment changes nothing."""
    latest = None
    for review in pr.reviews:
        if review.login == owner and review.state in DECISIVE:
            latest = review
    return latest is not None and latest.state == "APPROVED" and latest.commit_id == pr.head_sha


def evaluate(pr, config, tag_names, owner, drift=()):
    # None is also what a commit with no known pusher carries, so a missing owner would own every such commit.
    if not isinstance(owner, str) or not owner:
        raise ValueError(f"owner must be a non-empty GitHub login, got {owner!r}")
    if pr.from_fork:
        return [Finding("fork", "PRs from forks are not accepted in this repo.", True)]
    findings = []
    approved = owner_approved_head(pr, owner)
    head = pr.head_sha[:7]
    apps = app_logins(config)
    support, critique = apps["support"], apps["critique"]
    known = {owner: "owner", support: "support", critique: "critique"}

    active = cfg.active_frozen(config, tag_names)
    for path in pr.changed_files:
        reason = cfg.frozen_reason(path, active)
        if reason is None:
            continue
        touching = [c for c in pr.commits if path in c.files]
        # The exception is for the owner's own changes: a commit an App made stays the App's, whoever pushed it
        # (an owner's branch made from an agent's names the owner as pusher; final review I4).
        app_made = [c for c in touching if c.made_by_app]
        if touching and all(c.pusher == owner and not c.made_by_app for c in touching):
            findings.append(Finding("frozen", f"`{path}` ({reason}) changed only in commits {owner} pushed.", False))
        elif approved:
            findings.append(Finding("frozen", f"`{path}` ({reason}) changed; {owner} approved {head}.", False))
        else:
            made = (f"; an App made {', '.join(c.sha[:7] for c in app_made)}, though {owner} pushed it"
                    if app_made and all(c.pusher == owner for c in touching) else "")
            findings.append(Finding("frozen", f"`{path}` ({reason}) changed{made}; needs {owner}'s approving "
                                              f"review of {head}.", True))

    for commit in pr.commits:
        audit = [f for f in commit.files if cfg.glob_match(AUDIT_PATHS, f)]
        other = [f for f in commit.files if not cfg.glob_match(AUDIT_PATHS, f)]
        if commit.pusher == critique and other:
            findings.append(Finding("audit", f"{commit.sha[:7]}: critique may change only {AUDIT_PATHS}, "
                                             f"but changed {', '.join(other)}.", True))
        if audit and commit.pusher != critique:
            findings.append(Finding("audit", f"{commit.sha[:7]}: only critique may change {AUDIT_PATHS}; "
                                             f"pushed by {commit.pusher or 'an unknown identity'}.", True))
    # The per-commit lists and changed_files come from different API calls; an audit path that critique's
    # commits do not account for fails closed, as an unlisted frozen path does above.
    critique_files = {f for c in pr.commits if c.pusher == critique for f in c.files}
    for path in pr.changed_files:
        if cfg.glob_match(AUDIT_PATHS, path) and path not in critique_files:
            findings.append(Finding("audit", f"`{path}` changed, but no commit by critique lists it; "
                                             f"only critique may change {AUDIT_PATHS}.", True))

    for commit in pr.commits:
        role = known.get(commit.pusher)
        who = commit.pusher or "an unknown identity"
        if role:
            findings.append(Finding("attribution", f"{commit.sha[:7]} pushed by {who} ({role}).", False))
        elif approved:
            findings.append(Finding("attribution", f"{commit.sha[:7]} pushed by {who}; {owner} approved {head}.", False))
        else:
            findings.append(Finding("attribution", f"{commit.sha[:7]} pushed by {who}, not an App or {owner}; "
                                                   f"needs {owner}'s approving review of {head}.", True))

    findings += [Finding("drift", problem, True) for problem in drift]
    return findings


def passed(findings):
    return not any(f.fatal for f in findings)


def summary(findings, pr):
    verdict = "passed" if passed(findings) else "failed"
    lines = [f"## ownership: {verdict} (PR #{pr.number}, head {pr.head_sha[:7]})", "",
             "| | Rule | Finding |", "|---|---|---|"]
    for finding in findings:
        mark = "❌" if finding.fatal else "✅"
        message = finding.message.replace("|", "\\|")
        lines.append(f"| {mark} | {finding.rule} | {message} |")
    return "\n".join(lines) + "\n"
