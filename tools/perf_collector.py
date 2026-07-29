#!/usr/bin/env python3
"""Serve an exported web build and collect what its perf probe POSTs back.

One process on one port, deliberately: the probe POSTs to 127.0.0.1:8970 and the
page is served from the same origin, so there is no CORS preflight to get wrong.

    python tools/perf_collector.py build/perf
    # then open http://127.0.0.1:8970/index.html?mode=base

Modes are base | phys | audio (see scripts/perf_probe.gd). The tab must be
VISIBLE AND FOCUSED — Chrome suspends requestAnimationFrame in a background tab,
so a hidden tab reports nothing at all rather than reporting slow numbers.

Results stream to stdout and land in <serve_dir>/../perf-<mode>-<n>.json.
"""

import json
import os
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = 8970
OUT_DIR = "notes/perf"


class Handler(SimpleHTTPRequestHandler):
    # .wasm must be served as application/wasm or the streaming compile falls
    # back to a slow path (or refuses outright, depending on the browser).
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def do_POST(self):
        if self.path.rstrip("/") != "/result":
            self.send_error(404)
            return
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode("utf-8", "replace")
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            print("  ?? unparseable payload:", raw[:200], flush=True)
            return
        self.server.record(obj)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def log_message(self, *_args):
        pass  # the request log drowns the results


class Collector(ThreadingHTTPServer):
    def __init__(self, addr, root):
        self.root = root
        self.rows = []
        super().__init__(addr, lambda *a: Handler(*a, directory=root))

    def record(self, obj):
        event = obj.get("event", "?")
        if event == "started":
            print(f"\n=== probe started: mode={obj.get('mode')} "
                  f"stages={obj.get('stages')} settle={obj.get('settle_s')}s "
                  f"adapter={obj.get('adapter')}", flush=True)
        elif event == "warn":
            print(f"  !! {obj.get('detail')}", flush=True)
        elif event == "stage":
            d = obj.get("data", {})
            self.rows.append(d)
            print("  z=%-3s col=%-5s v=%-3s md=%-4s | median %6.2f  p99 %6.2f  "
                  "worst %7.2f  jitter %4.2f | phys %5.2f  pairs %-5s  draws %s"
                  % (d.get("zombies"), d.get("collide"), d.get("voices"),
                     d.get("max_dist"), d.get("median_ms", 0), d.get("p99_ms", 0),
                     d.get("worst_ms", 0), d.get("jitter", 0),
                     d.get("physics_ms", 0), d.get("collision_pairs"),
                     d.get("draw_calls")), flush=True)
        elif event == "final":
            env = obj.get("env", {})
            mode = env.get("mode", "base")
            os.makedirs(OUT_DIR, exist_ok=True)
            path = os.path.join(OUT_DIR, f"{mode}-{time.strftime('%Y%m%d-%H%M%S')}.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(obj, f, indent=2)
            print(f"\n=== final: {env.get('renderer')} / {env.get('driver')} / "
                  f"{env.get('physics')} @ {env.get('viewport')}", flush=True)
            print(f"=== wrote {path}\n", flush=True)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "build/perf"
    if not os.path.isdir(root):
        sys.exit(f"no such directory: {root}")
    srv = Collector(("127.0.0.1", PORT), root)
    print(f"serving {root} and collecting on http://127.0.0.1:{PORT}/", flush=True)
    print(f"open http://127.0.0.1:{PORT}/index.html?mode=base  "
          f"(and ?mode=phys, ?mode=audio)\n", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
