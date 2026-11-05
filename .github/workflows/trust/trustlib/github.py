"""A minimal GitHub REST client on urllib, so the trust tools need no third-party packages.

Copied into each repo by `biostat-trust apply`. Errors name the method and path, never the token.
"""

import http.client
import json
import re
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
_NEXT = re.compile(r'<([^>]+)>;\s*rel="next"')
_TOKEN = re.compile(r"[\x21-\x7e]+")   # printable ASCII, no space: all a header value can safely carry


class GitHubError(Exception):
    def __init__(self, status, method, path, message):
        super().__init__(f"{method} {path}: HTTP {status}: {message}")
        self.status = status


def _inside(api, url):
    """True if `url` is on `api`. Compares up to the slash, so api.github.com.evil.example and
    api.github.com@evil.example do not pass, and neither does an http:// downgrade."""
    return url.startswith(api + "/")


def _refusal(api, method, url):
    return GitHubError(0, method, url, f"refusing to send a request outside {api}")


class _StayOnApi(urllib.request.HTTPRedirectHandler):
    """urllib copies every header, Authorization included, onto a redirect, whatever the new host."""

    def __init__(self, api):
        self.api = api

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _inside(self.api, newurl):
            raise _refusal(self.api, req.get_method(), newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class GitHub:
    """`urlopen` is any callable `(request, timeout=...)`; the default refuses redirects off `api`."""

    def __init__(self, token=None, api=API, urlopen=None):
        # `gh auth token` and files end in a newline. A blank token means none, as None does; any other
        # whitespace or control character is refused, and the message must not echo the token.
        token = (token or "").strip() or None
        if token is not None and not _TOKEN.fullmatch(token):
            raise ValueError("token has whitespace, control or non-ASCII characters in it")
        self.token = token
        self.api = api.rstrip("/")
        self._urlopen = urlopen or urllib.request.build_opener(_StayOnApi(self.api)).open

    def _send(self, method, url, body):
        if not _inside(self.api, url):   # the token goes only to the API, however `url` was built
            raise _refusal(self.api, method, url)
        headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "biostat-trust"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, method=method, headers=headers)
        shown = url.removeprefix(self.api)
        refused = None
        try:
            with self._urlopen(request, timeout=30) as response:
                raw = response.read()
                link = response.headers.get("Link", "")
                status = getattr(response, "status", None) or 200
        except urllib.error.HTTPError as err:
            try:
                detail = err.read().decode(errors="replace")
            except (OSError, http.client.HTTPException):   # a truncated error body still has a status
                detail = str(err.reason)
            try:
                detail = json.loads(detail).get("message", detail)
            except (ValueError, AttributeError, RecursionError):
                pass
            raise GitHubError(err.code, method, shown, detail) from None
        except urllib.error.URLError as err:
            raise GitHubError(0, method, shown, str(err.reason)) from None
        except (OSError, http.client.HTTPException) as err:   # a timeout, reset or short read, in connect or read()
            raise GitHubError(0, method, shown, str(err) or type(err).__name__) from None
        except ValueError as err:   # http.client.putheader's message quotes the header value, the token with it
            refused = type(err).__name__
        if refused:   # raised outside the handler, so the original exception is not chained to this one
            raise GitHubError(0, method, shown, f"request failed ({refused}); details withheld, "
                                                "they can quote request headers")
        try:
            value = json.loads(raw.decode("utf-8")) if raw else None
        except UnicodeDecodeError:
            raise GitHubError(status, method, shown, "response body is not UTF-8") from None
        except (ValueError, RecursionError):
            raise GitHubError(status, method, shown, "response body is not JSON") from None
        return value, link, status

    def request(self, method, path, body=None, params=None):
        url = path if path.startswith("http") else self.api + path
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        return self._send(method, url, body)[0]

    def get(self, path, params=None):
        return self.request("GET", path, params=params)

    def post(self, path, body=None):
        return self.request("POST", path, body)

    def put(self, path, body=None):
        return self.request("PUT", path, body)

    def patch(self, path, body=None):
        return self.request("PATCH", path, body)

    def paginate(self, path, params=None, key=None):
        query = dict(params or {})
        query.setdefault("per_page", 100)
        url = f"{self.api}{path}?{urllib.parse.urlencode(query)}"
        items = []
        while url:
            data, link, status = self._send("GET", url, None)
            page = (data.get(key) if isinstance(data, dict) else None) if key else data
            if not isinstance(page, list):
                where = f" under {key!r}" if key else ""
                raise GitHubError(status, "GET", url.removeprefix(self.api),
                                  f"expected a list{where}, got {type(page).__name__}")
            items += page
            match = _NEXT.search(link or "")
            url = match.group(1) if match else None
        return items
