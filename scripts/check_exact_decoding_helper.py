#!/usr/bin/env python3
"""check-exact-decoding.sh helper — prompts, arms, comparisons, table.

Phases are run by the shell script, which owns the server lifecycle:
  prompts <outdir> <tag>          six fixed prompts, one response file each
  draft-engagement <log> <out>    parse 'accepted N/M draft tokens' lines
  concurrent-solos <out> <tag>    solo run of the two concurrent prompts
  concurrent-pair <out> <tag>     the same two prompts sent at once
  conv-control <out>              a 3-turn conversation in one process
  conv-first2 <out>               turns 1-2, then POST slot save
  conv-restore <out>              POST slot restore, then turn 3 cache_prompt:true
  restore-evidence <log> <out>    parse the restore line
  report <out>                    compare arms, print the table, exit 0/1/2
"""
import json, os, re, sys, threading, urllib.request

PORT = 18210
BASE = f"http://127.0.0.1:{PORT}"


def post(path, body, timeout=1800):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def get(path, timeout=30):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
        return json.loads(r.read())


def prompts():
    doc = ("The quick brown fox jumps over the lazy dog. " * 30)
    return [
        ("short-prose-1", "Write two sentences about the sea."),
        ("short-prose-2", "Explain what a compiler is in three sentences."),
        ("code-1", "Write a Python function that returns the n-th Fibonacci number."),
        ("code-2", "Write a bash function that prints every line of a file matching a regex."),
        ("doc-q", "Given this document, answer in one sentence: " + doc +
                 " What does the document say about the fox?"),
        ("tool-call", "What is the weather in Paris right now? Use the tool."),
    ]


TOOLS = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get the current weather for a city",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string", "description": "City name"}},
            "required": ["city"],
        },
    },
}]


def chat_body(messages, cache_prompt=False, tools=False):
    b = {"messages": messages, "max_tokens": 256, "temperature": 0, "top_k": 1,
         "cache_prompt": cache_prompt, "return_tokens": True, "verbose": True, "stream": False}
    if tools:
        b["tools"] = TOOLS
        b["tool_choice"] = "auto"
    return b


def chat(messages, cache_prompt=False, tools=False):
    return post("/v1/chat/completions", chat_body(messages, cache_prompt, tools))


def save(tag, outdir, body):
    open(os.path.join(outdir, tag + ".req.json"), "w").write(json.dumps(body, indent=1))


def save_resp(tag, outdir, resp):
    open(os.path.join(outdir, tag + ".resp.json"), "w").write(json.dumps(resp, indent=1))


def reply_text(resp):
    choice = (resp.get("choices") or [{}])[0]
    return (choice.get("message") or {}).get("content") or ""


# ---- phases ---------------------------------------------------------------------------
def ph_prompts(outdir, tag):
    for name, prompt in prompts():
        tools = (name == "tool-call")
        body = chat_body([{"role": "user", "content": prompt}], tools=tools)
        save(f"{tag}-{name}", outdir, body)
        try:
            resp = chat([{"role": "user", "content": prompt}], tools=tools)
        except urllib.error.HTTPError as e:
            resp = {"__error__": f"HTTP {e.code}: {e.read().decode()[:400]}"}
        except Exception as e:
            resp = {"__error__": str(e)}
        save_resp(f"{tag}-{name}", outdir, resp)
        toks = resp.get("tokens") or []
        fr = ((resp.get("choices") or [{}])[0].get("finish_reason"))
        print(f"  {tag} {name}: {len(toks)} tokens finish={fr}"
              + (" ERROR" if "__error__" in resp else ""))


def ph_draft_engagement(logfile, outfile):
    txt = open(logfile, errors="replace").read()
    lines = [l.strip() for l in txt.splitlines() if "draft acceptance" in l]
    drafted = accepted = 0
    for l in lines:
        m = re.search(r"draft acceptance = [\d.]+ \(\s*(\d+) accepted /\s*(\d+) generated\)", l)
        if m:
            accepted += int(m.group(1))
            drafted += int(m.group(2))
    engage = drafted > 0 and accepted > 0
    json.dump({"drafted": drafted, "accepted": accepted, "engaged": engage,
               "lines": lines}, open(outfile, "w"), indent=1)
    print(f"DRAFT ENGAGED={engage} drafted={drafted} accepted={accepted} "
          f"(acceptance {accepted}/{drafted})" if engage else
          f"DRAFT ENGAGED=false drafted={drafted} accepted={accepted}")
    return 0


