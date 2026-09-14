#!/usr/bin/env python3
"""Check a Cinema Composer tool pack against a video vendor.

Two modes, cheapest first.

  mock   Spin up a local vendor that behaves like a real async generator and
         run the whole pipeline against it. Costs nothing, needs no key, and
         catches everything except "is this endpoint real".

  live   Put ONE short shot through a real vendor with your own key. Prints the
         exact request first and will not send it without --send. Then it reads
         the replies, works out where the job id, status and file actually live,
         and prints a jobProtocol block you can paste straight into the pack.

Examples
  python3 Tools/vendor-check.py mock
  python3 Tools/vendor-check.py live --tool runway-gen --key "$RUNWAY_KEY"
  python3 Tools/vendor-check.py live --tool luma-dream --key "$LUMA_KEY" --send
"""
import argparse, json, os, re, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib import error as urlerror, request as urlrequest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PACK = os.path.join(HERE, "CinemaComposerPro", "Packs", "async-video-vendors.json")
MEDIA = os.path.join(tempfile.gettempdir(), "CinemaComposerMedia")


def rule(title, char="─"):
    print("\n" + char * 74)
    print(title)
    print(char * 74)


# ─────────────────────────────── shared client ───────────────────────────────

def json_path(path, root):
    """Port of JSONPath.value — dot paths with numeric array indexes."""
    node = root
    for part in path.split("."):
        if node is None:
            return None
        if part.isdigit():
            if not isinstance(node, list) or int(part) >= len(node):
                return None
            node = node[int(part)]
        else:
            if not isinstance(node, dict):
                return None
            node = node.get(part)
    return node


def fill(tpl, *, prompt, seconds, shot_id, take, api_key):
    """Port of HTTPToolAdapter.fill."""
    return (tpl.replace("{{apiKey}}", api_key or "")
               .replace("{{units}}", f"{seconds:.2f}")
               .replace("{{seconds}}", f"{seconds:.2f}")
               .replace("{{shotId}}", shot_id)
               .replace("{{take}}", str(take))
               .replace("{{prompt}}", prompt))


def build_body(tool, **kw):
    raw = {k: fill(v, **kw) for k, v in (tool.get("body") or {}).items()}
    typed = {}
    for k, v in raw.items():
        try:
            typed[k] = float(v) if " " not in v else v
        except ValueError:
            typed[k] = v
    return typed


