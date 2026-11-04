"""Real local HTTP fixture. Never records Authorization or accepts a production key."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse
import json
from pathlib import Path
import time

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=0)
parser.add_argument('--port-file')
parser.add_argument('--log')
args = parser.parse_args()

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        if self.headers.get('Authorization') != 'Bearer alex-local-fixture':
            if args.log:
                with open(args.log, 'a') as log:
                    log.write(json.dumps({'auth_matched': False, 'header_length': len(self.headers.get('Authorization', ''))}) + '\n')
            return self.fail(401)
        if body.get('model') != 'test-model' or body.get('stream') is not True:
            return self.fail(400)
        messages = body.get('messages', [])
        try:
            user = json.loads(messages[-1]['content'])
            text = user['originalText']
        except (ValueError, KeyError, IndexError):
            return self.fail(422)
        if args.log:
            with open(args.log, 'a') as log:
                log.write(json.dumps({'path': self.path, 'text': text, 'context': user.get('contextSentence'), 'model': body['model'], 'system': messages[0]['content']}, ensure_ascii=False) + '\n')
        if '/unauthorized/' in self.path:
            return self.fail(401)
        if '/rate-limit/' in self.path:
            return self.fail(429)
        if '/redirect/' in self.path:
            self.send_response(307)
            self.send_header('Location', '/sink')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        try:
            if '/malformed/' in self.path:
                self.wfile.write(b'data: {broken\n\n'); self.wfile.flush(); return
            if '/empty/' in self.path:
                return self.done()
            if text.lower() == 'ephemeral':
                chunks = ['/ɪˈfemərəl/\n', 'adj. 短暂的；转瞬即逝的\n', 'n. 只风行一时的东西']
            else:
                chunks = ['这是一段', '逐步返回的译文。', '\n玻璃的光学特性', '与流动感融为一体。']
            for chunk in chunks:
                data = json.dumps({'choices': [{'delta': {'content': chunk}}]}, ensure_ascii=False)
                self.wfile.write(('data: ' + data + '\n\n').encode()); self.wfile.flush()
                time.sleep(0.7 if '/slow/' in self.path else 0.12)
            if '/disconnect/' not in self.path:
                self.done()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def done(self):
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()

    def fail(self, code):
        self.send_response(code)
        self.send_header('Content-Length', '0')
        self.end_headers()

server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
url = f'http://127.0.0.1:{server.server_port}'
if args.port_file:
    Path(args.port_file).write_text(str(server.server_port))
print(url, flush=True)
server.serve_forever()
