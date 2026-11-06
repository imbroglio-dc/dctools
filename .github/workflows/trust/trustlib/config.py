"""A repo's trust config (.github/workflows/trust/trust.yaml) and the git-style globs it uses (spec §7.4).

Copied into each repo by `biostat-trust apply`, so it imports nothing outside the standard library and PyYAML.
The config sits in the trust/ subdirectory because Actions parses every YAML file directly in
.github/workflows/ as a workflow. payload.CONFIG_PATH names it (not imported here); the workflow hands it to the
check as TRUST_CONFIG.
"""

import fnmatch
import re
from dataclasses import dataclass

import yaml

GATE_PATTERNS = ("plan-v*", "data-v*", "results-v*", "v*-submitted")
FROZEN_KEYS = ("always",) + GATE_PATTERNS
BUILTIN_FROZEN = (".github/**",)
ROLES = ("support", "critique")
KNOWN_CHECKS = ("ownership", "tests", "ledger", "audit", "release")


class ConfigError(Exception):
    pass


class _UniqueKeyLoader(yaml.SafeLoader):
    """SafeLoader that refuses a mapping with the same key twice; PyYAML silently keeps the last."""


def _unique_mapping(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            duplicate = key in seen
        except TypeError:
            continue
        if duplicate:
            raise yaml.constructor.ConstructorError(None, None, f"duplicate key {key!r}", key_node.start_mark)
        seen.add(key)
    return loader.construct_mapping(node, deep=deep)


_UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _unique_mapping)


@dataclass(frozen=True)
class Config:
    apps: dict
    required_checks: tuple
    frozen: dict


def _string_list(value, where):
    if not isinstance(value, list) or not all(isinstance(v, str) and v.strip() for v in value):
        raise ConfigError(f"{where} must be a list of non-empty strings")
    return tuple(value)


_PATH_SYNTAX = "path patterns support only *, ** and ? (a directory name freezes everything under it)"


def _path_patterns(value, where):
    """Frozen-path globs, normalized so that a spelling git would accept cannot silently match nothing."""
    patterns = []
    for pattern in _string_list(value, where):
        if any(char in pattern for char in "[]\\"):
            raise ConfigError(f"{where}: {pattern!r} uses unsupported syntax; {_PATH_SYNTAX}")
        normalized = pattern
        while normalized.startswith("./"):
            normalized = normalized[2:]
        normalized = normalized.rstrip("/")
        if normalized.startswith("/"):
            raise ConfigError(f"{where}: {pattern!r} must be relative to the repo root, without a leading /")
        if any(segment in ("", ".", "..") for segment in normalized.split("/")):
            raise ConfigError(f"{where}: {pattern!r} is not a clean relative path (no empty, . or .. segments)")
        patterns.append(normalized)
    return tuple(patterns)


def _apps(value, require_apps):
    apps = {} if value is None else value
    if not (isinstance(apps, dict) and set(apps) <= set(ROLES)
            and all(isinstance(slug, str) and slug.strip() for slug in apps.values())):
        raise ConfigError("apps must map support and critique to non-empty App slugs")
    if require_apps and set(apps) != set(ROLES):
        raise ConfigError("apps must name the support and critique App slugs")
    return dict(apps)


def from_dict(data, *, require_apps=True):
    if not isinstance(data, dict):
        raise ConfigError("trust.yaml must be a mapping")
    unknown = set(data) - {"version", "apps", "required_checks", "frozen"}
    if unknown:
        raise ConfigError(f"unknown keys {sorted(unknown, key=str)}")
    if data.get("version") != 1:
        raise ConfigError("version must be 1")
    apps = _apps(data.get("apps"), require_apps)
    checks = _string_list(data.get("required_checks", []), "required_checks")
    if "ownership" not in checks:
        raise ConfigError("required_checks must include ownership")
    unknown_checks = set(checks) - set(KNOWN_CHECKS)
    if unknown_checks:
        raise ConfigError(f"unknown required checks {sorted(unknown_checks)}")
    frozen_raw = data.get("frozen") or {}
    if not isinstance(frozen_raw, dict):
        raise ConfigError("frozen must map a gate (always, plan-v*, ...) to paths")
    bad = set(frozen_raw) - set(FROZEN_KEYS)
    if bad:
        raise ConfigError(f"frozen has unknown gates {sorted(bad, key=str)}; use {list(FROZEN_KEYS)}")
    frozen = {gate: _path_patterns(paths or [], f"frozen.{gate}") for gate, paths in frozen_raw.items()}
    return Config(apps=apps, required_checks=checks, frozen=frozen)


def parse(text, *, require_apps=True):
    try:
        data = yaml.load(text, Loader=_UniqueKeyLoader)  # a SafeLoader subclass: no Python object tags
    except yaml.YAMLError as err:
        raise ConfigError(f"invalid YAML: {err}") from None
    except RecursionError:
        raise ConfigError("invalid YAML: nested too deeply") from None
    except Exception as err:
        # PyYAML's constructors also let ValueError (2001-13-45), AttributeError (!!timestamp x) and
        # KeyError (!!bool x) escape. Only this one call is in the try, so any failure means unloadable text.
        raise ConfigError(f"invalid YAML: {type(err).__name__}: {err}") from None
    return from_dict(data, require_apps=require_apps)


def load(path, *, require_apps=True):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as err:
        raise ConfigError(f"{path}: {err.strerror}") from None
    except UnicodeDecodeError:
        raise ConfigError(f"{path}: not valid UTF-8") from None
    return parse(text, require_apps=require_apps)


def dump(config):
    return yaml.safe_dump({
        "version": 1,
        "apps": dict(config.apps),
        "required_checks": list(config.required_checks),
        "frozen": {gate: list(paths) for gate, paths in config.frozen.items()},
    }, sort_keys=False)


def _glob_regex(pattern):
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    # The optional "/..." tail is git's directory rule: a pattern naming a directory covers everything under it.
    # DOTALL so that `.*` also covers a file name containing a newline.
    return re.compile("".join(out) + r"(?:/.*)?\Z", re.DOTALL)


def glob_match(pattern, path):
    """git pathspec glob: `*` and `?` stay within one path segment, `**` crosses segments, and a pattern
    that matches a leading directory of `path` matches `path` too."""
    return _glob_regex(pattern).match(path) is not None


def active_frozen(config, tag_names):
    """(pattern, reason) for every path frozen now: built-ins, `always`, and each gate whose tag exists."""
    tag_names = list(tag_names)  # walked once per gate; a generator would be spent after the first
    active = [(pattern, "built in") for pattern in BUILTIN_FROZEN]
    active += [(pattern, "always frozen") for pattern in config.frozen.get("always", ())]
    for gate in GATE_PATTERNS:
        tags = sorted(t for t in tag_names if fnmatch.fnmatchcase(t, gate))
        if tags:
            active += [(pattern, f"frozen by {gate} ({', '.join(tags)})") for pattern in config.frozen.get(gate, ())]
    return active


def frozen_reason(path, active):
    for pattern, reason in active:
        if glob_match(pattern, path):
            return reason
    return None