CONC = [p for p in prompts() if p[0] in ("code-1", "short-prose-1")]


def ph_concurrent_solos(outdir, tag):
    for name, prompt in CONC:
        body = chat_body([{"role": "user", "content": prompt}])
        save(f"{tag}-{name}-solo", outdir, body)
        try:
            resp = chat([{"role": "user", "content": prompt}])
        except Exception as e:
            resp = {"__error__": str(e)}
        save_resp(f"{tag}-{name}-solo", outdir, resp)


def ph_concurrent_pair(outdir, tag):
    results = {}

    def one(name, prompt):
        body = chat_body([{"role": "user", "content": prompt}])
        save(f"{tag}-{name}-conc", outdir, body)
        try:
            results[name] = chat([{"role": "user", "content": prompt}])
        except Exception as e:
            results[name] = {"__error__": str(e)}

    ts = [threading.Thread(target=one, args=p) for p in CONC]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    for name, _ in CONC:
        save_resp(f"{tag}-{name}-conc", outdir, results.get(name, {"__error__": "thread failed"}))


def ph_conv_control(outdir):
    """3 turns in one process, cache_prompt false throughout — the RESUME control."""
    msgs = [{"role": "user", "content": "My favourite colour is deep sea blue. Remember it."}]
    body = chat_body(msgs)
    save("conv-control-turn1", outdir, body)
    try:
        r1 = chat(msgs)
    except Exception as e:
        r1 = {"__error__": str(e)}
    save_resp("conv-control-turn1", outdir, r1)
    msgs += [{"role": "assistant", "content": reply_text(r1)},
             {"role": "user", "content": "What is my favourite colour? One word."}]
    body = chat_body(msgs)
    save("conv-control-turn2", outdir, body)
    try:
        r2 = chat(msgs)
    except Exception as e:
        r2 = {"__error__": str(e)}
    save_resp("conv-control-turn2", outdir, r2)
    msgs += [{"role": "assistant", "content": reply_text(r2)},
             {"role": "user", "content": "Now name a shade of that colour. Two words."}]
    body = chat_body(msgs)
    save("conv-control-turn3", outdir, body)
    try:
        r3 = chat(msgs)
    except Exception as e:
        r3 = {"__error__": str(e)}
    save_resp("conv-control-turn3", outdir, r3)


def ph_conv_first2(outdir):
    """Turns 1-2 (same messages as the control), then POST slot save."""
    msgs = [{"role": "user", "content": "My favourite colour is deep sea blue. Remember it."}]
    try:
        r1 = chat(msgs)
    except Exception as e:
        r1 = {"__error__": str(e)}
    save_resp("conv-resume-turn1", outdir, r1)
    msgs += [{"role": "assistant", "content": reply_text(r1)},
             {"role": "user", "content": "What is my favourite colour? One word."}]
    body = chat_body(msgs)
    save("conv-resume-turn2", outdir, body)
    try:
        r2 = chat(msgs)
    except Exception as e:
        r2 = {"__error__": str(e)}
    save_resp("conv-resume-turn2", outdir, r2)
    # the exact message list for turn 3, so the resumed arm uses the same conversation
    turn3 = msgs + [{"role": "assistant", "content": reply_text(r2)},
                    {"role": "user", "content": "Now name a shade of that colour. Two words."}]
    save("conv-resume-turn3-body", outdir, chat_body(turn3, cache_prompt=True))
    json.dump(turn3, open(os.path.join(outdir, "conv-resume-turn3-msgs.json"), "w"))
    try:
        res = post("/slots/0?action=save", {"filename": "conv.bin"}, timeout=60)
    except Exception as e:
        res = {"__error__": str(e)}
    save_resp("slot-save", outdir, res)
    print("slot save:", json.dumps(res))


