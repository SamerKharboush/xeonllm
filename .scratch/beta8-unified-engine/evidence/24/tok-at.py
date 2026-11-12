import struct

# token id of the answer text "@", from the model's own GGUF vocab (no GPU)
f = open('/Users/sam/models/Qwen3-14B-Q4_K_M.gguf', 'rb')
magic, ver, nt, nkv = struct.unpack('<4sIQQ', f.read(24))


def rd(fmt):
    s = struct.calcsize(fmt)
    return struct.unpack(fmt, f.read(s))[0]


def rstr():
    return f.read(rd('<Q'))


toks = None
for _ in range(nkv):
    k = rstr()
    t = rd('<I')
    if k == b'tokenizer.ggml.tokens':
        rd('<I')
        toks = [rstr().decode('utf-8', 'replace') for _ in range(rd('<Q'))]
    elif t == 8:
        rstr()
    elif t == 9:
        et = rd('<I')
        n = rd('<Q')
        for _ in range(n):
            if et == 8:
                rstr()
            elif et == 5:
                rd('<i')
    elif t in (4, 5):
        rd('<I')
    elif t == 6:
        rd('<f')
    elif t == 7:
        rd('<?')

print('token 0      ', repr(toks[0]))
print('token 31     ', repr(toks[31]))
print("ids for '@'  ", [i for i, x in enumerate(toks) if x == '@'])