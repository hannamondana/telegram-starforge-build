#!/usr/bin/env python3
"""
Star Forge build driver.

Why this is not a compiler
--------------------------
The iOS application itself is compiled by Apple's toolchain: the Swift/Clang
frontends targeting `arm64-apple-ios`, the `iPhoneOS.sdk` frameworks, the Apple
linker and `codesign`. Apple ships that toolchain only inside Xcode, only for
macOS. No Python program can perform those steps, so this script orchestrates
the real build instead of pretending to replace it:

  * on macOS it drives the repository's own `build-system/Make/Make.py`;
  * on any other host it can dispatch the GitHub Actions workflow that runs on a
    cloud macOS runner, then fetch the resulting IPA.

Usage
-----
    python3 starforge_build.py --check
    python3 starforge_build.py                          # local macOS build
    python3 starforge_build.py --xcode-version 27.1
    python3 starforge_build.py --github OWNER/REPO --ref master
"""

from __future__ import annotations

import argparse
import glob
import os
import platform
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = "build-system/appstore-configuration.json"
DEFAULT_SIGNING = "build-system/fake-codesigning"
DEFAULT_WORKFLOW = "build-starforge.yml"


def log(message: str) -> None:
    print("[starforge] " + message, flush=True)


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    print("[starforge] error: " + message, file=sys.stderr, flush=True)
    sys.exit(1)


def run(command: list[str], cwd: str | None = None) -> None:
    log("run: " + " ".join(command))
    result = subprocess.run(command, cwd=cwd)
    if result.returncode != 0:
        fail("command failed with exit code {}: {}".format(result.returncode, " ".join(command)))


def python_executable() -> str:
    # macOS tooling in this repo expects a `python3`; on Windows the launcher is
    # `python`. Prefer whichever actually exists.
    for candidate in ("python3", "python"):
        if shutil.which(candidate):
            return candidate
    fail("no python interpreter found on PATH")
    return "python"


def xcode_version_from_versions_file() -> str | None:
    path = os.path.join(HERE, "versions.json")
    if not os.path.exists(path):
        return None
    try:
        import json

        with open(path, "r", encoding="utf-8") as handle:
            return str(json.load(handle).get("xcode"))
    except Exception:
        return None


def diagnostics() -> None:
    log("host        : {} {}".format(platform.system(), platform.release()))
    log("python      : {} ({})".format(sys.version.split()[0], python_executable()))
    xcodebuild = shutil.which("xcodebuild")
    log("xcodebuild  : {}".format(xcodebuild or "NOT FOUND"))
    log("bazel       : {}".format(shutil.which("bazel") or "will be downloaded"))
    log("xcode (want): {}".format(xcode_version_from_versions_file() or "unknown"))
    log("gh          : {}".format(shutil.which("gh") or "NOT FOUND"))
    if platform.system() != "Darwin":
        log("")
        log("This host cannot compile iOS binaries: the Apple toolchain and the")
        log("iOS SDK exist only in Xcode on macOS. Use --github to build in CI.")


def find_ipa(search_root: str, output_dir: str) -> str | None:
    expected = os.path.join(output_dir, "Telegram.ipa")
    if os.path.isfile(expected):
        return expected
    patterns = [
        os.path.join(output_dir, "*.ipa"),
        os.path.join(search_root, "bazel-out", "applebin_ios-ios_arm*-opt-ST-*", "bin", "Telegram", "Telegram.ipa"),
    ]
    for pattern in patterns:
        matches = sorted(glob.glob(pattern))
        if matches:
            return matches[-1]
    return None


