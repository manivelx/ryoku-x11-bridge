# RXB full repository audit — 2026-11-24

Auditor: Claude (independent review). Audited tree: `development` at `031c1354871105fc9167f25c56393ddb3e73f3b6`
(upstream pin `0bf11741b22f69f22ad2733025671c7d0a5e1a47`). Audit branch: `claude/full-repo-audit`
(based on that exact commit). Nothing was installed on any host, `main` was not touched, no branch was deleted or merged.

**Final readiness decision: READY FOR ISOLATED TESTING ONLY.**
Reasons are in section 13. This is not target-hardware acceptance and not release readiness.

## 1. Executive summary

- No P0 finding. The installer, ownership manifest, rollback and removal logic are careful and well tested in a disposable Arch container.
- The lock stack (earlier audit, already integrated on `development`) is verified against real PAM on an isolated Xephyr display for XSecureLock and i3lock.
- Real-package inspection (new this round) shows the upstream `ryoku` package still ships a root-level `tmpfiles.d` file and a system unit `ryoku-boot-guard.service`, neither forbidden by the package-safety test. Neither is enabled, but the tmpfiles file creates world-writable entries under `/var/lib/ryoku` on the host. Owner decision needed (F1).
- `ryogami` requires `qt6-base>=6.12`. On a host with an older Qt, the install transaction would upgrade Qt as a side effect, which can break the existing Quickshell/BSPWM stack (F2). The preflight now detects this.
- Stale evidence references and badges pointed at a branch scheduled for deletion; fixed.
- Both leftover branches are superseded and can be discarded after archiving (section 7).

## 2. Architecture review (source inspected)

- Overlay approach (patch a pinned upstream in a disposable worktree) is sound and reproducible: `build-rxb-packages.sh` refuses any upstream HEAD other than `UPSTREAM_PIN`, builds in a detached worktree, and refuses to overwrite existing artifacts.
- The i3 provider (`cmd/ryoku-wm-i3`) vendors the upstream keybinding catalogue. **Verified identical** to upstream `ryoku/wm/binds.go` from the `import` block down (diff empty); a CI step now enforces this. The starter i3 config contains no custom `bindsym`; generated bindings come only from the catalogue, and unsupported actions are listed with a reason.
- Services: RXB-owned units (`ryoku-shell-x11.service`, `ryogami-x11.service`, `ryoku-x11-session.target`) are wired only into the dedicated target; `BindsTo=graphical-session.target` follows the sway-session pattern. Units clear `WAYLAND_DISPLAY`/`SWAYSOCK` and read a 0600 session-scoped `EnvironmentFile`. No `systemctl --user import-environment`; no default.target links (tested).
- Session wrapper cleanup: the EXIT trap runs on SIGTERM/SIGHUP/SIGINT (tested with a probe script). SIGKILL cannot be trapped, so a stale target/env file is possible after a hard kill (recovery in section 12).
- `KillMode=process` on the shell units (mirrors upstream) can leave helper children after a unit stop; the session teardown relies on X server exit. Low risk; observe during acceptance.

## 3. Findings

Legend: *Blocks* = blocks the controlled installation test on the owner's PC until resolved/decided.

