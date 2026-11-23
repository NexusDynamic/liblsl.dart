#!/usr/bin/env python3
"""Upload a liblsl release to Zenodo as a new version of the concept record.

Usage: zenodo_release.py <version> <archive>

The record comes from the top-level `doi:` of CITATION.cff: the concept
("all versions") DOI, or the DOI of any of its versions. Nothing has to be
updated between releases. Each run:

  1. finds the latest published version of the concept;
  2. stops if that is already <version> (a rerun after publishing);
  3. opens a new-version draft, or reuses the open one (a rerun before
     publishing), and removes the files it inherited;
  4. uploads <archive> and sets the metadata from .zenodo.json;
  5. publishes, when ZENODO_PUBLISH is "true"; otherwise leaves the draft.

Environment: ZENODO_TOKEN (scopes deposit:write and deposit:actions),
ZENODO_PUBLISH (optional), GITHUB_OUTPUT (optional).
"""

import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = "https://zenodo.org/api"
TOKEN = os.environ["ZENODO_TOKEN"]


def request(method, url, data=None, content_type="application/json", auth=True):
    headers = {"Accept": "application/json"}
    if auth:
        headers["Authorization"] = f"Bearer {TOKEN}"
    if data is not None:
        headers["Content-Type"] = content_type
        if content_type == "application/json":
            data = json.dumps(data).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"::error::{method} {url} failed: HTTP {e.code} {e.read().decode(errors='replace')}")
    return json.loads(body) if body else None


def citation_doi_id():
    with open("CITATION.cff") as f:
        match = re.search(r'^doi:\s*"?10\.5281/zenodo\.(\d+)"?\s*$', f.read(), re.M)
    if not match:
        sys.exit("::error::No top-level Zenodo concept DOI (doi: 10.5281/zenodo.N) in CITATION.cff")
    return match.group(1)


def open_draft(latest_id, concept):
    """The new-version draft of the concept, created if there is none."""
    try:
        deposit = request("POST", f"{API}/deposit/depositions/{latest_id}/actions/newversion")
        return request("GET", deposit["links"]["latest_draft"])
    except SystemExit:
        # Zenodo refuses a second new version while one is open: find that one.
        drafts = request("GET", f"{API}/deposit/depositions?status=draft&size=100")
        for draft in drafts:
            if str(draft.get("conceptrecid")) == concept:
                print(f"Reusing open draft {draft['id']}")
                return request("GET", draft["links"]["self"])
        raise


def main():
    version, archive = sys.argv[1], sys.argv[2]
    with open(".zenodo.json") as f:
        meta = json.load(f)
    if meta.get("version") != version:
        sys.exit(f"::error::.zenodo.json has version {meta.get('version')}, expected {version}")
    # The DOI may also be one of a version (as in older tags): either way
    # the record names its concept, and /records/<concept> redirects to the
    # latest published version.
    concept = str(request("GET", f"{API}/records/{citation_doi_id()}", auth=False)["conceptrecid"])
    latest = request("GET", f"{API}/records/{concept}", auth=False)
    print(f"Concept {concept}: latest published is {latest['id']} (version {latest['metadata'].get('version')})")
    if latest["metadata"].get("version") == version:
        print(f"Version {version} is already published: {latest['links']['self_html']}")
        write_outputs(latest["id"], latest["doi"], "published (already)")
        return

    draft = open_draft(latest["id"], concept)
    draft_id = draft["id"]
    print(f"Draft {draft_id}, reserved DOI {draft['metadata'].get('prereserve_doi', {}).get('doi')}")

    for f in draft.get("files", []):
        print(f"Removing inherited file {f['filename']}")
        request("DELETE", f"{API}/deposit/depositions/{draft_id}/files/{f['id']}")

    name = os.path.basename(archive)
    print(f"Uploading {name}…")
    with open(archive, "rb") as f:
        request("PUT", f"{draft['links']['bucket']}/{name}", f.read(), "application/octet-stream")

    meta["publication_date"] = datetime.date.today().isoformat()
    draft = request("PUT", f"{API}/deposit/depositions/{draft_id}", {"metadata": meta})
    doi = draft["metadata"].get("prereserve_doi", {}).get("doi") or draft.get("doi")

    if os.environ.get("ZENODO_PUBLISH") == "true":
        draft = request("POST", f"{API}/deposit/depositions/{draft_id}/actions/publish")
        print(f"Published {draft['doi']}")
        write_outputs(draft_id, draft["doi"], "published")
    else:
        print(f"Draft ready for review, DOI {doi} on publishing")
        write_outputs(draft_id, doi, "draft")


def write_outputs(record_id, doi, state):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            f.write(f"id={record_id}\ndoi={doi}\nstate={state}\n")


if __name__ == "__main__":
    main()
