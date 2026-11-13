import json, sys, os
E = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(E, "..", "..", "..", "..", ".."))
B7 = os.path.join(ROOT, ".scratch/beta8-unified-engine/evidence/gates-beta7/out2/set")
B8 = os.path.join(ROOT, ".scratch/beta8-unified-engine/evidence/gates-beta8/out/set")


def load(p):
    with open(p) as f:
        return json.load(f)


def cmp(a, b):
    if a == b:
        return "IDENTICAL"
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return "DIFF@%d (len %d vs %d)" % (i, len(a), len(b))
    return "DIFF (prefix, len %d vs %d)" % (len(a), len(b))


for stem in sys.argv[1:]:
    cur = load(os.path.join(E, stem, "%s-ngl0.answers.json" % stem))
    ref7 = load(os.path.join(B7, stem, "%s-ngl0.answers.json" % stem))
    ref8 = load(os.path.join(B8, stem, "%s-ngl0.answers.json" % stem))
    print(stem)
    for cell in ("band16", "band300", "band1100"):
        print("%s\t%s\t%s" % (cell, cmp(cur[cell], ref7[cell]), cmp(cur[cell], ref8[cell])))
    print()