"""Refresh the bundled fake provisioning profiles.

The profiles shipped with the upstream repository are real Apple provisioning
profiles whose ExpirationDate has passed, which makes Bazel's plisttool fail
with:

    ERROR: On target "...", provisioning profile ExpirationDate ("...") is in
    the past.

`rules_apple`'s provisioning_profile_tool accepts a plain XML plist in place of
a CMS-signed profile -- see the "Back door for testing" branch in
tools/provisioning_profile_tool/provisioning_profile_tool.py:

    content = open(profile_path, mode='rb').read()
    if content.startswith(b'<?xml'):
        return content

Nothing on this build path verifies the CMS signature: the tool only extracts
the embedded plist, and plisttool only reads the metadata derived from it. So
we rewrite the embedded plist with a future ExpirationDate and drop the CMS
wrapper. Everything else (entitlements, team id, UUID, TimeToLive) is carried
over byte for byte, so plisttool's entitlement checks keep passing.

This is idempotent: a profile that is already plain XML with a future expiry is
left untouched.

Usage:
    python3 refresh_profiles.py <directory containing *.mobileprovision>
"""

import datetime
import glob
import os
import plistlib
import sys

XML_START = b"<?xml"
XML_END = b"</plist>"

# The originals expired 2026-10-30.
NEW_EXPIRATION_DATE = datetime.datetime(2036, 10, 30, 12, 0, 0)
NEW_CREATION_DATE = datetime.datetime(2026, 1, 1, 0, 0, 0)

# provisioning_profile_tool._write_metadata indexes the profile with exactly
# these keys, so dropping one would turn into a KeyError during the build.
REQUIRED_KEYS = (
    "AppIDName",
    "ApplicationIdentifierPrefix",
    "CreationDate",
    "Platform",
    "Entitlements",
    "ExpirationDate",
    "Name",
    "TeamIdentifier",
    "TeamName",
    "TimeToLive",
    "UUID",
    "Version",
)


def embedded_plist(data, path):
    """Return the XML plist bytes carried by a profile (CMS or plain XML)."""
    if data.startswith(XML_START):
        return data
    start = data.find(XML_START)
    end = data.find(XML_END)
    if start < 0 or end < 0:
        raise RuntimeError("no embedded plist found in {}".format(path))
    return data[start:end + len(XML_END)]


def refresh(path):
    data = open(path, "rb").read()
    profile = plistlib.loads(embedded_plist(data, path))

    missing = [key for key in REQUIRED_KEYS if key not in profile]
    if missing:
        raise RuntimeError("{} is missing keys: {}".format(path, ", ".join(missing)))

    if data.startswith(XML_START) and profile.get("ExpirationDate", NEW_EXPIRATION_DATE) > datetime.datetime.now():
        print("  {}: already refreshed, left alone".format(os.path.basename(path)))
        return

    profile["ExpirationDate"] = NEW_EXPIRATION_DATE
    profile["CreationDate"] = NEW_CREATION_DATE

    out = plistlib.dumps(profile, fmt=plistlib.FMT_XML, sort_keys=False)

    # Never write something the build tools cannot read back.
    if not out.startswith(XML_START):
        raise RuntimeError("refusing to write {}: output is not an XML plist".format(path))
    if plistlib.loads(out) != profile:
        raise RuntimeError("refusing to write {}: round-trip mismatch".format(path))

    with open(path, "wb") as handle:
        handle.write(out)
    print("  {}: {} -> {} bytes, expires {}".format(
        os.path.basename(path), len(data), len(out), NEW_EXPIRATION_DATE.date()))


def main(directory):
    paths = sorted(glob.glob(os.path.join(directory, "*.mobileprovision")))
    if not paths:
        print("no *.mobileprovision files in {}".format(directory))
        return 1
    for path in paths:
        refresh(path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