| ID | Sev | Finding | Blocks |
|----|-----|---------|--------|
| F1 | P2 | Package `ryoku` ships `usr/lib/tmpfiles.d/ryoku.conf` and `usr/lib/systemd/system/ryoku-boot-guard.service` (from upstream `ryoku/cli/systemd/`). tmpfiles creates `/etc/ryoku`, `/var/lib/ryoku`, `/var/lib/ryoku/boot` (mode 1777), `greeter-primary` and `greeter-numlock` (mode 0666) and re-modes `/usr/share/ryoku`; pacman's tmpfiles hook applies it at install and it applies every boot. The unit is inert unless enabled and armed by a packaged update (`ConditionPathExists=/var/lib/ryoku/update-pending.json`). The package-safety test does not forbid either file. The existing Orbital SDDM theme may read the greeter hand-off files (not verified). Contradicts the project goal of not touching host boot/greeter integration. | Yes (owner decision) |
| F2 | P1 | `ryogami` depends on `qt6-base>=6.12`. If the host Qt is older, `pacman -S --needed` for dependencies upgrades Qt (and strictly-versioned Qt packages) as a partial upgrade, risking the existing Quickshell lockscreen and BSPWM stack. | Yes (procedural) |
| F3 | P2 | Conflicting/replaced packages: `ryoku-cursors` replaces+conflicts `bibata-cursor-theme(-bin)`; `gpk` replaces `gpk-bin`; `ryoku-desktop` depends on `power-profiles-daemon` (conflicts with `tlp`, `tuned-ppd`). The preflight did not check these. pacman would prompt, and with `RXB_PACMAN_NOCONFIRM=1` the transaction fails. | Preflight fixed here |
| F4 | P2 | The installer relies on `pacman` prompts for the dependency list and does not print or require review of the dependency transaction plan. `ryoku-desktop`/`ryoku-shell` bring a large dependency set (bluez, nftables, networkmanager, power-profiles-daemon, noto fonts, gpu-screen-recorder, easyeffects, pam-u2f, rtkit, …). None is enabled by RXB, but several ship system units/D-Bus files. | Procedural |
| F5 | P2 | `ryoku` CLI commands (`update`, `doctor`, `svc reconcile`, `boot-guard`) are shipped. The overlay guards the power path; full coverage of every host-mutating subcommand was **not** verified. Operators must not run them on the host. | Yes (document) |
| F6 | P2 | XSecureLock is absent on the target (i3lock only). The i3lock fallback passed real-PAM tests in Xephyr, but XSecureLock is the stronger design (separate auth helper). Installing it is an owner action; RXB must not install it silently. | No |
| F7 | P2 | GT 740 / NVIDIA 470 / Picom: no target evidence. Starter config launches `picom --daemon` only if Picom is installed and not already running, reusing the existing config. | Test plan only |
| F8 | P3 | README badges targeted `rxb/disposable-install-validation` (to be deleted) and several rows cited a stale "current PR head `8350cd29`". Fixed in this audit. | No |
| F9 | P3 | Visible side effects on the BSPWM desktop: new application entries (`ryoku-hub`, `ryostore`, `ryovm`, `compress-video`, `install-app`, `ryoku-nvim`), `/etc/ryoku-release`, `Bibata-*` cursor themes, a pacman keyring dir (`usr/share/pacman/keyrings/ryoku*`; the scriptlet only populates if the key is already known). Cosmetic. | No |
| F10 | P3 | Some Go sources lack SPDX headers; root `LICENSE` is GPL-3.0 while upstream's PKGBUILD says `GPL-3.0-or-later`. The notice tree and iNiR section 7 terms are shipped and tested. | No |
| F11 | P3 | `inventory-rxb-packages.sh` (added here) is report-only. It should become an allowlist gate after F1 is decided. | No |

Earlier lock findings (PATH-resolved locker, false-success on repeat requests, `/proc` scan defeated by non-dumpable XSecureLock, `:0`/`:0.0` double locks, stray `WAYLAND_DISPLAY` routing) are fixed and integrated; see `docs/x11-lock-security-audit.md`.

## 4. Security review

- Locking: XSecureLock preferred, i3lock fallback, both from absolute `/usr/bin`; per-display `flock` inherited by the locker; state record `<pid> <starttime>` verified against `/proc` (PID-reuse safe); success is never reported without a verified locker. Evidence: Xephyr + real `pam_unix` (default and isolated PAM service), deny-all PAM negative control, i3lock fallback, repeat requests, cleanup.
- Not covered by any test: real keyboard/pointer grab behaviour on hardware, VT switching, multi-monitor coverage, crash/recovery on a real session. Ctrl+Alt+Fn VT switching is an Xorg/kernel matter; it exposes a login prompt, not the locked session.
- Suspend/hibernate: refused with exit 69 on X11, including with a stray `WAYLAND_DISPLAY`.
- Installer/removal: refuse symlinked or group/other-accessible manifest paths; manifest is root-owned 0600 in a 0700 directory; package names validated; removal acts only on manifest entries.
- Session env: runtime files are created with `rm` + `noclobber`/umask 077 and symlink refusal; values with quotes/backslashes/newlines are rejected.

## 5. Packaging and installation review

