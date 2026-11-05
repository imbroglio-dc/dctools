"""What a repo's trust setup should look like on GitHub, and where it is weaker (spec §4, §7.3).

Copied into each repo by `biostat-trust apply`; the ownership check runs it on every PR.
"""

import hashlib
import json
import os

from . import config as cfg

ACTIONS_APP_ID = 15368   # GitHub Actions: the only source a required check accepts
ADMIN_ROLE = 5           # RepositoryRole actor id of the admin role
MAIN = "trust:main"
TAGS_CREATE = "trust:gate-tags-create"
TAGS_LOCK = "trust:gate-tags-lock"
NAMES = (MAIN, TAGS_CREATE, TAGS_LOCK)
MANIFEST = "MANIFEST.json"
MANIFEST_PATH = f".github/workflows/trust/{MANIFEST}"


def desired_rulesets(config):
    checks = [{"context": name, "integration_id": ACTIONS_APP_ID} for name in config.required_checks]
    tag_refs = [f"refs/tags/{gate}" for gate in cfg.GATE_PATTERNS]
    admin = {"actor_id": ADMIN_ROLE, "actor_type": "RepositoryRole"}
    return {
        MAIN: {
            "name": MAIN, "target": "branch", "enforcement": "active",
            "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
            "bypass_actors": [dict(admin, bypass_mode="pull_request")],
            "rules": [
                {"type": "deletion"},
                {"type": "non_fast_forward"},
                {"type": "pull_request", "parameters": {
                    "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": False,
                    "require_code_owner_review": False, "require_last_push_approval": False,
                    "required_review_thread_resolution": False}},
                {"type": "required_status_checks", "parameters": {
                    "strict_required_status_checks_policy": False, "required_status_checks": checks}},
            ],
        },
        TAGS_CREATE: {
            "name": TAGS_CREATE, "target": "tag", "enforcement": "active",
            "conditions": {"ref_name": {"include": tag_refs, "exclude": []}},
            "bypass_actors": [dict(admin, bypass_mode="always")],
            "rules": [{"type": "creation"}],
        },
        TAGS_LOCK: {
            "name": TAGS_LOCK, "target": "tag", "enforcement": "active",
            "conditions": {"ref_name": {"include": tag_refs, "exclude": []}},
            "bypass_actors": [],
            "rules": [{"type": "update"}, {"type": "deletion"}],
        },
    }


def diff_ruleset(want, have, strict=False):
    """(problems, notes): where the live ruleset `have` is weaker than `want`. Stronger is fine.

    GitHub hides a ruleset's bypass list from a token that cannot edit the ruleset. By default that is
    a note; with `strict` it is a problem, because a weakened bypass would go unreported."""
    name = want["name"]
    if have is None:
        return [f"ruleset {name} is missing"], []
    problems, notes = [], []
    if have.get("enforcement") != "active":
        problems.append(f"{name}: enforcement is {have.get('enforcement')}, not active")
    if have.get("target") != want["target"]:
        problems.append(f"{name}: targets {have.get('target')}, not {want['target']}")
    ref_name = (have.get("conditions") or {}).get("ref_name") or {}
    live_include = ref_name.get("include") or []   # null and absent both mean "covers nothing"
    missing_refs = [ref for ref in want["conditions"]["ref_name"]["include"] if ref not in live_include]
    if missing_refs:
        problems.append(f"{name}: no longer covers {', '.join(missing_refs)}")
    if ref_name.get("exclude"):
        problems.append(f"{name}: excludes {', '.join(ref_name['exclude'])}")
    live_rules = {rule.get("type"): rule.get("parameters") or {} for rule in have.get("rules") or []}
    for rule in want["rules"]:
        if rule["type"] not in live_rules:
            problems.append(f"{name}: rule {rule['type']} is missing")
        elif rule["type"] == "required_status_checks":
            live = {(c.get("context"), c.get("integration_id"))
                    for c in live_rules[rule["type"]].get("required_status_checks") or []}
            for check in rule["parameters"]["required_status_checks"]:
                if (check["context"], check["integration_id"]) not in live:
                    problems.append(f"{name}: required check {check['context']} from GitHub Actions is missing")
    if have.get("bypass_actors") is not None:
        allowed = {(a["actor_type"], a["actor_id"], a["bypass_mode"]) for a in want["bypass_actors"]}
        extra = [a for a in have["bypass_actors"]
                 if (a.get("actor_type"), a.get("actor_id"), a.get("bypass_mode")) not in allowed]
        if extra:
            problems.append(f"{name}: extra bypass actors {extra}")
    elif strict:
        problems.append(f"{name}: bypass list is not visible to this token; check it with the repo admin's token")
    else:
        notes.append(f"{name}: bypass list not visible to this token")
    return problems, notes


def live_rulesets(gh, repo):
    found = {}
    for summary in gh.paginate(f"/repos/{repo}/rulesets", {"includes_parents": "false"}):
        if summary.get("name") in NAMES:
            found[summary["name"]] = gh.get(f"/repos/{repo}/rulesets/{summary['id']}")
    return found


def verify_rulesets(gh, repo, config, strict=False):
    live = live_rulesets(gh, repo)
    problems, notes = [], []
    for name, want in desired_rulesets(config).items():
        p, n = diff_ruleset(want, live.get(name), strict)
        problems += p
        notes += n
    return problems, notes


def file_digest(data):
    return hashlib.sha256(data).hexdigest()


def manifest_for(files):
    """MANIFEST.json bytes: the sha256 of every file `biostat-trust apply` writes, except the manifest itself."""
    digests = {path: file_digest(data) for path, data in sorted(files.items()) if path != MANIFEST_PATH}
    return (json.dumps(digests, indent=2) + "\n").encode()


def check_manifest(repo_root):
    """Problems where the files `biostat-trust apply` wrote no longer match its MANIFEST."""
    try:
        with open(os.path.join(repo_root, MANIFEST_PATH)) as handle:
            recorded = json.load(handle)
    except (OSError, ValueError):
        return [f"{MANIFEST_PATH} is missing or unreadable"]
    if not isinstance(recorded, dict) or not recorded:   # an empty manifest would vouch for nothing
        return [f"{MANIFEST_PATH} is empty or not a table of file digests"]
    problems = []
    for path, digest in recorded.items():
        try:
            with open(os.path.join(repo_root, path), "rb") as handle:
                data = handle.read()
        except (OSError, ValueError):   # ValueError: a path with a NUL byte
            problems.append(f"{path} is missing")
            continue
        if file_digest(data) != digest:
            problems.append(f"{path} differs from what biostat-trust apply wrote")
    return problems
