"""Inspect only Clip installation and redacted CloudKit status on booted simulators."""
import collections
import json
import pathlib
import plistlib
import re
import sqlite3
import subprocess

BUNDLE = "com.ioant.clip.ios"
DAILY = "ioant-Note"
REVIEW = "ioant-Clip-CloudKit-UI-Review"
LEGACY_REVIEW = "ioant-Clip-CloudKit-Review"
EXPECTED = "614FDA13-6198-452B-A6B2-94AA5591B30A"


def sim(*args, timeout=20):
    return subprocess.run(
        ["/usr/bin/xcrun", "simctl", *args],
        capture_output=True, text=True, timeout=timeout, check=True
    ).stdout.strip()


def summary(path):
    database = path / "notes.sqlite3"
    if database.is_file():
        with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
            connection.execute("BEGIN")
            count = connection.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
            revisions = connection.execute("SELECT COUNT(*) FROM revisions").fetchone()[0]
            row = connection.execute("SELECT payload FROM library_state WHERE key='enrollment'").fetchone()
            enrollment = json.loads(row[0]) if row else None
    elif (path / "notes.json").is_file():
        value = json.loads((path / "notes.json").read_bytes())
        count = len(value.get("notes", []))
        records = value.get("syncJournal", {}).get("revisions", [])
        revisions = len(records) // 2 if isinstance(records, list) else len(records)
        enrollment = value.get("syncEnrollment")
    else:
        return None, None
    return {
        "notes": count, "revisions": revisions, "bound": bool(enrollment),
        "paused": enrollment.get("isPaused", False) if enrollment else None,
        "checkpoint": (path / "cloudkit-remote-checkpoint-v1.json").is_file()
    }, enrollment


def cloud_errors(udid, process):
    if not re.fullmatch(r"[A-Za-z0-9-]+", process):
        return
    predicate = (
        f'(process == "{process}" AND (subsystem CONTAINS[c] "cloudkit" OR eventMessage CONTAINS[c] "CKError")) '
        'OR ((process == "cloudd" OR process == "accountsd") AND eventMessage CONTAINS[c] "ioant.clip")'
    )
    try:
        raw = sim("spawn", udid, "log", "show", "--last", "40m", "--style", "json",
                  "--predicate", predicate, timeout=22)
        records = json.loads(raw)
    except (subprocess.SubprocessError, ValueError):
        print("CloudKit unified logs unavailable", flush=True)
        return
    codes = collections.Counter()
    categories = collections.Counter()
    for record in records:
        message = record.get("eventMessage", "")
        for code in re.findall(r"(?:CKErrorDomain|CKInternalErrorDomain)\s*(?:Code\s*=\s*|:?\s+)(\d{1,5})\b", message):
            codes[code] += 1
        for category, pattern in {
            "authentication": r"not authenticated|authentication failed|not signed in|missing auth token|no account|noaccount|invalid auth token",
            "entitlement": r"missing entitlement|not entitled|bad container|badcontainer|invalid container|permission failure",
            "network": r"network (?:is )?(?:unavailable|failure)|not connected to the internet|connection was lost|timed out",
            "temporarily_unavailable": r"temporarily unavailable|temporarilyUnavailable|service unavailable",
            "success": r"operation (?:finished|completed) successfully|finished with no error",
        }.items():
            if re.search(pattern, message, flags=re.I):
                categories[category] += 1
    print("Redacted CloudKit logs:", len(records), "events; numeric error codes", dict(codes),
          "classifications", dict(categories), flush=True)


library = pathlib.Path("Library/Application Support")
mac, mac_binding = summary(pathlib.Path.home() / library / DAILY)
print("Mac daily storage:", mac, flush=True)
booted = [d for items in json.loads(sim("list", "-j", "devices", "booted"))["devices"].values()
          for d in items if d["state"] == "Booted"]
print("Booted Simulators:", len(booted), flush=True)
for index, device in enumerate(booted, 1):
    udid = device["udid"]
    try:
        app = pathlib.Path(sim("get_app_container", udid, BUNDLE, "app"))
        data = pathlib.Path(sim("get_app_container", udid, BUNDLE, "data"))
        info = plistlib.loads((app / "Info.plist").read_bytes())
    except (subprocess.SubprocessError, OSError):
        print("Simulator", index, "Clip not resolved; expected device:", udid == EXPECTED, flush=True)
        continue
    active = any(BUNDLE in line and line.split()[0].isdigit()
                 for line in sim("spawn", udid, "launchctl", "list").splitlines())
    lane = DAILY if info.get("ClipCloudKitDevelopment") == "YES" else (
        REVIEW if info.get("ClipCloudKitUIReview") == "YES" else LEGACY_REVIEW
    )
    status, binding = summary(data / library / lane)
    same = bool(mac_binding and binding and mac_binding.get("account") == binding.get("account"))
    print("Simulator", index, "expected device:", udid == EXPECTED, "Clip running:", active, "storage:", lane,
          "cloud configuration:", info.get("ClipCloudKitEnvironment") == "Development",
          "state:", status, "same binding as Mac:", same, flush=True)
    if active:
        cloud_errors(udid, info["CFBundleExecutable"])
