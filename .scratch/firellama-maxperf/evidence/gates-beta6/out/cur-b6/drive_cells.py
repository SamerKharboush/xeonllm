import json, sys, threading, http.client, time

HOST, PORT, MODEL, OUT, PARALLEL = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], int(sys.argv[5])
RUN = sys.argv[6]  # <model stem>-<label>, names this run's answer files
TIMEOUT = int(sys.argv[7])  # seconds per request; -ngl 0 on a large model prefills slowly
ONLY = sys.argv[8].split()  # run only these cells (empty: all)

def save():
    # after every cell, so a run that is stopped keeps the answers it finished
    with open(f"{OUT}/{RUN}.answers.json", "w") as f:
        json.dump(dict(answers), f, ensure_ascii=False, indent=1)
    with open(f"{OUT}/{RUN}.answers.txt", "w") as f:
        for name, text in answers:
            f.write(f"== {name}\n{text[-400:]}\n\n".replace("\r", " "))

def wanted(name):
    return not ONLY or name in ONLY
results = []
answers = []

def add(name, status, note, ptok):
    # print each cell as it lands so a stall leaves the finished cells on disk
    print(f"{name}\t{status}\t{note}\t{ptok}", flush=True)

def post(payload, timeout=TIMEOUT):
    c = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    body = json.dumps(payload)
    c.request("POST", "/v1/chat/completions", body, {"Content-Type": "application/json"})
    r = c.getresponse()
    data = r.read()
    c.close()
    return r.status, data

def cell(name, payload, want_tool=False):
    if not wanted(name):
        return None
    t0 = time.time()
    try:
        status, data = post(payload)
        js = json.loads(data) if data else {}
        if status != 200:
            add(name, "FAIL", f"HTTP {status}: {data[:200]!r}", 0)
            return None
        ch = js.get("choices", [{}])[0]
        msg = ch.get("message", {})
        text = msg.get("content") or msg.get("reasoning_content") or ""
        calls = msg.get("tool_calls") or []
        ptok = js.get("usage", {}).get("prompt_tokens", 0)
        ctok = js.get("usage", {}).get("completion_tokens", 0)
        ok = bool(text.strip()) and (ctok >= 1)
        if want_tool and not calls:
            add(name, "FAIL", "no tool_calls in the answer", ptok)
            return None
        if not ok:
            add(name, "FAIL", f"empty answer (prompt {ptok}, completion {ctok})", ptok)
            return None
        # the full greedy text, reasoning first, so a thinking model is compared on all of it
        answers.append((name, (msg.get("reasoning_content") or "") + "\n--\n" + (msg.get("content") or "")))
        save()
        add(name, "PASS", f"prompt_tokens={ptok} completion_tokens={ctok} {time.time()-t0:.1f}s", ptok)
        return js
    except Exception as e:
        add(name, "FAIL", f"{type(e).__name__}: {e}", 0)
        return None

def band(tokens, topic):
    # ~4 chars per token of English prose
    words = ("the quick brown fox jumps over the lazy dog while the compiler waits for the "
             "next token and the gpu finishes its tile " * (tokens // 18 + 2))
    prompt = f"{topic}\n\n{words}\n\nIn one word, what colour is the sky?"
    return {"model": MODEL, "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 64, "temperature": 0.0, "stream": False}

TOPIC = "You are a terse assistant. Read the text and answer the final question."

for t in (16, 300, 450, 520, 1100, 4200, 8300):
    cell(f"band{t}", band(t, TOPIC))

# six turns that reuse the cache
msgs = []
for i in range(6):
    msgs.append({"role": "user", "content": f"Turn {i}: name a colour (one word). " + "filler " * 200})
    cell(f"conv6-turn{i}", {"model": MODEL, "messages": msgs, "max_tokens": 64, "temperature": 0.0})
    msgs.append({"role": "assistant", "content": "blue"})

# a prompt past the cache window, then a small one: the cache must evict and still answer
cell("evict", band(16000, TOPIC))
cell("after-evict", band(32, TOPIC))

# tools
cell("tools", {"model": MODEL,
               "messages": [{"role": "user", "content": "What is the weather in Lisbon? Use the tool."}],
               "tools": [{"type": "function", "function": {
                   "name": "get_weather", "description": "Get the current weather",
                   "parameters": {"type": "object", "properties": {"city": {"type": "string"}},
                                  "required": ["city"]}}}],
               # a thinking model plans the call first; 128 tokens ended Nemotron mid-plan
               "tool_choice": "auto", "max_tokens": 512, "temperature": 0.0}, want_tool=True)

# two concurrent requests
if not wanted("parallel2"):
    pass
elif PARALLEL >= 2:
    out = []
    def one(i):
        out.append((i, post(band(220, TOPIC))[0]))
    ts = [threading.Thread(target=one, args=(i,)) for i in range(2)]
    [t.start() for t in ts]; [t.join() for t in ts]
    ok = len(out) == 2 and all(s == 200 for _, s in out)
    add("parallel2", "PASS" if ok else "FAIL", f"statuses={out}", 0)
else:
    add("parallel2", "SKIP", f"--parallel {PARALLEL} does not allow it", 0)

# a cancelled stream, then a new request
try:
    if not wanted("cancel-stream"):
        raise StopIteration
    c = http.client.HTTPConnection(HOST, PORT, timeout=30)
    c.request("POST", "/v1/chat/completions",
              json.dumps({"model": MODEL, "messages": [{"role": "user", "content": "Write a very long essay about the sea."}],
                          "max_tokens": 4096, "stream": True}),
              {"Content-Type": "application/json"})
    r = c.getresponse()
    r.read(64)
    c.close()
    add("cancel-stream", "PASS", "stream closed after 64 bytes", 0)
except StopIteration:
    pass
except Exception as e:
    add("cancel-stream", "FAIL", f"{type(e).__name__}: {e}", 0)
cell("after-cancel", band(64, TOPIC))

results = []  # each cell already printed; keep the list shape for the caller
