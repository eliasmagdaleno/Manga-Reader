#!/usr/bin/env python3
"""Mint a MyAnimeList access token for `scripts/mal_live_write.py`.

The app holds its own token in the simulator keychain, which is not readable from
a shell. This runs the same OAuth2 flow by hand and prints a token you can export:

    scripts/mal_oauth_token.py

It opens MAL's approval page, waits for you to paste the redirect back, and
exchanges it. The client id comes from `Secrets.xcconfig`, so the token belongs to
the same registered app the simulator signs in as.

MAL is a *public* client here: there is no client secret, and PKCE is what stands
in for one. MAL documents only `plain`, so the challenge is the verifier verbatim
(see `MALOAuth.swift:14`) — that is MAL's constraint, not a shortcut taken here.

The token is printed, never written to disk: it is account credentials, and the
one place it belongs is the environment of the run that needs it. It lasts about
a month; re-run this when `mal_live_write.py` starts reporting 401.
"""

import argparse
import base64
import os
import pathlib
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

AUTHORIZE = "https://myanimelist.net/v1/oauth2/authorize"
TOKEN = "https://myanimelist.net/v1/oauth2/token"
# Must match the app's registration exactly; MAL compares it verbatim.
REDIRECT = "mangareader://oauth/mal"
SECRETS = pathlib.Path(__file__).resolve().parent.parent / "Secrets.xcconfig"


def client_id() -> str:
    from_env = os.environ.get("MAL_CLIENT_ID")
    if from_env:
        return from_env.strip()
    if not SECRETS.exists():
        sys.exit(
            f"no MAL_CLIENT_ID in the environment and no {SECRETS.name} to read it from. "
            "Secrets.xcconfig is gitignored, so it exists only in your main checkout — run this "
            "from there, or pass MAL_CLIENT_ID=... explicitly."
        )
    for line in SECRETS.read_text().splitlines():
        match = re.match(r"\s*MAL_CLIENT_ID\s*=\s*(\S+)", line)
        if match:
            return match.group(1)
    sys.exit(f"{SECRETS.name} has no MAL_CLIENT_ID line")


def verifier() -> str:
    # 43-128 unreserved characters. MAL's `plain` method sends this same string as
    # the challenge, so it is the only secret binding the redirect to this process.
    return base64.urlsafe_b64encode(secrets.token_bytes(64)).decode().rstrip("=")


def authorize_url(cid: str, code_verifier: str, state: str) -> str:
    query = urllib.parse.urlencode({
        "response_type": "code",
        "client_id": cid,
        "code_challenge": code_verifier,
        "code_challenge_method": "plain",
        "redirect_uri": REDIRECT,
        "state": state,
    })
    return f"{AUTHORIZE}?{query}"


def code_from(reply: str, state: str) -> str:
    """Accept either the whole redirect URL or a bare code."""
    reply = reply.strip()
    if not reply:
        sys.exit("nothing pasted")
    # Decide on URL-ness, not on the presence of `code=`: a refusal comes back as
    # `...?error=access_denied` with no code at all, and testing for the code first
    # would hand that whole URL back as if it were one.
    if "?" not in reply:
        return reply
    query = urllib.parse.urlparse(reply).query
    params = urllib.parse.parse_qs(query)
    if "error" in params:
        sys.exit(f"MAL refused the authorization: {params['error'][0]}")
    # The redirect is the one place an attacker-supplied code could be swapped in,
    # so the state that came back has to be the state that went out.
    got = params.get("state", [None])[0]
    if got != state:
        sys.exit(
            "state mismatch: this redirect did not come from the request just made. "
            "Start over rather than exchanging it."
        )
    return params["code"][0]


def exchange(cid: str, code: str, code_verifier: str) -> dict:
    form = urllib.parse.urlencode({
        "client_id": cid,
        "code": code,
        "code_verifier": code_verifier,
        "grant_type": "authorization_code",
        "redirect_uri": REDIRECT,
    }).encode()
    request = urllib.request.Request(TOKEN, data=form, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(request) as response:
            import json
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        sys.exit(f"token exchange failed: {error.code} {error.read().decode(errors='replace')}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-browser", action="store_true",
                        help="print the URL instead of opening it")
    args = parser.parse_args()

    cid = client_id()
    code_verifier = verifier()
    state = secrets.token_urlsafe(16)
    url = authorize_url(cid, code_verifier, state)

    print("1. Approve the app on MAL:\n")
    print(f"   {url}\n")
    if not args.no_browser:
        webbrowser.open(url)

    print("2. The browser will then try to open `mangareader://oauth/mal?...` and fail —")
    print("   that is expected, nothing is listening outside the simulator. Copy that URL")
    print("   from the address bar (or just the `code=` value) and paste it here.\n")

    try:
        reply = input("redirect URL or code: ")
    except (EOFError, KeyboardInterrupt):
        print()
        return 1

    payload = exchange(cid, code_from(reply, state), code_verifier)
    token = payload["access_token"]
    expires_days = payload.get("expires_in", 0) / 86400

    print(f"\nToken minted, good for about {expires_days:.0f} days. Export it:\n")
    print(f"   export MAL_ACCESS_TOKEN={token}\n")
    print("Then: scripts/mal_live_write.py fire")
    print("\nThis grants write access to your MAL list. It was printed, not saved —")
    print("clear your scrollback if that matters to you.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
