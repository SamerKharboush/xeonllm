// Uncached read rate of one file (beta8 ticket 07): sequential, then 2 MiB blocks at random
// 2 MiB-aligned offsets. F_NOCACHE on the descriptor; before each phase the region's page-cache
// residency is reported (mincore over an mmap), so a cached read cannot pass for a disk read.
//
//   cc -O2 tools/storage-probe/nvmeread.c -o nvmeread
//   ./nvmeread <file> <seq start GiB> <seq GiB> <random blocks> <seed>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

// fraction of pages in [off, off+len) resident in the page cache
static double resident(int fd, off_t off, size_t len) {
    void * p = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, off);
    if (p == MAP_FAILED) return -1;
    size_t pg = getpagesize(), n = (len + pg - 1) / pg, r = 0;
    char * v = malloc(n);
    if (mincore(p, len, v) == 0) for (size_t i = 0; i < n; i++) r += v[i] & 1;
    free(v); munmap(p, len);
    return (double) r / n;
}

int main(int argc, char ** argv) {
    if (argc < 6) { fprintf(stderr, "usage: %s file seqStartGiB seqGiB randomBlocks seed\n", argv[0]); return 2; }
    const off_t G = 1LL << 30, B2 = 2 << 20, CH = 8 << 20;
    off_t s0 = atoll(argv[2]) * G, sl = atoll(argv[3]) * G;
    int nr = atoi(argv[4]); srand48(atol(argv[5]));
    int fd = open(argv[1], O_RDONLY); if (fd < 0) { perror("open"); return 1; }
    fcntl(fd, F_NOCACHE, 1);
    struct stat st; fstat(fd, &st);
    if (s0 + sl > st.st_size) { fprintf(stderr, "range past end\n"); return 1; }
    char * buf; posix_memalign((void **) &buf, 1 << 14, CH);

    printf("file %lld bytes; seq [%lld GiB, +%lld GiB) resident %.4f\n", (long long) st.st_size,
           (long long) (s0 / G), (long long) (sl / G), resident(fd, s0, sl));
    double t = now();
    for (off_t o = s0; o < s0 + sl; o += CH) if (pread(fd, buf, CH, o) != CH) { perror("pread"); return 1; }
    t = now() - t;
    printf("sequential 8 MiB reads: %.3f s  %.3f GB/s\n", t, sl / t / 1e9);

    // random 2 MiB-aligned blocks outside the sequential range
    off_t nb = st.st_size / B2, * offs = malloc(nr * sizeof(off_t));
    double res = 0;
    for (int i = 0; i < nr; i++) {
        off_t o; do { o = (off_t) (drand48() * nb) * B2; } while ((o >= s0 && o < s0 + sl) || o + B2 > st.st_size);
        offs[i] = o; res += resident(fd, o, B2);
    }
    printf("random: %d blocks of 2 MiB, mean resident before %.4f\n", nr, res / nr);
    t = now();
    for (int i = 0; i < nr; i++) if (pread(fd, buf, B2, offs[i]) != B2) { perror("pread"); return 1; }
    t = now() - t;
    printf("random 2 MiB reads: %.3f s  %.3f GB/s  %.2f ms/block\n", t, (double) nr * B2 / t / 1e9, t / nr * 1e3);
    return 0;
}
