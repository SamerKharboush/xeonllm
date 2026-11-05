// Distinct experts selected per MoE layer over the first k tokens of one batch (beta8 ticket 08).
// For each k in {1,2,4,8}: the union of experts chosen by tokens 0..k-1, per layer, averaged over
// layers. Host only (n_gpu_layers = 0), one decode of the prompt, greedy nothing (no sampling).
//
//   expert_count <model.gguf> "<prompt text>"
#include "llama.h"
#include "ggml.h"
#include "ggml-backend.h"
#include <cstdio>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

struct state {
    std::map<int, std::vector<int32_t>> ids;   // layer -> [n_tokens * n_used]
    std::map<int, int> n_used;
};

static bool cb(struct ggml_tensor * t, bool ask, void * ud) {
    const char * name = ggml_get_name(t);
    if (strncmp(name, "ffn_moe_topk-", 13) != 0) return false;
    if (ask) return true;  // we want this tensor's data
    auto * s = (state *) ud;
    const int il = atoi(name + 13);
    // ids: [n_used, n_tokens], i32
    const int64_t n_used = t->ne[0], n_tok = t->ne[1];
    // a view of the argsort over every expert: row t starts at t*nb[1], only n_used ids each
    std::vector<int32_t> buf(n_used * n_tok);
    for (int64_t r = 0; r < n_tok; ++r) {
        ggml_backend_tensor_get(t, buf.data() + r * n_used, r * t->nb[1], n_used * sizeof(int32_t));
    }
    s->ids[il] = buf;
    s->n_used[il] = (int) n_used;
    return true;
}

int main(int argc, char ** argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s model.gguf \"prompt\"\n", argv[0]); return 2; }
    llama_backend_init();
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    llama_model * model = llama_model_load_from_file(argv[1], mp);
    if (!model) return 1;
    state st;
    auto cp = llama_context_default_params();
    cp.n_ctx = 1024; cp.n_batch = 512; cp.n_ubatch = 512;
    cp.cb_eval = cb; cp.cb_eval_user_data = &st;
    llama_context * ctx = llama_init_from_model(model, cp);
    const llama_vocab * vocab = llama_model_get_vocab(model);
    std::vector<llama_token> toks(256);
    int n = llama_tokenize(vocab, argv[2], strlen(argv[2]), toks.data(), toks.size(), true, false);
    if (n < 8) { fprintf(stderr, "prompt has %d tokens, need >= 8\n", n); return 1; }
    // windows of 8 consecutive tokens starting at several offsets, so the count is not one window's
    const int win = 8;
    std::map<int, std::vector<double>> per_k;  // k -> per (window, layer) distinct counts
    for (int start = 0; start + win <= n; start += win) {
        llama_memory_clear(llama_get_memory(ctx), true);
        // prefix up to start, then the window, in one batch; only the window's ids are counted
        llama_batch b = llama_batch_get_one(toks.data(), start + win);
        st.ids.clear();
        if (llama_decode(ctx, b) != 0) { fprintf(stderr, "decode failed\n"); return 1; }
        for (auto & [il, v] : st.ids) {
            const int nu = st.n_used[il];
            for (int k : {1, 2, 4, 8}) {
                std::set<int32_t> u;
                for (int t = start; t < start + k; ++t)
                    for (int j = 0; j < nu; ++j) u.insert(v[t * nu + j]);
                per_k[k].push_back((double) u.size());
            }
        }
    }
    int nu = st.n_used.empty() ? 0 : st.n_used.begin()->second;
    printf("prompt tokens %d, experts used per token %d, moe layers %zu\n", n, nu, st.ids.size());
    double d1 = 0;
    for (int k : {1, 2, 4, 8}) {
        auto & v = per_k[k];
        double s = 0, mn = 1e9, mx = 0;
        for (double x : v) { s += x; mn = std::min(mn, x); mx = std::max(mx, x); }
        double m = s / v.size();
        if (k == 1) d1 = m;
        printf("k=%d  distinct experts per layer: mean %.2f (min %.0f, max %.0f, %zu samples)  ratio to k=1: %.3f\n",
               k, m, mn, mx, v.size(), m / d1);
    }
    llama_free(ctx); llama_model_free(model);
    return 0;
}
