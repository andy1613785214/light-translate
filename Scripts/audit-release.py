"""Checks only explicitly publishable files; never reads Keychain or private preferences."""
from pathlib import Path
import argparse, plistlib, re, subprocess, sys

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_DIRS = ['Sources', 'Scripts', 'Resources', 'Tests', 'docs', '.github']
PUBLIC_FILES = ['README.md', 'Package.swift', '.gitignore', '.gitattributes', 'LICENSE', 'Evaluation/cases.json']
PATTERNS = {
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'API token': re.compile(rb'\bsk-[A-Za-z0-9_-]{20,}\b'),
    'Google API token': re.compile(rb'\bAIza[0-9A-Za-z_-]{30,}\b'),
    'GitHub token': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'),
    'AWS access ID': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
}
BLOCKED_SUFFIXES = {'.pem', '.p12', '.pfx', '.key', '.keychain', '.keychain-db'}
failures = []

def inspect(path):
    if path.is_symlink() or not path.is_file(): return
    if path.name == '.env' or path.name.startswith('.env.') or path.suffix.lower() in BLOCKED_SUFFIXES:
        failures.append((path, 'private configuration filename')); return
    data = path.read_bytes()
    for reason, pattern in PATTERNS.items():
        if pattern.search(data): failures.append((path, reason))

parser = argparse.ArgumentParser()
parser.add_argument('--source', action='store_true')
parser.add_argument('--bundle', type=Path)
parser.add_argument('--staged', action='store_true')
args = parser.parse_args()
source_count = 0
if args.source:
    paths = [ROOT/f for f in PUBLIC_FILES if (ROOT/f).exists()]
    paths += [p for name in PUBLIC_DIRS for p in (ROOT/name).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name != '.DS_Store']
    for path in paths: inspect(path)
    source_count = len(paths)
if args.staged:
    paths = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '-z'], cwd=ROOT).decode().split('\0')
    for relative in filter(None, paths):
        path = ROOT/relative
        if relative not in PUBLIC_FILES and relative.split('/')[0] not in PUBLIC_DIRS:
            failures.append((path, 'outside publish allowlist'))
        if '.build' in path.parts or 'dist' in path.parts or '__pycache__' in path.parts:
            failures.append((path, 'local runtime artifact'))
        inspect(path)
if args.bundle:
    bundle = args.bundle.resolve()
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    for key in ['apiKey', 'APIKey', 'endpoint', 'cloudModel', 'ollamaPath', 'shortcut']:
        if key in info: failures.append((bundle/'Contents/Info.plist', 'user configuration embedded'))
    for path in bundle.rglob('*'):
        if any(name in path.parts for name in ['.aws', '.codex', '.git', '.env']): failures.append((path, 'private directory'))
        inspect(path)
    binary = (bundle/'Contents/MacOS/LightTranslate').read_bytes()
    if str(Path.home()).encode() in binary: failures.append((bundle/'Contents/MacOS/LightTranslate', 'personal build path embedded'))
if failures:
    for path, reason in failures: print(f'FAIL: {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path.name}: {reason}')
    sys.exit(1)
print(f'PASS: privacy audit ({source_count} source files; bundle={bool(args.bundle)}; staged={args.staged})')
