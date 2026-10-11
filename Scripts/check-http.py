#!/usr/bin/env python3
"""Exercise the production HTTP client against an isolated loopback fixture, without cloud credentials."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
redirect_hits = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == '/stats':
            self.send_json(200, {'redirectHits': len(redirect_hits)})
        elif self.path == '/slow':
            time.sleep(2)
            self.send_json(200, {'ok': True})
        else:
            self.send_json(404, {})

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.path.startswith('/redirect-target'):
            redirect_hits.append(True)
            self.send_json(200, {})
            return
        if self.path.startswith('/redirect/'):
            self.send_response(307)
            self.send_header('Location', '/redirect-target/chat/completions')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path.startswith('/unauthorized/'):
            self.send_json(401, {'error': {'message': 'fixture'}})
            return
        if self.path.startswith('/malformed/'):
            self.send_json(200, {'choices': []})
            return
        request = json.loads(data)
        if self.headers.get('Authorization') != 'Bearer fixture-only-key':
            self.send_json(401, {})
            return
        if request['model'] == 'qwen-mt-lite':
            if len(request['messages']) != 1 or request['messages'][0]['role'] != 'user' or 'response_format' in request:
                self.send_json(400, {})
                return
            to_english = request['translation_options']['target_lang'] == 'English'
            self.send_json(200, {'choices': [{'message': {'content': 'This conclusion is tentative.' if to_english else '这个结论尚未确定。'}}]})
            return
        source = json.loads(request['messages'][-1]['content'])
        to_english = source.get('target_language') == 'English'
        result = {
            'detectedLanguage': source['source_language'],
            'translation': source.get('translation') or ('This conclusion is tentative.' if to_english else '这个结论尚未确定。'),
            'vocabulary': [{
                'word': 'tentative', 'ipa': None, 'partOfSpeech': 'adj.',
                'contextualMeaning': '尚未最终确定的', 'commonMeanings': ['暂定的', '试探性的'],
                'collocations': ['a tentative conclusion'],
                'examples': [
                    {'english': 'These dates are tentative.', 'chinese': '这些日期是暂定的。'},
                    {'english': 'We reached a tentative agreement.', 'chinese': '我们达成了初步协议。'}]
            }]
        }
        self.send_json(200, {'choices': [{'message': {'content': json.dumps(result, ensure_ascii=False)}}]})

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.daemon_threads = True
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    environment = os.environ.copy()
    environment['LIGHT_TRANSLATE_TEST_BASE_URL'] = f'http://127.0.0.1:{server.server_port}'
    completed = subprocess.run([str(ROOT / '.build/debug/TranslationChecks')], env=environment, cwd=ROOT)
    raise SystemExit(completed.returncode)
finally:
    server.shutdown()
    server.server_close()
