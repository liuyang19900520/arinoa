#!/usr/bin/env python3
"""Submit an already-uploaded TestFlight build of Arinoa to App Store review.

Uses the App Store Connect API directly. Steps:
  1. find (or create) the App Store version VERSION
  2. pick build BUILD (or the newest VALID build of VERSION) and attach it
  3. set "What's New" per locale from submissions/<VERSION>/<lang>/whats-new.txt
  4. set review notes from submissions/<VERSION>/review-notes.txt
  5. create a reviewSubmission, add the version, and submit it

With DRY_RUN=true only GET requests are made; every write is printed instead.
Anything missing (screenshots, privacy answers, ...) is reported by Apple when
submitting; the script prints Apple's error text and stops rather than guessing.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8 written by write-asc-key.sh),
     VERSION, BUILD (optional), RELEASE_TYPE (manual|automatic), DRY_RUN.
Needs: pip install pyjwt cryptography requests
"""
import os
import sys
import time
from pathlib import Path

import jwt
import requests

# App Store Apple ID of Arinoa. Found in docs/appstore-submission (submissions/1.0/README.md) and
# ci/asc-submit (scripts/ci/asc_lib.py) on origin; Yang: confirm it in App Store Connect > App Information.
APP_ID = os.environ.get("APP_ID", "").strip() or "6827531369"
API = "https://api.appstoreconnect.apple.com/v1"
# submissions/<version>/<folder>  ->  App Store Connect locale
LOCALES = {"en": "en-US", "ja": "ja", "zh-Hans": "zh-Hans"}

VERSION = os.environ["VERSION"].strip()
BUILD = os.environ.get("BUILD", "").strip()
RELEASE_TYPE = os.environ.get("RELEASE_TYPE", "manual").strip()
DRY_RUN = os.environ.get("DRY_RUN", "true").strip().lower() == "true"
SUBMISSION_DIR = Path("submissions") / VERSION


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def token():
    key = Path(os.environ["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


SESSION = requests.Session()
SESSION.headers["Authorization"] = f"Bearer {token()}"


def call(method, path, body=None, params=None):
    """One API call. Writes are skipped (and printed) in dry-run mode."""
    if method != "GET" and DRY_RUN:
        print(f"[dry run] would {method} {path}: {body}")
        return {"data": {"id": "DRY-RUN", "attributes": {}}}
    r = SESSION.request(method, API + path, json=body, params=params)
    if r.status_code >= 400:
        try:
            errs = r.json().get("errors", [])
        except ValueError:
            errs = [{"detail": r.text}]
        print(f"::error::{method} {path} failed ({r.status_code}):")
        for e in errs:
            print(f"  - {e.get('title', '')}: {e.get('detail', '')}")
            # Submission blockers (missing screenshots etc.) come as associated errors.
            for assoc in (e.get("meta", {}).get("associatedErrors") or {}).values():
                for a in assoc:
                    print(f"      * {a.get('detail', a)}")
        sys.exit(1)
    return r.json() if r.content else {}


def read(path):
    return path.read_text().strip() if path.is_file() else None


def main():
    mode = "DRY RUN (read-only)" if DRY_RUN else "LIVE"
    print(f"==> {mode}: version {VERSION}, build {BUILD or 'latest valid'}, release {RELEASE_TYPE}")
    if RELEASE_TYPE not in ("manual", "automatic"):
        fail("release_type must be manual or automatic")

    # 1. App Store version
    found = call("GET", f"/apps/{APP_ID}/appStoreVersions",
                 params={"filter[versionString]": VERSION, "filter[platform]": "IOS"})["data"]
    if found:
        ver = found[0]
        state = ver["attributes"].get("appStoreState")
        print(f"==> Found version {VERSION} (state {state})")
        if state not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                         "METADATA_REJECTED"):
            fail(f"Version {VERSION} is {state}; it can't be submitted again.")
        call("PATCH", f"/appStoreVersions/{ver['id']}", {"data": {
            "type": "appStoreVersions", "id": ver["id"],
            "attributes": {"releaseType": "MANUAL" if RELEASE_TYPE == "manual" else "AFTER_APPROVAL"}}})
    else:
        print(f"==> Version {VERSION} doesn't exist yet; creating it")
        ver = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": VERSION,
                           "releaseType": "MANUAL" if RELEASE_TYPE == "manual" else "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    vid = ver["id"]

    # 2. Build
    params = {"filter[app]": APP_ID, "filter[preReleaseVersion.version]": VERSION,
              "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 1}
    if BUILD:
        params["filter[version]"] = BUILD
    builds = call("GET", "/builds", params=params)["data"]
    if not builds:
        fail(f"No VALID (processed) build {BUILD or ''} of version {VERSION}. Wait for processing in TestFlight.")
    build = builds[0]
    print(f"==> Using build {build['attributes']['version']} (id {build['id']})")
    if build["attributes"].get("usesNonExemptEncryption") is None:
        print("::warning::Export compliance not answered for this build; Apple may block the submission.")
    call("PATCH", f"/appStoreVersions/{vid}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}})

    # 3. What's New per locale (only locales that already exist on the version)
    if not SUBMISSION_DIR.is_dir():
        print(f"::warning::{SUBMISSION_DIR} not found; leaving metadata as it is in App Store Connect.")
    locs = [] if vid == "DRY-RUN" else call(
        "GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    by_locale = {l["attributes"]["locale"]: l for l in locs}
    for folder, locale in LOCALES.items():
        text = read(SUBMISSION_DIR / folder / "whats-new.txt")
        if not text:
            continue
        if len(text) > 4000:
            fail(f"{folder}/whats-new.txt is over 4000 characters")
        loc = by_locale.get(locale)
        if not loc:
            print(f"::warning::Locale {locale} isn't set up on the version; skipping its What's New.")
            continue
        print(f"==> What's New for {locale}: {len(text)} chars")
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"],
            "attributes": {"whatsNew": text}}})

    # 4. Review notes
    notes = read(SUBMISSION_DIR / "review-notes.txt")
    if notes:
        print(f"==> Review notes: {len(notes)} chars")
        detail = None if vid == "DRY-RUN" else call(
            "GET", f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
        if detail:
            call("PATCH", f"/appStoreReviewDetails/{detail['id']}", {"data": {
                "type": "appStoreReviewDetails", "id": detail["id"],
                "attributes": {"notes": notes}}})
        else:
            # A brand-new version has no review detail yet; contact info is
            # copied from the previous version by Apple only in the web UI,
            # so missing contact fields will be reported at submission.
            call("POST", "/appStoreReviewDetails", {"data": {
                "type": "appStoreReviewDetails", "attributes": {"notes": notes},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})

    # 5. Submit for review
    open_subs = call("GET", "/reviewSubmissions", params={
        "filter[app]": APP_ID, "filter[platform]": "IOS",
        "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"})["data"]
    if any(s["attributes"]["state"] in ("WAITING_FOR_REVIEW", "IN_REVIEW") for s in open_subs):
        fail("Another submission is already waiting for or in review.")
    sub = next((s for s in open_subs if s["attributes"]["state"] == "READY_FOR_REVIEW"), None)
    if sub:
        print(f"==> Reusing draft review submission {sub['id']}")
    else:
        sub = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    # Adding the version is where Apple reports missing screenshots, privacy, etc.
    call("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {
        "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})

    print("==> Dry run finished; nothing was changed." if DRY_RUN
          else f"==> Submitted {VERSION} ({build['attributes']['version']}) for review.")


if __name__ == "__main__":
    main()