Inspected from the real built packages (CI log of run 45288196496 on commit `db8c490`, which differs from `031c135` only by the added inventory step): 12 packages (`gpk`, `ryogami`, `ryoku`, `ryoku-blobs`, `ryoku-cursor-material`, `ryoku-cursors`, `ryoku-desktop`, `ryoku-desktop-i3`, `ryoku-hub`, `ryoku-keyring`, `ryoku-palette-bridge`, `ryoku-shell`).

- Host-sensitive files outside RXB/Ryoku-private paths: `etc/ryoku-release`; six `.desktop` files and three hicolor icons (`ryoku-desktop`); `usr/share/xsessions/ryoku-x11.desktop` (`ryoku-desktop-i3`); keyring files; **and F1** (`ryoku`). No SDDM, udev, polkit, logind, pacman-hook, modprobe, sysusers, environment.d or boot paths are present — the overlay's gating worked.
- Scriptlets: only `ryoku-keyring` (conditional `pacman-key --populate`) and `ryoku-desktop` (icon/desktop database refresh and a hint).
- Dependencies: the safety test forbids DKMS and Wayland-only helper stacks. `dkms` appears only as an optdepend.
- Transaction tests cover: install, synthetic upgrade, rejected (corrupt) transaction, rollback, removal, manifest/symlink attacks. Not covered: interrupted install (SIGKILL mid-transaction), a pre-existing conflicting package, a stale-Qt host.

## 6. Build and test results (evidence levels)

| Level | Result |
|-------|--------|
| 1 Source inspected | Whole repository, installer, session scripts, units, lock wrappers, overlay highlights, upstream package payloads. |
| 2 Implemented | Provider, overlay, session, installer/remover, lock wrappers. |
| 3 Build passed | CI "pinned upstream integration" `arch-package-build` passed on `031c135` and on the audit branch; packages inventoried. |
| 4 Unit/regression | Passed in CI on `031c135` (i3 provider; overlay-and-go-tests). Run locally by the auditor on this tree: `gofmt -l` clean, `go vet`, `go test -race` for `cmd/ryoku-wm-i3`, Python unit tests (21), README check, `bash -n` on the changed shell scripts. |
| 5 Xvfb/Xephyr | CI: full-shell Xvfb+i3 acceptance, install transaction, "x11 lock PAM acceptance" passed on `031c135`. |
| 6 Target hardware | **Not performed.** |
| 7 Owner confirmed | **Not performed.** |

Commands: see `.github/workflows/*.yml`; the exact commands run are the CI steps. Locally: `cd cmd/ryoku-wm-i3 && gofmt -l . && go vet ./... && go test -race ./...`; `python3 -m unittest discover -s tests`; `python3 scripts/test-rxb-readme.py`.
Note: CI runs for `031c135` were recorded under the old branch name `rxb/disposable-install-validation`; `development` itself has no workflow runs yet.

## 7. Remaining unique branch review

| Branch | Relation | Unique content | Recommendation |
|--------|----------|----------------|----------------|
| `claude/ci-cleanup-and-bind-vars` (`8400ed6`) | 1 ahead / 124 behind | Variable expansion fix (`expandI3Variables`, longest-first) + test; Xvfb test cleanup retry; **8 committed `.pyc` files**. | **Discard.** Both fixes already exist on `development` (`expandI3Variables` in `config.go`, `config_vars_test.go`, `rm -rf` retry in both smoke scripts). The `.pyc` files are junk. |
| `rxb/phase0-ci-and-provider-hardening` (`cc6a4ba`) | No merge-base with `development`; 146 ahead / 180 behind; 2026-11-21..22 | Older snapshot. Tree diff: development contains ~40 more files (installer, remover, preflight, lock tests, readme test, etc.). Only two files exist solely here: `payload/systemd/ryoku-shell.service.d/10-rxb-x11.conf` and `ryogami.service.d/10-rxb-x11.conf` — global drop-ins into upstream units, a design the current package-safety test deliberately rejects. | **Discard after archiving.** I compared trees and files, and skimmed what differs; I did not review every one of the 146 commits individually. |
| `rxb/disposable-install-validation` | Identical to `development` (`031c135`) | None | Delete when the owner is ready; first update README badge branch (done on the audit branch). |

Before deleting either branch, create a tag (for example `archive/phase0-cc6a4ba`, `archive/ci-cleanup-8400ed6`). I did not delete or tag anything.

## 8. Documentation and licensing review

