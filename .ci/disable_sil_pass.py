#!/usr/bin/env python3
"""Disable a SIL optimization pass for the ShareScreen module.

Swift 6.3.3 (Xcode 26.6) crashes while optimizing
`ShareScreen.init(context:subject:...)` -- a genuine compiler bug in OSSA
lifetime canonicalization:

    While running pass #N SILFunctionTransform "<Pass>" on SILFunction ...
    swift::OSSACanonicalizeOwned::extendLexicalLivenessToDeadEnds()
    -> visitUsersOutsideLinearLivenessBoundary()
    -> llvm::report_fatal_error

Every pass that reaches that code path has to be turned off for this module.
The passes are pure optimizations: disabling them changes no semantics, only
costs a little optimization inside this one module.

Usage: disable_sil_pass.py <PassName>
Exit:  0 patch written (or pass was already disabled), 1 on error.
"""

import re
import sys

PATH = 'submodules/TelegramUI/Components/ShareScreen/BUILD'

# The first (and only) `copts = [` block in the file, up to its closing `],`.
BLOCK_RE = re.compile(r'    copts = \[\n(?:.*?\n)*?    \],\n')


def main():
    if len(sys.argv) != 2:
        print('usage: disable_sil_pass.py <PassName>')
        return 1

    name = sys.argv[1]
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', name):
        print('::error::refusing a suspicious pass name: {!r}'.format(name))
        return 1

    with open(PATH, 'r', encoding='utf-8') as handle:
        source = handle.read()

    match = BLOCK_RE.search(source)
    if match is None:
        print('::error::cannot find the ShareScreen copts block in ' + PATH)
        return 1

    block = match.group(0)
    disabled = re.findall(r'-sil-disable-pass=([A-Za-z0-9]+)', block)
    if name in disabled:
        print('pass {} is already disabled'.format(name))
        return 0

    disabled.append(name)

    lines = [
        '    copts = [',
        '        "-warnings-as-errors",',
        '        # Star Forge: Swift 6.3.3 crashes in OSSA lifetime',
        '        # canonicalization (visitUsersOutsideLinearLivenessBoundary)',
        '        # while optimizing this module, so the offending passes are',
        '        # disabled. They are pure optimizations; semantics are unchanged.',
    ]
    for item in disabled:
        lines.append('        "-Xllvm",')
        lines.append('        "-sil-disable-pass={}",'.format(item))
    lines.append('    ],')
    lines.append('')

    patched = source[:match.start()] + '\n'.join(lines) + source[match.end():]

    with open(PATH, 'w', encoding='utf-8') as handle:
        handle.write(patched)

    print('disabled SIL passes for ShareScreen: {}'.format(', '.join(disabled)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
