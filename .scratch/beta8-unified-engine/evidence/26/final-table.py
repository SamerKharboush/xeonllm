import json, hashlib, os
E="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/26"
G="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8"
B7="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta7/out2/set"
S="ornith-1.0-35b-Q6_K"
def L(p): return json.load(open(p)) if os.path.exists(p) else None
refs={"beta8-tensor":f"{G}/out/set/{S}/{S}-tensor.answers.json",
      "beta8-draft":f"{G}/out/set/{S}/{S}-draft.answers.json",
      "beta7-draft":f"{B7}/{S}/{S}-draft.answers.json"}
R={k:L(v) for k,v in refs.items()}
def fd(a,b):
    n=min(len(a),len(b)); return next((i for i in range(n) if a[i]!=b[i]), n)
def run(l):
    m="tensor" if l[0]=="t" else "draft"
    return L(f"{E}/{l}/{S}-{m}.answers.json"), m
labs=["d1","d2","d3","t1","t2","t3","b7d","moe","nopo","nopo2","ub512"]
o=[]
o.append("RUNS (all beta 8 unless noted; d1/d2/d3/t1/t2/t3 = repeats)")
o.append("")
o.append("label   mode   engine        band16   band300  band1100 len sha       vs beta8-tensor")
for l in labs:
    d,m=run(l)
    eng="beta.7" if l=="b7d" else "beta.8"
    if not d: o.append(f"{l:7s} {m:6s} {eng:8s} MISSING"); continue
    a=d.get("band1100")
    h=hashlib.sha1(a.encode()).hexdigest()[:8] if a else "-"
    t=R["beta8-tensor"]["band1100"]
    vs="SAME" if a==t else "diff@%d"%fd(a,t)
    def s(c):
        if c not in d: return "n/a"
        return "SAME" if d[c]==R["beta8-tensor"][c] else "DIFF"
    o.append(f"{l:7s} {m:6s} {eng:8s} {s('band16'):8s} {s('band300'):8s} {len(a):4d} {h}  {vs}")
o.append("")
o.append("REFERENCES")
for k,v in R.items():
    o.append(f"  {k:12s} band1100 len={len(v['band1100']):3d} sha={hashlib.sha1(v['band1100'].encode()).hexdigest()[:8]}")
o.append("")
o.append("DISTINCT band1100 OUTPUTS SEEN (sha -> runs)")
g={}
for l in labs:
    d,m=run(l)
    if not d: continue
    h=hashlib.sha1(d["band1100"].encode()).hexdigest()[:8]
    g.setdefault(h,[]).append(f"{l}({m})")
for k,v in R.items():
    h=hashlib.sha1(v["band1100"].encode()).hexdigest()[:8]
    g.setdefault(h,[]).append(f"REF:{k}")
for h,v in sorted(g.items(), key=lambda x:-len(x[1])):
    first=[d for d in [run(l)[0] for l in labs if run(l)[0]] ]
    o.append(f"  {h} n={len(v):2d}  {', '.join(v)}")
open(f"{E}/final-table.txt","w").write("\n".join(o)+"\n")
print("\n".join(o))