- README claims are conservative ("not ready for installation on a daily-use machine") and enforced by `scripts/test-rxb-readme.py`. Fixed: badge branch and stale commit references. The README table still reads as evidence for the CI environment, not hardware.
- Licensing: GPL-3.0 text, upstream NOTICE preserved, full upstream notice/licence tree shipped in the package and tested (including iNiR section 7 terms and OFL fonts). Upstream images in README are hot-linked and labelled as upstream references.
- Gaps: SPDX headers (F10); the install guide should mention F1/F2 and the "do not run `ryoku update/doctor`" rule (see section 9).

## 9. Required corrections

Before a controlled PC installation:
1. Decide F1: either (a) gate `ryoku-boot-guard.service` and `ryoku.tmpfiles.conf` out of the RXB `ryoku` package in the overlay (and add them to the forbidden list in `test-rxb-package-safety.sh`; also verify the shell daemon tolerates a missing `/var/lib/ryoku`), or (b) accept and document them. This changes packaging and needs the owner's approval, so I did not implement it.
2. Document F5: do not run `ryoku update`, `ryoku doctor` or `ryoku-host` subcommands on the host; audit/gate them.
3. Add tests for an interrupted install and for a pre-existing conflicting package.
4. Turn the package inventory into an allowlist gate after step 1.
5. Optionally add SPDX headers.

Done in this audit (low-risk): extended read-only host preflight; catalogue-drift CI check; package-inventory CI step; README/roadmap reference fixes.

## 10. Installation-test risk assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Partial Qt upgrade breaks Quickshell/BSPWM | Medium if the host is not fully updated | High | Full update first, reboot, re-verify BSPWM, then preflight (checks Qt and pending updates). |
| Conflicting package removal prompt | Low | Medium | Preflight; never use `RXB_PACMAN_NOCONFIRM=1` on the host. |
| tmpfiles/boot-guard side effects (F1) | Certain if installed as built | Low–Medium | Owner decision before install. |
| New dependencies (power-profiles-daemon, bluez, networkmanager, …) change system behaviour | Medium | Medium | Review the dependency plan (below) before confirming. |
| Lock misbehaviour on the GT 740 stack | Unknown | High (session strand) | Second login path (TTY) confirmed first; test lock only with recovery access. |
| Black screen / rendering fault with NVIDIA 470 + Picom | Unknown | Medium | BSPWM remains selectable; keep Picom config unchanged. |

No step touches the kernel, bootloader, EFI, NVIDIA driver or SDDM configuration.

## 11. Safe installation-test procedure (for the owner, later, after the corrections above and with explicit approval)

Prefer a VM or a dedicated spare installation first. On the real PC, only after F1 is decided:

