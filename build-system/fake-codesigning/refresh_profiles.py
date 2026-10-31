#!/usr/bin/env python3
"""Re-sign the bundled fake provisioning profiles with a future ExpirationDate.

Why this exists
---------------
`build-system/fake-codesigning/profiles/*.mobileprovision` are Apple-issued
profiles (team C67CF9S4VU, TimeToLive 360 days) whose ExpirationDate passed on
2026-10-30. Two independent consumers then break:

  * build-system/Make/BuildConfiguration.py decodes every profile with
    `openssl smime -inform der -verify -noverify ...` and passes
    check_result=True, so the files must stay real CMS blobs -- a plain XML
    plist is rejected outright;
  * rules_apple's plisttool aborts the build with
    "provisioning profile ExpirationDate (...) is in the past".

The profiles therefore cannot just be re-dated in place: changing the plist
invalidates the CMS signature. They are decoded, re-dated, and re-signed with
the bundled `certs/SelfSigned.p12`, which is exactly the flow
build-system/Make/GenerateProfiles.py uses -- and the identity every existing
`DeveloperCertificates` entry already carries.

This is idempotent: a profile that is already CMS-signed with a future expiry
is left untouched.

macOS only (`security`, `openssl`).

Usage:
    python3 refresh_profiles.py [--check] <build-system/fake-codesigning>
"""

import argparse
import datetime
import glob
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

XML_START = b"<?xml"
XML_END = b"</plist>"

KEYCHAIN_NAME = "starforge-profiles.keychain"
KEYCHAIN_PASSWORD = "starforge"

# certs/SelfSigned.p12 is valid until 2030-10-29, so date the profiles just
# inside it. plisttool only rejects dates that are already in the past.
NEW_EXPIRATION_DATE = datetime.datetime(2030, 10, 28, 12, 0, 0)
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


def log(message):
    print(message, flush=True)


def run(command, check=True):
    proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "command failed (exit {}): {}\n  stdout: {}\n  stderr: {}".format(
                proc.returncode,
                " ".join(command),
                proc.stdout.decode("utf-8", "replace").strip(),
                proc.stderr.decode("utf-8", "replace").strip(),
            )
        )
    return proc


def security(arguments, check=True):
    return run(["security"] + arguments, check=check)


def read_plist_bytes(path):
    """Return the XML plist carried by a profile (plain XML or CMS)."""
    data = open(path, "rb").read()
    if data.startswith(XML_START):
        return data

    attempts = []
    for command in (
        ["security", "cms", "-D", "-i", path],
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
    ):
        proc = run(command, check=False)
        if proc.returncode == 0 and proc.stdout.startswith(XML_START):
            return proc.stdout
        attempts.append(
            "{} -> exit {}: {}".format(
                command[0], proc.returncode, proc.stderr.decode("utf-8", "replace").strip()
            )
        )
    raise RuntimeError("cannot read a plist out of {}\n  {}".format(path, "\n  ".join(attempts)))