def ph_conv_restore(outdir):
    try:
        res = post("/slots/0?action=restore", {"filename": "conv.bin"}, timeout=60)
    except Exception as e:
        res = {"__error__": str(e)}
    save_resp("slot-restore", outdir, res)
    print("slot restore:", json.dumps(res))
    turn3 = json.load(open(os.path.join(outdir, "conv-resume-turn3-msgs.json")))
    try:
        r3 = chat(turn3, cache_prompt=True)
    except Exception as e:
        r3 = {"__error__": str(e)}
    save_resp("conv-resume-turn3", outdir, r3)


def ph_restore_evidence(logfile, outfile, outdir=None):
    txt = open(logfile, errors="replace").read()
    # the engine logs nothing for a slot restore itself; the proof is the HTTP reply
    # (slot-restore.resp.json: n_restored > 0) plus the log's "cached n_tokens = N"
    # line on the turn-3 request, which can only be > 0 after a restore.
    hits = [l.strip() for l in txt.splitlines()
            if re.search(r"restor", l, re.I) or re.search(r"n_past", l, re.I)
            or re.search(r"cached n_tokens", l, re.I)]
    ev = {"restored": bool(hits), "log_lines": hits}
    if outdir:
        p = os.path.join(outdir, "slot-restore.resp.json")
        if os.path.exists(p):
            r = json.load(open(p))
            ev["http"] = r
            ev["restored"] = bool(hits) or r.get("n_restored", 0) > 0
            q = os.path.join(outdir, "conv-resume-turn3.resp.json")
            if os.path.exists(q):
                ev["turn3_usage"] = json.load(open(q)).get("usage")
                n_cached = ev["turn3_usage"].get("prompt_tokens_details", {}).get("cached_tokens", 0)
                ev["restored"] = ev["restored"] or n_cached > 0
    json.dump(ev, open(outfile, "w"), indent=1)
    print(f"RESTORE LOADED={ev.get('restored')}")
    for h in hits[-5:]:
        print("  " + h)


# ---- report ---------------------------------------------------------------------------
def toks(resp):
    # chat-completions responses only carry token ids when "verbose": true puts the
    # native fields under __verbose (see server-task.cpp to_json_oaicompat_chat).
    t = resp.get("tokens") or (resp.get("__verbose") or {}).get("tokens") or []
    return t


def text(resp):
    if "__verbose" in resp:
        return (resp["__verbose"] or {}).get("content") or ""
    return reply_text(resp)


def finish(resp):
    return (resp.get("choices") or [{}])[0].get("finish_reason")


def load(outdir, tag):
    d = {}
    for name, _ in prompts():
        p = os.path.join(outdir, f"{tag}-{name}.resp.json")
        if os.path.exists(p):
            d[name] = json.load(open(p))
        else:
            d[name] = {"__error__": "missing response file"}
    return d


def cmp_row(arm, name, ref, got):
    """Returns (arm, name, verdict, detail)."""
    if "__error__" in ref:
        return (arm, name, "VOID", f"reference error: {ref['__error__']}")
    if "__error__" in got:
        return (arm, name, "VOID", f"arm error: {got['__error__']}")
    a, b = toks(ref), toks(got)
    if not a and not b:
        return (arm, name, "VOID", "no token ids in either response (return_tokens unsupported?)")
    first = None
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            first = i
            break
    if first is None and len(a) != len(b):
        first = min(len(a), len(b))
    if finish(ref) != finish(got) and first is None:
        return (arm, name, "FAIL", f"finish_reason {finish(ref)} vs {finish(got)}, ids equal len={len(a)}")
    if first is not None:
        lo = max(0, first - 2)
        ca, cb = a[lo:first + 2], b[lo:first + 2]
        ta = text(ref)[:60].replace("\n", " ")
        tb = text(got)[:60].replace("\n", " ")
        return (arm, name, "FAIL",
                f"@{first} ref={a[first] if first < len(a) else '-'} got={b[first] if first < len(b) else '-'} "
                f"len={len(a)}/{len(b)} ctx ref={ca} got={cb} text ref={ta!r} got={tb!r}")
    return (arm, name, "PASS", f"len={len(a)} tokens finish={finish(ref)}")