1. Create a restore point (Snapper/BTRFS snapshot or full backup). Confirm you can reach a TTY (Ctrl+Alt+F3) and log in.
2. `sudo pacman -Syu`, reboot, and confirm the BSPWM session, SDDM Orbital theme and lockscreen work.
3. From the existing BSPWM session as your normal user: `bash scripts/rxb-host-preflight.sh`. Stop on any `[FAIL]`; read every `[WARN]` (especially Qt, pending updates, conflicts, lock stack).
4. Verify the bundle: `sha256sum -c SHA256SUMS` inside the extracted `rxb-install-bundle`.
5. Review the dependency plan without installing: `pacman -Sp --print-format '%n %v' <external dependencies>` or run the installer without `RXB_PACMAN_NOCONFIRM` and read pacman's list before answering. Abort if it lists the kernel, NVIDIA, SDDM, `quickshell`/Qt upgrades or removals.
6. Install: `bash scripts/install-rxb-packages.sh` (answer pacman's prompt only after reading it).
7. Log out. At SDDM choose **Ryoku (X11 / i3)**. First test with BSPWM available as the fallback; do not change SDDM settings.
8. Check: i3 running, `systemctl --user status ryoku-x11-session.target`, shell visible, panels respond.
9. Lock test: from the RXB session only, with a second path available (TTY login already open on another VT). Lock; wrong password must stay locked; correct password must unlock.
10. Log out; confirm SDDM returns and BSPWM still starts normally.
11. Record results with `scripts/collect-x11-hardware-evidence.sh` and the acceptance checklist. Do not enable suspend/hibernate.

## 12. Rollback and recovery

- Normal rollback: log out, choose BSPWM; `bash scripts/remove-rxb-packages.sh` (removes only packages recorded in `/var/lib/rxb/installed-packages`). Review pacman's removal list before confirming. User config under `~/.config/ryoku-x11` is kept; remove it manually after a backup.
- If the RXB session fails to start: pick BSPWM at SDDM; if SDDM itself misbehaves, use a TTY and `sudo systemctl restart sddm`. The restore snapshot is the last resort.
- Stale RXB services after a hard kill: `systemctl --user stop ryoku-x11-session.target` and `rm -f "$XDG_RUNTIME_DIR/ryoku-x11-session.env"`.
- Stuck lock (screen locked, password not accepted): switch to a TTY (Ctrl+Alt+F3), log in, then `pkill -u "$USER" -x xsecurelock; pkill -u "$USER" -x i3lock` and `rm -f "$XDG_RUNTIME_DIR"/ryoku-x11-lock/*`; return to the X VT (usually Ctrl+Alt+F1/F2). This needs a working TTY login, so confirm that first.
- If `/var/lib/ryoku` was created by F1: after removal it is left behind; remove it manually only after confirming nothing else uses it.
- A failed or interrupted install: external dependencies are recorded in the manifest before the local transaction; run the removal script, then inspect `pacman -Qdt`.

## 13. Final readiness decision

**READY FOR ISOLATED TESTING ONLY.**

Build, package, installer-transaction, Xvfb and Xephyr/PAM evidence is solid and reproducible. It is not **READY FOR CONTROLLED PC INSTALLATION TESTING** because: F1 needs an owner decision, F2/F3 are only mitigated by the preflight and procedure, `ryoku` CLI host-mutating subcommands are unaudited (F5), interrupted-install and conflict cases are untested, and nothing has been tested on the target hardware. Once those are handled and CI passes on the resulting commit, the decision can be re-evaluated.


## 14. Post-audit remediation on `claude/full-repo-audit`

The following changes were made after the audit tree described above. They are implementation changes, not yet accepted test evidence; the CI run for the resulting head must pass before this branch is promoted to `development`.

- **F1 — resolved in the overlay:** the RXB build sets `RYOKU_X11_BRIDGE=1` in the upstream `ryoku` package. Its package payload omits `ryoku-boot-guard.service` and `ryoku.conf` tmpfiles installation. This avoids the host boot guard's `/boot/limine.conf`/EFI behavior and the global `/etc/ryoku`, `/var/lib/ryoku`, and SDDM greeter hand-off file creation. The RXB package set also removes `ryoku-keyring` and its hard dependency because its `.INSTALL` script mutates the system pacman trust database; RXB's updater is disabled and the local bundle does not need the upstream repository signing key. Package safety rejects the boot-guard/tmpfiles paths, keyring package/files and pacman trust-store scriptlets.
- **F2 — installer enforcement added:** the installer refuses pending system updates, checks the installed `qt6-base` floor, prints a read-only dependency plan, and refuses a dependency plan that would upgrade an already-installed package as an RXB side effect.
- **F3 — installer enforcement added:** known conflicts/replacements (`bibata-cursor-theme`, `bibata-cursor-theme-bin`, `gpk-bin`, `tlp`, `tuned-ppd`) are rejected before package transactions.
- **F4 — review made explicit:** the installer prints the dependency transaction plan before it asks pacman to install dependencies. Interactive pacman confirmation remains required; do not use the test-only no-confirm variable on a host.
- **F5 — command boundaries added:** the RXB `ryoku` CLI refuses update/rollback/boot/deploy/recovery/channel-tracking commands and forces `doctor` into read-only `--check` mode. `ryoku-host` refuses service reconciliation, session bootstrap/wrapper repair, repository mutation, initramfs rebuild, and suspend/hibernate commands. Explicit privileged UI actions such as package installation remain available through the upstream authorization path and still require deliberate user action.
- **Installer recovery tests added:** the transaction suite now simulates a pre-existing conflict and kills the installer at the local package transaction boundary to verify that the ownership manifest is already present and the remover cleans the subset that actually landed.

**Status at time of writing:** CI for the updated overlay, package build, package-safety checks and transaction tests is pending. F6/F7 (real X11 input/lock behavior and target GPU/rendering acceptance) remain hardware-test gates. No daily-use host installation has been performed.
