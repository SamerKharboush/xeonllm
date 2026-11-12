# 17: GCN mat-vec: per-op decode profile, then a load-shape kernel
Type: task · Status: step 1 done; kernel work moved after beta 8
See beta7 ticket 07 and its 2026-11-07 comment (rows-per-wave already tuned in-tree; Mocca run 1 rejected).

## 2026-11-12: step 1 (profile) done
See `evidence/17/RESULT.md` (orchestrator review at the end). Measured mat-vec shapes read 34-52 GB/s alone; the kernel is the limit. Kernel work (load shape, repack) is not in beta 8.
