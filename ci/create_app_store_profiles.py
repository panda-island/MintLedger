#!/usr/bin/env python3

import base64
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes


API_ROOT = "https://api.appstoreconnect.apple.com/v1"
PROFILE_SPECS = {
    "APP_PROFILE_NAME": ("com.pandaisland.mintledger", "MintLedger App Store"),
    "WIDGET_PROFILE_NAME": ("com.pandaisland.mintledger.widget", "MintLedger Widget App Store"),
    "WATCH_PROFILE_NAME": ("com.pandaisland.mintledger.watchkitapp", "MintLedger Watch App Store"),
}


def token() -> str:
    key_path = Path(os.environ["APP_STORE_CONNECT_KEY_PATH"])
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key_path.read_text(encoding="utf-8"),
        algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )


AUTH_TOKEN = token()


def api(method: str, path: str, *, query: dict[str, str] | None = None, payload: dict | None = None) -> dict:
    url = f"{API_ROOT}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"Authorization": f"Bearer {AUTH_TOKEN}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        print(f"App Store Connect API {method} {path} failed ({error.code}): {details}", file=sys.stderr)
        raise


def matching_certificate_id() -> str:
    local_cert = x509.load_pem_x509_certificate(Path(os.environ["LOCAL_DISTRIBUTION_CERTIFICATE_PATH"]).read_bytes())
    local_fingerprint = local_cert.fingerprint(hashes.SHA256())
    certificates = api("GET", "/certificates", query={"limit": "200"})["data"]
    for certificate in certificates:
        content = certificate["attributes"].get("certificateContent")
        if not content:
            continue
        remote_cert = x509.load_der_x509_certificate(base64.b64decode(content))
        if remote_cert.fingerprint(hashes.SHA256()) == local_fingerprint:
            return certificate["id"]
    raise RuntimeError("The imported Apple Distribution certificate was not found in the developer account")


def bundle_id_resource(identifier: str, display_name: str) -> dict:
    result = api("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": "200"})["data"]
    exact_match = next((item for item in result if item["attributes"]["identifier"] == identifier), None)
    if exact_match:
        return exact_match
    return api(
        "POST",
        "/bundleIds",
        payload={
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": identifier, "name": display_name, "platform": "IOS"},
            }
        },
    )["data"]


def create_profile(bundle_id: dict, certificate_id: str, base_name: str) -> dict:
    unique_name = f"{base_name} {int(time.time())}"
    return api(
        "POST",
        "/profiles",
        payload={
            "data": {
                "type": "profiles",
                "attributes": {"name": unique_name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id["id"]}},
                    "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
                },
            }
        },
    )["data"]


def install_profile(profile: dict, env_name: str) -> None:
    raw_path = Path(os.environ["RUNNER_TEMP"]) / f"{env_name.lower()}.mobileprovision"
    raw_path.write_bytes(base64.b64decode(profile["attributes"]["profileContent"]))
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", str(raw_path)])
    properties = plistlib.loads(decoded)
    profile_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    profile_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(raw_path, profile_dir / f"{properties['UUID']}.mobileprovision")
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as environment:
        environment.write(f"{env_name}={properties['Name']}\n")
    print(f"Installed {properties['Name']} ({properties['UUID']})")


def main() -> None:
    certificate_id = matching_certificate_id()
    for env_name, (identifier, display_name) in PROFILE_SPECS.items():
        bundle_id = bundle_id_resource(identifier, display_name)
        profile = create_profile(bundle_id, certificate_id, display_name)
        install_profile(profile, env_name)


if __name__ == "__main__":
    main()