def local_build(args: argparse.Namespace) -> None:
    if platform.system() != "Darwin":
        fail(
            "an iOS .ipa can only be compiled on macOS with Xcode. "
            "Run this on a Mac, or use --github OWNER/REPO to build in CI."
        )

    if not shutil.which("xcodebuild"):
        fail("Xcode command line tools are missing. Install Xcode first (version from versions.json).")

    source_dir = os.path.abspath(args.source or HERE)
    config = args.config or DEFAULT_CONFIG
    signing = args.signing or DEFAULT_SIGNING
    output_dir = os.path.abspath(args.out or os.path.join(source_dir, "build-artifacts"))
    cache_dir = os.path.abspath(args.cache_dir or os.path.join(os.path.expanduser("~"), "telegram-bazel-cache"))
    build_number = args.build_number or "100001"
    py = python_executable()

    log("source      : {}".format(source_dir))
    log("configuration: {}".format(config))
    log("signing     : {}".format(signing))
    log("output      : {}".format(output_dir))

    os.makedirs(output_dir, exist_ok=True)

    certificates = os.path.join(source_dir, "build-system", "Make", "ImportCertificates.py")
    if os.path.exists(certificates):
        run([py, certificates, "--path", os.path.join(source_dir, signing, "certs")], cwd=source_dir)

    make_py = os.path.join(source_dir, "build-system", "Make", "Make.py")
    command = [
        py,
        "-u",
        make_py,
        "--cacheDir={}".format(cache_dir),
    ]
    if args.bazel_root:
        command.append("--bazelUserRoot={}".format(os.path.abspath(args.bazel_root)))
    command += [
        "build",
        "--configurationPath={}".format(config),
        "--codesigningInformationPath={}".format(signing),
        "--configuration=release_arm64",
        "--buildNumber={}".format(build_number),
        "--outputBuildArtifactsPath={}".format(output_dir),
    ]
    if args.xcode_version:
        command.append("--overrideXcodeVersion")
    run(command, cwd=source_dir)

    ipa = find_ipa(source_dir, output_dir)
    if not ipa:
        fail("build finished but no Telegram.ipa was found")
    log("IPA ready   : {}".format(ipa))
    log("Sign it with Sideloadly / AltStore / Xcode using your Apple ID, then sideload.")


def github_build(args: argparse.Namespace) -> None:
    if not shutil.which("gh"):
        fail(
            "the GitHub CLI ('gh') is required for --github. "
            "Install it (https://cli.github.com) and authenticate with 'gh auth login'."
        )
    repo = args.github
    ref = args.ref or "master"
    workflow = args.workflow or DEFAULT_WORKFLOW
    inputs: list[str] = []
    if args.xcode_version:
        inputs += ["-f", "xcode_version={}".format(args.xcode_version)]
    if args.build_number:
        inputs += ["-f", "build_number={}".format(args.build_number)]

    run(["gh", "workflow", "run", workflow, "--repo", repo, "--ref", ref] + inputs)
    log("dispatched; waiting for the run to start...")
    run(["gh", "run", "watch", "--repo", repo, "--workflow", workflow, "--exit-status"])
    out = os.path.abspath(args.out or ".")
    os.makedirs(out, exist_ok=True)
    run(["gh", "run", "download", "--repo", repo, "--workflow", workflow, "--dir", out])
    log("artifacts downloaded to {}".format(out))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Star Forge iOS build driver (orchestrates Apple's toolchain, does not replace it)."
    )
    parser.add_argument("--check", action="store_true", help="print an environment report and exit")
    parser.add_argument("--github", metavar="OWNER/REPO", help="dispatch the build to GitHub Actions instead of building locally")
    parser.add_argument("--workflow", metavar="FILE", help="workflow file name for --github (default: {})".format(DEFAULT_WORKFLOW))
    parser.add_argument("--ref", metavar="BRANCH", help="git ref for --github (default: master)")
    parser.add_argument("--source", metavar="DIR", help="repository root (default: script directory)")
    parser.add_argument("--config", metavar="PATH", help="build configuration json (default: {})".format(DEFAULT_CONFIG))
    parser.add_argument("--signing", metavar="DIR", help="codesigning directory (default: {})".format(DEFAULT_SIGNING))
    parser.add_argument("--out", metavar="DIR", help="artifact output directory")
    parser.add_argument("--cache-dir", metavar="DIR", help="Bazel disk cache (macOS only)")
    parser.add_argument("--bazel-root", metavar="DIR", help="Bazel user root (macOS only)")
    parser.add_argument("--build-number", metavar="N", help="build number (default: 100001)")
    parser.add_argument("--xcode-version", metavar="V", help="bypass the versions.json check and use the installed Xcode")

    args = parser.parse_args()

    if args.check:
        diagnostics()
        return

    if args.github:
        github_build(args)
    else:
        local_build(args)


if __name__ == "__main__":
    main()
