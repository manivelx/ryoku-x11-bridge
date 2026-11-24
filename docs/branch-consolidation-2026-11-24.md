# Branch consolidation record — 2026-11-24

This record documents the live branch audit performed before the RXB testing-build phase.
The development tree is authoritative for implementation; main remains the stable baseline.

## Intended permanent branches

- `main`: stable release baseline only.
- `development`: current integration and validation branch.

## Audited remote branches and disposition

| Branch | Head | Unique work relative to development | Disposition |
|---|---|---|---|
| `claude/ci-cleanup-and-bind-vars` | `8400ed60be0ecd065466dd4845a590a987e73402` | Longest-name-first i3 variable expansion and regression test; Quickshell/Xvfb process cleanup and retry behavior. The same implementation is present in development's `config.go`, `config_vars_test.go`, `test-quickshell-i3-smoke.sh`, and `test-rxb-full-shell-xvfb.sh`. | Functionality integrated by equivalent later development commits. Do not merge the branch wholesale: its unique commit also contains generated `__pycache__/*.pyc` files. Those files are not part of the development tree. Record this commit as reviewed; delete branch only after final verification. |
| `claude/full-repo-audit` | `3845bfc4ef839489aaae849ea63ae5cb58533128` | No commits ahead of development; branch is 33 commits behind. | Already integrated through PR #4 into development. |
| `rxb/disposable-install-validation` | `031c1354871105fc9167f25c56393ddb3e73f3b6` | No commits ahead of development; branch is 73 commits behind. | Already integrated into development. |
| `rxb/phase0-ci-and-provider-hardening` | `cc6a4bab22fe9bc6be00d99ba2b9e92f406a59f5` | Four commits: PKGINFO-based package identification; implementation/validation status clarification; phase-zero evidence; pinned-upstream dependency audit. | PKGINFO-based selection is present in development package-safety checks; current development docs and tests are newer and more complete. Do not overwrite them with this older branch snapshot. |
| `recovery/pre-consolidation-ci-cleanup-20261124` | `8400ed60be0ecd065466dd4845a590a987e73402` | Exact duplicate of CI-cleanup branch head. | Recovery duplicate; same disposition as CI-cleanup branch. |
| `recovery/pre-consolidation-development-20261124` | `031c1354871105fc9167f25c56393ddb3e73f3b6` | Exact duplicate of disposable-install-validation head. | Recovery duplicate; already ancestor of development. |
| `recovery/pre-consolidation-full-audit-20261124` | `3845bfc4ef839489aaae849ea63ae5cb58533128` | Exact duplicate of full-repo-audit head. | Recovery duplicate; already ancestor of development. |
| `recovery/pre-consolidation-main-20261124` | `f99237dd1c75c6c5bbad051415ca605214225bc7` | Two commits relative to the old merge base: read-only host preflight addition and an explicit revert keeping it off main until validated. | Main has superseded this snapshot; its net preflight change is reverted. |
| `recovery/pre-consolidation-phase0-20261124` | `cc6a4bab22fe9bc6be00d99ba2b9e92f406a59f5` | Exact duplicate of phase0 branch head. | Recovery duplicate; same disposition as phase0 branch. |

## Main-only history and content

At audit time, main was `f808aa7d9e48d55e980ba47188ba6665c073fce7` and development was `6d0cab5a151f9b2d442b0e87058dd5e6dfb4f73a`.

Main has seven commits not in development's ancestry. They include the read-only preflight addition followed by its revert, stable-baseline README refresh, and licensing-notice commits. The `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md` blobs are identical on main and development. The README intentionally differs: main describes the stable baseline; development describes the active integration candidate. Do not copy main's stable-baseline README over development.

The main-only commits are useful historical provenance even where their final file content is already present on development. Reconcile ancestry without replacing the development tree.

## Integration policy

- Preserve the development tree as the source of truth for current integration work.
- Reconcile main and the phase-zero history into development using a normal ancestry-preserving merge commit whose resulting tree is the reviewed development tree. Do not force-push or rewrite either branch.
- Do not merge the CI-cleanup branch wholesale because its unique commit includes generated Python bytecode. Its useful source/test behavior is already present in development; keep the current tree free of generated caches.
- Keep the stable main branch unchanged until development has passed its release gates.
- Keep recovery references until final branch-list and CI verification is complete.
- No remote branch is deleted by this audit. Final remote cleanup is a separate operation and must be verified against the exact intended two-branch list.

## Important limitations

A passing CI run, disposable Arch transaction, or Xvfb/Xephyr test is not physical acceptance on the target CachyOS machine with NVIDIA GT 740 / legacy 470 driver. Hardware acceptance remains a separate owner-controlled test.
