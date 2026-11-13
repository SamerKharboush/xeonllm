import json, os
E="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/26"
G="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8"
B7="/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta7/out2/set"
S="ornith-1.0-35b-Q6_K"
def L(p): return json.load(open(p)) if os.path.exists(p) else None
R={k:L(v) for k,v in {
 "beta8-tensor":f"{G}/out/set/{S}/{S}-tensor.answers.json",
 "beta8-draft":f"{G}/out/set/{S}/{S}-draft.answers.json",
 "beta7-draft":f"{B7}/{S}/{S}-draft.answers.json"}.items()}
labs=["d1","d2","t1","b7d","moe","nopo","ub512"]
D={l:L(f"{E}/{l}/{S}-"+("tensor" if l=="t1" else "draft")+".answers.json") for l in labs}
cells=["band16","band300","band1100"]
def fd(a,b):
    n=min(len(a),len(b)); return next((i for i in range(n) if a[i]!=b[i]), n)
o=[]
o.append("A. determinism: d1 vs d2 (same command, twice, draft)")
for c in cells:
    a,b=D["d1"].get(c),D["d2"].get(c)
    o.append(f"   {c:9s} {'IDENTICAL' if a==b else 'DIFF'} len {len(a)}/{len(b)}" + ("" if a==b else f" diff@{fd(a,b)}"))
o.append("")
o.append("B. every run vs beta8-tensor reference (ticket 26: draft vs tensor first token)")
o.append(f"   {'label':7s} {'band16':>22s} {'band300':>22s} {'band1100':>22s}")
for l in labs:
    row=[]
    for c in cells:
        a=D[l].get(c)
        row.append("MISSING" if a is None else ("IDENTICAL" if a==R["beta8-tensor"][c] else "DIFF@%d %d/%d"%(fd(a,R["beta8-tensor"][c]),len(a),len(R["beta8-tensor"][c]))))
    o.append(f"   {l:7s} {row[0]:>22s} {row[1]:>22s} {row[2]:>22s}")
o.append("")
o.append("C. band1100 vs beta8-draft reference (the wrong text)")
for l in ["d1","d2","t1","b7d","moe","nopo","ub512"]:
    a=D[l].get("band1100"); r=R["beta8-draft"]["band1100"]
    o.append(f"   {l:7s} len={len(a):3d} {'SAME-as-wrong' if a==r else 'diff@%d'%fd(a,r)}")
open(f"{E}/checks.txt","w").write("\n".join(o)+"\n")
