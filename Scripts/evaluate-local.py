#!/usr/bin/env python3
"""Evaluate Qwen on an isolated owned server. Downloads only with explicit --download."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--model', choices=['qwen3:0.6b', 'qwen3:1.7b'], default='qwen3:0.6b')
parser.add_argument('--limit', type=int, default=30)
parser.add_argument('--ollama', default=shutil.which('ollama') or '/opt/homebrew/bin/ollama')
parser.add_argument('--download', action='store_true', help='Explicitly download the selected model before evaluation')
args = parser.parse_args()
if args.limit < 1:
    raise SystemExit('--limit must be at least 1')
models = Path(os.environ.get('OLLAMA_MODELS', Path.home() / '.ollama/models'))
manifest = models / 'manifests/registry.ollama.ai/library/qwen3' / args.model.split(':')[1]
if not manifest.exists() and not args.download:
    raise SystemExit(f'Model is not installed: {args.model}. No download was attempted.')
for layer in (json.loads(manifest.read_text()).get('layers', []) if manifest.exists() else []):
    blob = models / 'blobs' / layer['digest'].replace(':', '-')
    if not blob.is_file():
        raise SystemExit(f'Missing model blob: {blob.name}')

environment = os.environ.copy()
environment['CLANG_MODULE_CACHE_PATH'] = str(ROOT / '.build/clang-module-cache')
environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(ROOT / '.build/swift-module-cache')
subprocess.run(['swift', 'build', '-c', 'release', '--disable-sandbox', '--cache-path', str(ROOT / '.build/package-cache'), '--product', 'TranslationEval'], cwd=ROOT, env=environment, check=True)
with socket.socket() as probe:
    probe.bind(('127.0.0.1', 0))
    port = probe.getsockname()[1]
base = f'http://127.0.0.1:{port}'
environment.update(OLLAMA_HOST=f'127.0.0.1:{port}', OLLAMA_MODELS=str(models), OLLAMA_NO_CLOUD='1',
                   OLLAMA_KEEP_ALIVE='2m', OLLAMA_NUM_PARALLEL='1', OLLAMA_MAX_LOADED_MODELS='1')
output = ROOT / 'Evaluation' / ('results-' + args.model.replace(':', '-') + '.json')
with (ROOT / '.build/ollama-evaluation.log').open('w') as log:
    server = subprocess.Popen([args.ollama, 'serve'], env=environment, stdout=log, stderr=log, start_new_session=True)
    try:
        for _ in range(120):
            if server.poll() is not None:
                raise RuntimeError('Owned Ollama server exited; see .build/ollama-evaluation.log')
            try:
                with urllib.request.urlopen(base + '/api/version', timeout=0.5) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(0.25)
        else:
            raise RuntimeError('Owned Ollama server did not become ready')
        if args.download:
            print(f'Explicit download requested: {args.model}', flush=True)
            with (ROOT / '.build/model-download.log').open('w') as download_log:
                subprocess.run([args.ollama, 'pull', args.model], env=environment, check=True,
                               stdout=download_log, stderr=download_log)
        samples = []
        stop_sampling = threading.Event()
        started = time.monotonic()
        def sample_owned_group():
            while not stop_sampling.is_set():
                try:
                    rows = subprocess.check_output(['ps', '-ax', '-o', 'pgid=,rss='], text=True)
                    rss = sum(int(fields[1]) for row in rows.splitlines()
                              if len(fields := row.split()) == 2 and int(fields[0]) == server.pid)
                    samples.append({'seconds': round(time.monotonic() - started, 3), 'serverRssMiB': rss / 1024})
                except (OSError, subprocess.CalledProcessError, ValueError):
                    pass
                stop_sampling.wait(0.5)
        sampler = threading.Thread(target=sample_owned_group, daemon=True)
        sampler.start()
        print(f'Evaluating {args.model}; output: {output}', flush=True)
        try:
            evaluated = subprocess.run([str(ROOT / '.build/release/TranslationEval'), base, args.model,
                                        str(ROOT / 'Evaluation/cases.json'), str(output), str(args.limit)], cwd=ROOT)
        finally:
            stop_sampling.set()
            sampler.join(timeout=2)
            resources = {'model': args.model, 'sampleIntervalSeconds': 0.5,
                         'peakObservedServerRssMiB': max((s['serverRssMiB'] for s in samples), default=None),
                         'samples': samples}
            resource_path = ROOT / 'Evaluation' / ('resources-' + args.model.replace(':', '-') + '.json')
            resource_path.write_text(json.dumps(resources, indent=2))
        raise SystemExit(evaluated.returncode)
    finally:
        # This process group was created above and contains only this evaluation's server/runners.
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=8)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
                server.wait()