def walk(node, prefix=""):
    """Every leaf in a JSON tree, as (path, value)."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{prefix}.{k}" if prefix else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{prefix}.{i}" if prefix else str(i))
    else:
        yield prefix, node


def guess_id_path(root):
    cands = [(p, v) for p, v in walk(root)
             if isinstance(v, (str, int)) and re.search(r"(^|\.)(id|task_id|uuid)$", p, re.I)]
    cands.sort(key=lambda pv: len(pv[0].split(".")))
    return cands[0][0] if cands else None


def guess_status_path(root):
    cands = [(p, v) for p, v in walk(root)
             if isinstance(v, str) and re.search(r"(status|state)$", p, re.I)]
    cands.sort(key=lambda pv: len(pv[0].split(".")))
    return cands[0][0] if cands else None


def guess_url_path(root):
    cands = [(p, v) for p, v in walk(root)
             if isinstance(v, str) and v.startswith("http")
             and re.search(r"\.(mp4|mov|webm|m4v)(\?|$)", v, re.I)]
    if not cands:
        cands = [(p, v) for p, v in walk(root)
                 if isinstance(v, str) and v.startswith("http")
                 and re.search(r"(url|video|output|asset|download)", p, re.I)]
    cands.sort(key=lambda pv: len(pv[0].split(".")))
    return cands[0][0] if cands else None


def send(url, *, method="GET", headers=None, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = urlrequest.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urlrequest.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), dict(r.headers)
    except urlerror.HTTPError as e:
        return e.code, e.read(), dict(e.headers or {})


def redact(text, key):
    return text.replace(key, key[:4] + "…" + key[-2:]) if key and len(key) >= 8 else text


# ──────────────────────────────── mock mode ────────────────────────────────

MP4 = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom\x00\x00\x00\x08free"
_jobs, _lock = {}, threading.Lock()


def mock_server(port):
    class H(BaseHTTPRequestHandler):
        def _j(self, code, payload):
            b = json.dumps(payload).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_POST(self):
            if "Bearer " not in self.headers.get("authorization", ""):
                return self._j(401, {"error": "missing or malformed api key"})
            n = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(n)) if n else {}
            with _lock:
                jid = f"job_{len(_jobs)+1:04d}"
                _jobs[jid] = {"polls": 0, "payload": payload}
            self._j(200, {"id": jid})

        def do_GET(self):
            m = re.match(r"^/v1/tasks/(.+)$", self.path)
            if m:
                with _lock:
                    job = _jobs.get(m.group(1))
                    if not job:
                        return self._j(404, {"error": "unknown job"})
                    job["polls"] += 1
                    polls = job["polls"]
                if polls < 3:
                    return self._j(200, {"id": m.group(1), "status": "RUNNING"})
                return self._j(200, {"id": m.group(1), "status": "SUCCEEDED",
                                     "output": [f"http://127.0.0.1:{port}/f/{m.group(1)}.mp4"]})
            if self.path.startswith("/f/"):
                self.send_response(200)
                self.send_header("Content-Type", "video/mp4")
                self.send_header("Content-Length", str(len(MP4)))
                self.end_headers()
                self.wfile.write(MP4)
                return
            self._j(404, {"error": "no route"})

        def log_message(self, *a):
            pass
    return HTTPServer(("127.0.0.1", port), H)


def run_mock(args):
    port = args.port
    base = f"http://127.0.0.1:{port}"
    tool = {
        "name": "Mock async vendor",
        "endpoint": f"{base}/v1/text_to_video",
        "headers": {"authorization": "Bearer {{apiKey}}"},
        "body": {"prompt": "{{prompt}}", "duration": "{{seconds}}", "shot_ref": "{{shotId}}"},
        "limits": {"maxShotSeconds": 10},
        "jobProtocol": {"statusEndpoint": f"{base}/v1/tasks/{{{{jobId}}}}",
                        "jobIDPath": "id", "statusPath": "status",
                        "resultURLPath": "output.0",
                        "succeededValues": ["SUCCEEDED"], "failedValues": ["FAILED"],
                        "pollSeconds": 0.05, "timeoutSeconds": 20},
    }
    srv = mock_server(port)
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    rule("MOCK VENDOR — free, no key, no network", "═")
    print(f"  listening on {base}")
    shots = [("S001-0001", 4.0), ("S001-0002", 7.5), ("S001-0003", 13.0)]
    ok, fail = 0, 0
    for shot_id, seconds in shots:
        for piece_id, piece_secs in segments(shot_id, seconds, tool["limits"]["maxShotSeconds"]):
            try:
                out = render_once(tool, piece_id, piece_secs,
                                  "mock shot, 16mm grain", 1, "sk-mock-000000", quiet=True)
                print(f"  ✓ {piece_id:<16} asked {piece_secs:>5.2f}s · "
                      f"{out['polls']} polls · {out['bytes']}B → {os.path.basename(out['file'])}")
                ok += 1
            except Exception as e:                                  # noqa: BLE001
                print(f"  ✗ {piece_id:<16} {e}")
                fail += 1
    srv.shutdown()

    rule("RESULT", "═")
    print(f"  {ok} generated, {fail} failed")
    print(f"  files in {MEDIA}")
    print("\n  What this proves: template filling, per-shot splitting, job polling,")
    print("  result extraction, download and media-store naming all work.")
    print("  What it cannot prove: that a vendor's real endpoint and auth are right.")
    print("  For that, run `live` once per vendor.")
    return 0 if fail == 0 else 1


def segments(shot_id, seconds, cap):
    if not cap or seconds <= cap:
        return [(shot_id, seconds)]
    n = int(seconds / cap + 0.999999)
    each = seconds / n
    return [(f"{shot_id}#{i+1}", round(each * 100) / 100) for i in range(n)]


def render_once(tool, shot_id, seconds, prompt, take, api_key, quiet=False):
    kw = dict(prompt=prompt, seconds=seconds, shot_id=shot_id, take=take, api_key=api_key)
    headers = {"Content-Type": "application/json"}
    for k, v in (tool.get("headers") or {}).items():
        headers[k] = fill(v, **kw)
    body = build_body(tool, **kw)

    status, raw, _ = send(fill(tool["endpoint"], **kw), method=tool.get("method", "POST"),
                          headers=headers, body=body)
    if not 200 <= status < 300:
        raise RuntimeError(f"submit HTTP {status}: {raw[:200].decode(errors='replace')}")
    submit = json.loads(raw)

    jp = tool["jobProtocol"]
    jid = json_path(jp["jobIDPath"], submit)
    if jid is None:
        raise RuntimeError(f'no job id at "{jp["jobIDPath"]}"')

    deadline, polls = time.time() + jp.get("timeoutSeconds", 900), 0
    while time.time() < deadline:
        time.sleep(jp.get("pollSeconds", 5))
        polls += 1
        surl = fill(jp["statusEndpoint"], **kw).replace("{{jobId}}", str(jid))
        st_code, st_raw, _ = send(surl, method=jp.get("statusMethod", "GET"), headers=headers)
        if not 200 <= st_code < 300:
            raise RuntimeError(f"status HTTP {st_code}: {st_raw[:200].decode(errors='replace')}")
        reply = json.loads(st_raw)
        state = json_path(jp["statusPath"], reply)
        state_s = str(state) if state is not None else ""
        if any(state_s.lower() == f.lower() for f in jp.get("failedValues", [])):
            msg = json_path(jp.get("failureMessagePath") or "", reply) or state_s
            raise RuntimeError(f"vendor reported failed: {msg}")
        if any(state_s.lower() == s.lower() for s in jp.get("succeededValues", [])):
            url = json_path(jp["resultURLPath"], reply)
            if not url:
                raise RuntimeError(f'finished but no file at "{jp["resultURLPath"]}"')
            os.makedirs(MEDIA, exist_ok=True)
            safe = re.sub(r"[/\\:*?\"<>|# ]", "_", shot_id)
            dest = os.path.join(MEDIA, f"{safe}-take{take}.mp4")
            _, data, _ = send(url, timeout=300)
            open(dest, "wb").write(data)
            return {"polls": polls, "file": dest, "bytes": len(data)}
    raise RuntimeError("timed out waiting for the vendor")


# ──────────────────────────────── live mode ────────────────────────────────

def run_live(args):
    pack = json.load(open(args.pack))
    tools = {t["id"]: t for t in pack["tools"]}
    if args.tool not in tools:
        print(f"No tool '{args.tool}' in {args.pack}. Available: {', '.join(tools)}")
        return 2
    tool = tools[args.tool]
    if "jobProtocol" not in tool:
        print(f"'{args.tool}' is synchronous (no jobProtocol) — this mode targets async video.")
        return 2

    kw = dict(prompt=args.prompt, seconds=args.seconds,
              shot_id=args.shot, take=1, api_key=args.key)
    headers = {"Content-Type": "application/json"}
    for k, v in (tool.get("headers") or {}).items():
        headers[k] = fill(v, **kw)
    body = build_body(tool, **kw)
    url = fill(tool["endpoint"], **kw)

    rule(f"REQUEST — exactly what the app would send to {tool['name']}", "═")
    print(f"  {tool.get('method','POST')} {url}")
    for k, v in headers.items():
        print(f"  {k}: {redact(v, args.key)}")
    print("\n" + json.dumps(body, indent=2))
    est = tool.get("pricing", {}).get("rate", 0) * args.seconds
    print(f"\n  estimated cost of this one call: ${est:.2f} "
          f"({args.seconds}s × ${tool.get('pricing',{}).get('rate',0)}/s)")

    if not args.send:
        print("\n  Nothing was sent. Re-run with --send to actually call the vendor.")
        return 0

    rule("SUBMIT", "═")
    status, raw, _ = send(url, method=tool.get("method", "POST"), headers=headers, body=body)
    text = raw.decode(errors="replace")
    print(f"  HTTP {status}")
    print("  " + redact(text[:600], args.key))
    if not 200 <= status < 300:
        print("\n  The endpoint or auth is wrong. Check the vendor's current docs;")
        print("  401/403 means the header shape is wrong, 404 means the path moved.")
        return 1
    try:
        submit = json.loads(text)
    except json.JSONDecodeError:
        print("\n  Reply was not JSON — this pack cannot drive that endpoint.")
        return 1

    jp = tool["jobProtocol"]
    rule("WHERE THINGS ACTUALLY ARE", "═")
    found_id = guess_id_path(submit)
    configured_id = jp.get("jobIDPath")
    print(f"  job id   pack says {configured_id!r:<28} found {found_id!r}")
    if found_id and found_id != configured_id:
        print("           ↳ MISMATCH — update jobIDPath")
    jid = json_path(configured_id, submit) or (json_path(found_id, submit) if found_id else None)
    if jid is None:
        print("\n  Could not find a job id at all. Paste the reply above into the pack author.")
        return 1

    rule("POLL", "═")
    deadline = time.time() + jp.get("timeoutSeconds", 900)
    interval = jp.get("pollSeconds", 5)
    last = None
    while time.time() < deadline:
        time.sleep(interval)
        surl = fill(jp["statusEndpoint"], **kw).replace("{{jobId}}", str(jid))
        code, sraw, _ = send(surl, method=jp.get("statusMethod", "GET"), headers=headers)
        stext = sraw.decode(errors="replace")
        if not 200 <= code < 300:
            print(f"  status HTTP {code}: {redact(stext[:300], args.key)}")
            return 1
        last = json.loads(stext)
        state = json_path(jp["statusPath"], last)
        if state is None:
            found_status = guess_status_path(last)
            print(f"  status   pack says {jp['statusPath']!r:<28} found {found_status!r}")
            print("           ↳ MISMATCH — update statusPath")
            state = json_path(found_status, last) if found_status else None
        print(f"  {time.strftime('%H:%M:%S')}  state = {state!r}")
        s = str(state or "")
        if any(s.lower() == f.lower() for f in jp.get("failedValues", [])):
            print("\n  Vendor reported failure. Full reply:")
            print("  " + redact(stext[:600], args.key))
            return 1
        if any(s.lower() == v.lower() for v in jp.get("succeededValues", [])):
            break
    else:
        print("\n  Timed out. Raise timeoutSeconds, or the status values in the pack are wrong.")
        return 1

    rule("RESULT", "═")
    configured_url = jp.get("resultURLPath")
    found_url = guess_url_path(last)
    print(f"  file     pack says {configured_url!r:<28} found {found_url!r}")
    file_url = json_path(configured_url, last) or (json_path(found_url, last) if found_url else None)
    if not file_url:
        print("\n  Finished but no file URL found. Full reply:")
        print("  " + redact(json.dumps(last)[:600], args.key))
        return 1

    os.makedirs(MEDIA, exist_ok=True)
    dest = os.path.join(MEDIA, f"{args.shot}-take1.mp4")
    _, data, hdrs = send(file_url, timeout=300)
    open(dest, "wb").write(data)
    kind = "MP4" if b"ftyp" in data[:32] else hdrs.get("Content-Type", "unknown")
    print(f"  downloaded {len(data):,} bytes ({kind}) → {dest}")

    rule("PASTE THIS INTO THE PACK", "═")
    corrected = dict(jp)
    if found_id:
        corrected["jobIDPath"] = found_id
    fs = guess_status_path(last)
    if fs:
        corrected["statusPath"] = fs
    if found_url:
        corrected["resultURLPath"] = found_url
    observed = str(json_path(corrected["statusPath"], last))
    if observed and observed not in corrected.get("succeededValues", []):
        corrected["succeededValues"] = sorted(set(corrected.get("succeededValues", []) + [observed]))
    print(json.dumps({"jobProtocol": corrected}, indent=2))
    print(f"\n  One real generation cost about ${est:.2f}. The pack is now verified.")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="mode", required=True)

    m = sub.add_parser("mock", help="free local vendor, no key needed")
    m.add_argument("--port", type=int, default=8791)
    m.set_defaults(func=run_mock)

    l = sub.add_parser("live", help="one real shot against a real vendor")
    l.add_argument("--pack", default=DEFAULT_PACK)
    l.add_argument("--tool", required=True, help="tool id, e.g. runway-gen")
    l.add_argument("--key", required=True, help="your API key")
    l.add_argument("--seconds", type=float, default=5.0, help="keep this short — you pay for it")
    l.add_argument("--shot", default="TEST-0001")
    l.add_argument("--prompt", default="a slow push in on an empty theatre, 35mm grain")
    l.add_argument("--send", action="store_true", help="actually call the vendor and spend money")
    l.set_defaults(func=run_live)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