def setup_keychain(p12_path):
    security(["delete-keychain", KEYCHAIN_NAME], check=False)
    security(["create-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN_NAME])

    search_list = [
        line.strip().strip('"')
        for line in security(["list-keychains", "-d", "user"]).stdout.decode().splitlines()
        if line.strip()
    ]
    security(["list-keychains", "-d", "user", "-s", KEYCHAIN_NAME] + search_list)

    security(["set-keychain-settings", KEYCHAIN_NAME])
    security(["unlock-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN_NAME])
    security([
        "import", p12_path, "-k", KEYCHAIN_NAME, "-P", "",
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security",
    ])
    security([
        "set-key-partition-list", "-S", "apple-tool:,apple:",
        "-k", KEYCHAIN_PASSWORD, KEYCHAIN_NAME,
    ])


def cleanup_keychain():
    security(["delete-keychain", KEYCHAIN_NAME], check=False)


def find_identity():
    proc = security(["find-identity", "-v", "-p", "codesigning", KEYCHAIN_NAME], check=False)
    text = proc.stdout.decode("utf-8", "replace")
    identities = [line.split('"')[1] for line in text.splitlines() if '"' in line]
    if not identities:
        raise RuntimeError("no codesigning identity in {}:\n{}".format(KEYCHAIN_NAME, text.strip()))
    return identities[0]


def sign_with_security(plist_path, output_path):
    security(["cms", "-S", "-k", KEYCHAIN_NAME, "-N", _identity, "-i", plist_path, "-o", output_path])


def sign_with_openssl(p12_path, plist_path, output_path, workdir):
    pem_path = os.path.join(workdir, "signer.pem")
    run([
        "openssl", "pkcs12", "-in", p12_path, "-passin", "pass:", "-nodes", "-out", pem_path,
    ])
    run([
        "openssl", "smime", "-sign", "-binary", "-nodetach",
        "-in", plist_path, "-signer", pem_path, "-inkey", pem_path,
        "-outform", "der", "-out", output_path,
    ])


def verify_signed(path, expected_entitlements):
    """Decode the way BuildConfiguration.py does, then re-check the plist."""
    proc = run(["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path])
    profile = plistlib.loads(proc.stdout)

    expiration = profile.get("ExpirationDate")
    if not expiration or expiration < datetime.datetime.now():
        raise RuntimeError("still expired: {}".format(expiration))
    if profile.get("Entitlements") != expected_entitlements:
        raise RuntimeError("entitlements changed while re-signing")
    if not security(["cms", "-D", "-i", path], check=False).stdout.startswith(XML_START):
        raise RuntimeError("security cms -D cannot decode the result")

    missing = [key for key in REQUIRED_KEYS if key not in profile]
    if missing:
        raise RuntimeError("missing keys after signing: {}".format(", ".join(missing)))
    return expiration


def refresh(path, p12_path, workdir):
    name = os.path.basename(path)
    raw = open(path, "rb").read()
    profile = plistlib.loads(read_plist_bytes(path))

    missing = [key for key in REQUIRED_KEYS if key not in profile]
    if missing:
        raise RuntimeError("{} is missing keys: {}".format(path, ", ".join(missing)))

    expiration = profile.get("ExpirationDate")
    if not raw.startswith(XML_START) and expiration and expiration > datetime.datetime.now():
        log("  {}: already signed, expires {}, skipped".format(name, expiration))
        return False

    log("  {}: signing (was {}, expiring {})".format(
        name, "CMS" if not raw.startswith(XML_START) else "plain XML", expiration))

    original_entitlements = profile.get("Entitlements")
    profile["ExpirationDate"] = NEW_EXPIRATION_DATE
    profile["CreationDate"] = NEW_CREATION_DATE

    plist_path = os.path.join(workdir, name + ".plist")
    with open(plist_path, "wb") as handle:
        handle.write(plistlib.dumps(profile, fmt=plistlib.FMT_XML, sort_keys=False))

    output_path = os.path.join(workdir, name + ".signed")
    failures = []
    signers = (
        ("security cms -S", lambda: sign_with_security(plist_path, output_path)),
        ("openssl smime -sign", lambda: sign_with_openssl(p12_path, plist_path, output_path, workdir)),
    )
    for label, signer in signers:
        if os.path.exists(output_path):
            os.unlink(output_path)
        try:
            signer()
            expires = verify_signed(output_path, original_entitlements)
        except Exception as error:  # noqa: BLE001 - report every signer that fails
            failures.append("{}: {}".format(label, error))
            continue
        shutil.copyfile(output_path, path)
        log("    -> signed with {}, {} bytes, expires {}".format(label, os.path.getsize(path), expires))
        return True

    raise RuntimeError("could not re-sign {}:\n  {}".format(path, "\n  ".join(failures)))


_identity = None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("codesigning_dir", help="path to build-system/fake-codesigning")
    parser.add_argument("--check", action="store_true", help="report profile state, change nothing")
    args = parser.parse_args()

    profiles_dir = os.path.join(args.codesigning_dir, "profiles")
    p12_path = os.path.join(args.codesigning_dir, "certs", "SelfSigned.p12")

    paths = sorted(glob.glob(os.path.join(profiles_dir, "*.mobileprovision")))
    if not paths:
        log("no *.mobileprovision files in {}".format(profiles_dir))
        return 1

    if args.check:
        now = datetime.datetime.now()
        for path in paths:
            raw = open(path, "rb").read()
            container = "plain XML" if raw.startswith(XML_START) else "CMS"
            profile = plistlib.loads(read_plist_bytes(path))
            expiration = profile.get("ExpirationDate")
            # BuildConfiguration.py needs a CMS container and a future date.
            state = "OK" if container == "CMS" and expiration and expiration > now else "NEEDS SIGNING"
            log("  {:<32} {:<10} {:<14} expires {}".format(
                os.path.basename(path), container, state, expiration))
        return 0

    if sys.platform != "darwin":
        log("refresh_profiles.py needs macOS (uses `security` and `openssl`); "
            "use --check to inspect the files anywhere")
        return 2
    if not os.path.isfile(p12_path):
        log("missing {}".format(p12_path))
        return 1

    global _identity
    log("Setting up temporary keychain and importing {}...".format(os.path.basename(p12_path)))
    setup_keychain(p12_path)
    try:
        _identity = find_identity()
        log("Signing identity: {}".format(_identity))

        workdir = tempfile.mkdtemp(prefix="starforge-profiles-")
        try:
            changed = sum(1 for path in paths if refresh(path, p12_path, workdir))
        finally:
            shutil.rmtree(workdir, ignore_errors=True)
    finally:
        cleanup_keychain()

    log("Done: {} of {} profiles re-signed.".format(changed, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