def ph_report(outdir):
    rows = []
    off = load(outdir, "off")
    draft = load(outdir, "draft")
    off2 = load(outdir, "off2")

    # DRAFT arm is VOID unless drafting actually engaged on this run: with no
    # acceptance the comparison would be trivial (CLAUDE.md, performance rule 2).
    engfile = os.path.join(outdir, "draft-engagement.json")
    engaged = False
    if os.path.exists(engfile):
        engaged = json.load(open(engfile)).get("engaged", False)
    if engaged:
        for name, _ in prompts():
            rows.append(cmp_row("DRAFT", name, off.get(name, {"__error__": "missing"}), draft.get(name, {"__error__": "missing"})))
    else:
        for name, _ in prompts():
            rows.append(("DRAFT", name, "VOID", "no draft acceptance lines (drafted=0/accepted=0); the DRAFT arm is trivial"))

    # concurrency: each prompt sent at once must equal its solo run in the same server
    for name, _ in CONC:
        solo = os.path.join(outdir, f"draft-{name}-solo.resp.json")
        conc = os.path.join(outdir, f"draft-{name}-conc.resp.json")
        if not (os.path.exists(solo) and os.path.exists(conc)):
            rows.append(("CONCURRENT", name, "VOID", "missing solo/conc response"))
            continue
        rows.append(cmp_row("CONCURRENT", name, json.load(open(solo)), json.load(open(conc))))

    # RESUME: turn 3 resumed vs turn 3 control
    ctl = os.path.join(outdir, "conv-control-turn3.resp.json")
    res = os.path.join(outdir, "conv-resume-turn3.resp.json")
    if not (os.path.exists(ctl) and os.path.exists(res)):
        rows.append(("RESUME", "turn3", "VOID", "missing resume turn3 response"))
    else:
        c = json.load(open(ctl))
        r = json.load(open(res))
        # confirm the restore happened
        ev = os.path.join(outdir, "restore-evidence.json")
        restored = False
        if os.path.exists(ev):
            restored = json.load(open(ev)).get("restored", False)
        if not restored:
            rows.append(("RESUME", "turn3", "VOID", "no restore line in the restarted server log"))
        else:
            rows.append(cmp_row("RESUME", "turn3", c, r))

    # determinism control: OFF vs OFF2
    for name, _ in prompts():
        if name in off and name in off2:
            rows.append(cmp_row("OFF2", name, off.get(name, {"__error__": "missing"}), off2.get(name, {"__error__": "missing"})))

    print("arm\tprompt\tverdict\tdetail")
    rc = 0
    for r in rows:
        print("\t".join(str(x) for x in r))
        if r[2] == "FAIL":
            rc = 1
        elif r[2] == "VOID" and r[0] in ("DRAFT", "CONCURRENT", "RESUME"):
            # a VOID arm does not make the gate fail, but the table must show it
            pass
    return rc


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "prompts":
        ph_prompts(sys.argv[2], sys.argv[3])
    elif cmd == "draft-engagement":
        ph_draft_engagement(sys.argv[2], sys.argv[3])
    elif cmd == "concurrent-solos":
        ph_concurrent_solos(sys.argv[2], sys.argv[3])
    elif cmd == "concurrent-pair":
        ph_concurrent_pair(sys.argv[2], sys.argv[3])
    elif cmd == "conv-control":
        ph_conv_control(sys.argv[2])
    elif cmd == "conv-first2":
        ph_conv_first2(sys.argv[2])
    elif cmd == "conv-restore":
        ph_conv_restore(sys.argv[2])
    elif cmd == "restore-evidence":
        ph_restore_evidence(sys.argv[2], sys.argv[3])
    elif cmd == "report":
        sys.exit(ph_report(sys.argv[2]))
    else:
        print("unknown phase", cmd, file=sys.stderr)
        sys.exit(2)