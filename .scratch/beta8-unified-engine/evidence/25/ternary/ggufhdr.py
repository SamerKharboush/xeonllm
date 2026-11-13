import struct, sys
p = sys.argv[1]
f = open(p, 'rb')
f.read(4)
ver = struct.unpack('<I', f.read(4))[0]
nt = struct.unpack('<Q', f.read(8))[0]
nkv = struct.unpack('<Q', f.read(8))[0]
SZ = {0:1,1:1,2:2,3:2,4:4,5:4,6:4,7:1,10:8,11:8,12:8}
def rs():
    n = struct.unpack('<Q', f.read(8))[0]
    return f.read(n).decode('utf8', 'replace')
def rv(t):
    if t == 8:
        return rs()
    if t == 9:
        at = struct.unpack('<I', f.read(4))[0]
        n = struct.unpack('<Q', f.read(8))[0]
        return [rs() if at == 8 else f.read(SZ[at]) for _ in range(n)]
    return f.read(SZ[t])
out = {}
for _ in range(nkv):
    k = rs()
    t = struct.unpack('<I', f.read(4))[0]
    out[k] = rv(t)
want = [k for k in out if any(s in k for s in ('architecture','head','block_count','expert','key_length','embedding_length','attention','rope'))]
for k in sorted(want):
    v = out[k]
    if isinstance(v, int):
        print(k, '=', v)
    else:
        print(k, '=', v)