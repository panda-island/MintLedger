#!/usr/bin/env python3

import json
import os
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

import jwt


API_ROOT = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.pandaisland.mintledger"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
        },
        Path(os.environ["APP_STORE_CONNECT_KEY_PATH"]).read_text(encoding="utf-8"),
        algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )


AUTH_TOKEN = token()


def api(path: str, query: dict[str, str] | None = None) -> dict:
    url = f"{API_ROOT}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {AUTH_TOKEN}"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def sanitized_lines(log_text: str) -> list[str]:
    interesting = re.compile(
        r"Exception Type|Exception Codes|Termination Reason|Triggered by Thread|Last Exception Backtrace|"
        r"Application Specific Information|Fatal error|MintLedger|AppLock|LocalAuthentication|LAContext|SwiftUI"
    )
    lines = []
    for line in log_text.splitlines():
        if not interesting.search(line):
            continue
        line = re.sub(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", "<UUID>", line)
        line = re.sub(r"0x[0-9A-Fa-f]+", "<ADDRESS>", line)
        lines.append(line[:1200])
    return lines[:160]


def main() -> None:
    apps = api("/apps", {"filter[bundleId]": BUNDLE_ID, "limit": "5"})["data"]
    if not apps:
        raise SystemExit("MintLedger app was not found in App Store Connect")
    app_id = apps[0]["id"]

    submissions = api(
        f"/apps/{app_id}/betaFeedbackCrashSubmissions",
        {
            "sort": "-createdDate",
            "limit": "10",
            "include": "build",
            "fields[betaFeedbackCrashSubmissions]": "createdDate,buildBundleId,appUptimeInMilliseconds,crashLog,build",
            "fields[builds]": "version,uploadedDate",
        },
    )
    builds = {item["id"]: item["attributes"].get("version") for item in submissions.get("included", [])}

    found = False
    for submission in submissions["data"]:
        relationship = submission.get("relationships", {}).get("build", {}).get("data")
        build_number = builds.get(relationship["id"]) if relationship else None
        if build_number not in {"22", "23"}:
            continue
        found = True
        created = submission.get("attributes", {}).get("createdDate", "unknown")
        print(f"=== TestFlight crash: build {build_number}, submitted {created} ===")
        crash = api(
            f"/betaFeedbackCrashSubmissions/{submission['id']}/crashLog",
            {"fields[betaCrashLogs]": "logText"},
        )
        log_text = crash.get("data", {}).get("attributes", {}).get("logText", "")
        lines = sanitized_lines(log_text)
        print("\n".join(lines) if lines else "Crash log contained no matching diagnostic lines")

    if not found:
        print("No TestFlight crash feedback was available yet for builds 22 or 23.")


if __name__ == "__main__":
    main()
