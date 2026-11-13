# Veil OS

A personal, gaming-focused Linux image built as a **learning project**. It is a thin
BlueBuild layer on top of Bazzite, built and published by GitHub Actions.

- Repo: `github.com/TheDarkTeri/veil-os`
- Image: `ghcr.io/thedarkteri/veil-os` (lowercase: container registries reject uppercase)
- Base: `ghcr.io/ublue-os/bazzite-deck-nvidia:stable`

## Rules for anyone (human or AI) working in this repo

1. **Ask before secrets or disks.** Stop and get an explicit yes from the user before any
   action that touches:
   - **secrets**: cosign keys (`cosign.key`, `cosign.private`), the `SIGNING_SECRET`
     GitHub secret, tokens, passwords, anything under GitHub repo Settings;
   - **disks**: partitioning, formatting, flashing an ISO or USB stick, installing an OS,
     creating or changing a VM's disk, or writing anywhere outside this repo folder.
   A yes covers that one action only. It does not carry over to the next one.
2. **Don't invent.** No guessed package names, Flatpak IDs, config keys, file paths or
   commands. Check upstream docs or source first. If something can't be verified, say so
   and list it under "Not verified" below instead of presenting it as fact.
3. **Minimal and working beats feature-rich.** Don't fight the base image. If Bazzite
   already does something, document it rather than re-implementing it.
4. **Never commit a private key.** `cosign.key` / `cosign.private` are git-ignored; only
   `cosign.pub` belongs in the repo.
5. Ask before creating, publishing or pushing anything public (repo, releases, packages).

## Goals

- Boots into Steam Gaming Mode (gamescope session); normal KDE Plasma desktop available.
- Preinstalled: Steam, Lutris, MangoHud, ProtonUp-Qt, controller support.
- Sensible gaming defaults, each one explained (what, why, how to check).
- Own branding: name, wallpaper, boot splash.
- Deliverables: architecture notes, complete repo, test checklist (VM vs. real hardware).

## Target hardware

| Machine | CPU | GPU | Notes |
|---|---|---|---|
| Desktop | Ryzen 5 7500F | RTX 3060 | No integrated GPU |
| Laptop | Ryzen 5 4600H | GTX 1650 Ti | Hybrid graphics (AMD iGPU + NVIDIA dGPU) |

Both GPUs are Turing or newer, so both use the NVIDIA open kernel driver that the base ships.
Test VM: VMware on Windows 11 (no NVIDIA GPU, no Vulkan; desktop-only testing).

## Decisions (2026-11-11) and why

- **Base is `bazzite-deck-nvidia`**, not Kinoite. Universal Blue retired `kinoite-nvidia`
  in Sept 2025. The Bazzite deck image already integrates the kernel, NVIDIA driver,
  gamescope session, autologin and Gaming/Desktop switching, which is the fragile part.
- **GameMode is intentionally NOT included.** It was in the original wish list, but Bazzite
  removes it on purpose (`dnf5 -y remove gamemode` in its build) and the user decided not to
  fight the base. Do not re-add it.
- **`ID=bazzite`, `VARIANT_ID` and `/usr/share/ublue-os/image-info.json` are left alone.**
  Bazzite's own scripts (`bazzite-autologin`, `bazzite-flatpak-manager`, ujust recipes) key
  off them. Only the display fields in os-release are rebranded.
- **No extra sysctls or kernel arguments.** The base already sets the gaming tweaks; the
  README documents them. Duplicating them adds risk and no benefit.
- **One image for both machines.**
- **Splash logo is 96 px tall.** Computed from Plymouth's spinner layout so it clears the
  spinner and a status line even at 800x600 (see README, "Branding").
- **Wallpaper** is the logo at 1:1 (never upscaled) on a 1920x1080 canvas, "CLIENT" line
  removed, V emblem + "VEIL" kept.

## How the repo works

| Path | Purpose |
|---|---|
| `recipes/recipe.yml` | BlueBuild recipe: base image + modules, executed in order |
| `files/system/` | Copied verbatim onto `/` of the image (`files` module) |
| `files/scripts/branding.sh` | Build-time: os-release display fields, default KDE wallpaper |
| `files/scripts/regen-initramfs.sh` | Build-time: rebuilds initramfs so the Plymouth logo is included |
| `.github/workflows/build.yml` | BlueBuild's template workflow; builds on push, daily, and on demand |
| `.github/workflows/build-iso.yml` | Builds the live installer ISO; manual trigger only, uses no secrets |
| `iso/patch-installer.sh`, `iso/iso.yaml` | Adapt Bazzite's installer (pinned commit) to install Veil OS |
| `branding/make-branding.ps1` | Regenerates the wallpaper and splash PNGs from `branding/Logo.png` |
| `docs/TESTING.md` | What to verify in VMware vs. on the real machines |

Conventions:
- **LF line endings everywhere** (`.gitattributes`). A CRLF shell script breaks the Linux build.
- Shell scripts start with `set -euo pipefail` and **guard every edit**: if an expected line
  or file is missing because upstream changed, the build must fail, not ship half-branded.
- Local Windows machine cannot build the image; the GitHub Actions run is the real test.

## Verified against upstream (2026-11-11)

- BlueBuild modules and keys used: `files`, `default-flatpaks` (v2 `configurations`),
  `script` (`scripts` in `files/scripts/`), `signing`. Docs: blue-build.org/reference.
- Signing: `cosign generate-key-pair` with an empty password, private key in the
  `SIGNING_SECRET` repo secret, `cosign.pub` in the repo root. Docs: blue-build.org/how-to/cosign.
- Bazzite source (`ublue-os/bazzite`, main): Fedora 45, OGC kernel, `nvidia-open`;
  Plymouth watermark at `/usr/share/plymouth/themes/spinner/watermark.png` (theirs: 149x43);
  default wallpaper set in `plasmoidsetupscripts/org.kde.plasma.folder.js` of the
  `com.valve.vapor.desktop` and `com.valve.vgui.desktop` look-and-feel packages;
  ProtonUp-Qt (`net.davidotek.pupgui2`) is only installed by the ISO installer, not on rebase.
- Plymouth two-step plugin: spinner frames 32x32 centred at 70% height; watermark top at
  `0.96 * (screen_height - image_height)`; messages drawn 10 px below the spinner.

## Not verified (check these, don't assume)

- Gaming Mode on the hybrid-graphics laptop. Fallback: `steamosctl set-default-login-mode desktop`.
- **Nothing has been booted yet.** Every item in `docs/TESTING.md` is still open.
- What reads `BOOTLOADER_NAME` in os-release (check the boot menu title in the VM).
- Whether KDE's wallpaper picker lists the `VeilOS` wallpaper package.
- Lock screen and KDE login splash still show Bazzite art (out of scope for now).
- VMware's boot-splash resolution; whether Bazzite's default Plymouth theme is `bgrt` or `spinner`.
- BlueBuild's `default-flatpaks` module running next to Bazzite's own
  `bazzite-flatpak-manager` (expect one `flathub` system remote; check it).
- Whether a daily rebuild is the right cadence (Bazzite `stable` moves less often).

## Build and signing facts (2026-11-11)

- First GitHub Actions build of commit `a174eba` succeeded. The action publishes to the
  lowercase path `ghcr.io/thedarkteri/veil-os` with tags `latest`, `<fedora>` (`45`),
  `YYYYMMDD`, `YYYYMMDD-<fedora>` and `<short sha>-<fedora>`.
- The package is public: an anonymous manifest request returned 200.
- The build log is the place to confirm a change took effect: `branding.sh` prints the final
  os-release, and dracut prints `Including module: plymouth`.
  `gh run view <id> --repo TheDarkTeri/veil-os --log`
- Signing key: generated with cosign 3.1.4 (winget package `Sigstore.Cosign`, which installs
  the command as **`cosign-windows-amd64`**, not `cosign`). `cosign.pub` is committed, the
  private key is in the `SIGNING_SECRET` repo secret and in `C:\OS\cosign.key` (git-ignored).
  Rule 1 applies to both: ask before touching either.
- The `gh` token on this machine has no `read:packages` scope, so the packages API returns
  403. Check visibility with an anonymous pull instead of widening the token.

## ISO (added 2026-11-11)

The user wants to install like Linux Mint: boot a flash drive, install, done; no stock
Bazzite, no rebase.

- **BlueBuild cannot make ISOs right now.** `bluebuild generate-iso` wraps
  `JasonN3/build-container-installer`, declared end-of-life 2026-09-27 and archived
  2026-10-26 (its issue #215: it cannot build since Fedora archived the repos it used).
  BlueBuild's replacement is undecided (`blue-build/cli` issue #613, unmerged PR #831).
  Re-check those before changing approach.
- **Chosen route: Bazzite's own ISO pipeline.** `build-iso.yml` mirrors
  `ublue-os/bazzite/.github/workflows/build_iso.yml`: Bazzite's `installer/` at commit
  `3110f3c` + `ublue-os/titanoboa@5c457c3`. That pair is what produced Bazzite's green ISO
  runs on 2026-11-08 (their workflow then used `Zeglius/titanoboa@revamp-pr`, whose tree is
  identical to `5c457c3`). The `bazzite-deck-nvidia` job took 29 minutes on `ubuntu-latest`
  and uploaded its ISO as an artifact.
- **It is a live ISO, but only an installer environment.** The live desktop is
  `ghcr.io/ublue-os/bazzite:stable` (no NVIDIA driver, no Steam, no Gaming Mode), as for all
  of Bazzite's ISOs. Do not promise "try Veil OS from the stick".
- **Why a patch is needed:** Bazzite's hook finds the image to install with
  `podman images 'bazzite*'`. `iso/patch-installer.sh` replaces that with
  `INSTALL_IMAGE_PAYLOAD`, maps the hook's `*-nvidia*` checks to "yes" and `*-deck*` to "no"
  (handheld on-screen keyboard), swaps the boot menu and renames "Bazzite" in the welcome
  dialogs. It is guarded; bumping `BAZZITE_COMMIT` will fail loudly if the files changed.
- **Updates:** the installer ends with `bootc switch --mutate-in-place
  --enforce-container-sigpolicy --transport registry ghcr.io/thedarkteri/veil-os:<tag>`.
  The workflow reads that line back out of the built image and fails if it is not there.
- **Left alone on purpose:** the login script's NVIDIA "hardware helper" still looks for
  `bazzite*`, finds nothing and skips itself (with a real name it would call Veil OS the
  wrong image). Conky and the MOTD in the live session show an empty image name for the
  same reason; cosmetic.
- **No secrets in the ISO workflow.** Bazzite signs its ISOs with cosign; this one only
  writes a SHA-256. Adding signing means using `SIGNING_SECRET`: rule 1, ask first.
- Sizes: Bazzite's `bazzite-deck-nvidia` live ISO is 10.02 GiB; the Veil OS image is
  6.60 GiB compressed on GHCR. A 16 GB flash drive is the minimum.
- Flashing a drive and installing are disk operations: the user does them (rule 1).

First ISO build (2026-11-11, run 43060366149, commit `2523af5`): green in 33 minutes
(live image 20 min, Titanoboa 8 min, upload 1 min). `veil-os-live-amd64.iso` is 10.25 GiB
(11,004,577,792 bytes), SHA-256 `1f0c1e1e…52b0a0bc` (full value in the README status
table), artifact expires 2026-11-18. The 10 GiB artifact uploaded from this public repo
without complaint. The log confirms the patched installer names
`ghcr.io/thedarkteri/veil-os:latest` in both its `ostreecontainer` and `bootc switch`
lines. One harmless warning: `jlumbroso/free-disk-space` says its `tool-cache` input was
renamed to `preinstalled-runtimes`; rename it the next time the workflow is touched and
re-run to confirm.

First boot (2026-11-13): the ISO boots in VMware on the laptop (UEFI) to the live KDE
desktop, and the patched dialogs say "Veil OS". Conky's `BUILD:` and `IMAGE:` lines are
empty, as expected. The install was not attempted because of the memory check below.

**The installer's memory check** (`block_low_memory_install` in Bazzite's
`on_gui_login.sh`, added by upstream PR #4708): it reads `MemTotal` from `/proc/meminfo`
and, below **5,000,000 kB**, loops a dialog whose only button is Shutdown. The "8GB" in
its text is Bazzite's documented minimum; the code only blocks below about 5 GB. Upstream's
reason: installs on 4 GB "fail every time". They do not say at which step; the likely
mechanism is that the live session lives in RAM and `/var/tmp`, which ostree uses during
the deploy, is a tmpfs capped at 50% of RAM (`installer/build.sh`). There is no boot
parameter to skip it and nothing else re-checks memory; killing `on_gui_login.sh` and
running `liveinst` bypasses it, which is only defensible in a throwaway VM.

**VMware runs on the laptop**, which has 8 GiB installed and 7.37 GiB usable
(7,730,500 kB; 643 MB reserved for the iGPU). So the real install on the laptop passes the
check, but a VM on that host cannot have 8 GB. A VM needs at least 5632 MB configured to
clear the check (4096 MB shows as 3.8 GB in the guest).

**CAUSE FOUND (2026-11-13), fix written, NOT yet in a built ISO.** The debug log ends with
`Path '/mnt/sysroot/var/home' is not under root '/var/mnt/sysroot', refusing SELinux label
fix.` The live session is a Fedora Atomic image, where `/mnt` is a symlink to `/var/mnt`.
Anaconda passes `--root=/mnt/sysroot`; systemd 262 (262.1-1.fc45) resolves the root for its
SELinux code but not for the file paths, then refuses to label a file "not under" the root
and exits 73 without a message. The only matching rule is `d /var/home 0755 root root -`
in `rpm-ostree-0-integration.conf`. Not Veil-specific: secureblue fixed the same thing on
2026-11-06 (`secureblue/secureblue` PR 2808: `rm /mnt; mkdir -m 0755 /mnt` in the live
environment); Bazzite's installer has no fix on main or testing and no issue for it.
- Fix here: step 4 of `iso/patch-installer.sh` appends the same `/mnt` replacement to
  Bazzite's hook (guarded; fails if upstream starts handling `/mnt` itself), and
  `build-iso.yml` checks that `/mnt` is a real directory in the built live image. Dry run:
  25 of 25 checks. `tool-cache` was also renamed to `preinstalled-runtimes` in the workflow.
- **These changes are uncommitted and the ISO has not been rebuilt.** The ISO from
  2026-11-11 still fails unless, in the live session before starting the installer, the
  user runs `sudo rm /mnt && sudo mkdir -m 0755 /mnt`. The user was asked to try exactly
  that in a freshly rebooted VM, to validate the fix and reveal any later failure (the
  `bootc switch` signature step is next and untested) before spending a rebuild on it.
- The text below is the earlier investigation, kept for the record.

**First install attempt (2026-11-13) FAILED.** In VMware, Anaconda deployed the
image (15 GB on the virtual disk), then died with "The command `systemd-tmpfiles --create
--boot --root=/mnt/sysroot --prefix=/var/home` exited with the code 73". What is known:

- Where: `_create_tmpfiles('/var/home')` in Anaconda's
  `pyanaconda/modules/payloads/payload/rpm_ostree/installation.py`, the first of ten such
  calls right after the deploy. Anaconda accepts exit codes 0 and 65 only. 73 means the
  tmpfiles config was valid but something could not be created (permissions, missing
  parent, read-only target, "unsafe path transition", ...).
- It ran after our patched lines did their job (the image was found and deployed), and
  before `bootc switch`, Flatpaks and Secure Boot, so those are still untested.
- Probably not Veil-specific: `cosmic-blue-os/cosmic-blue` PR 10 (2026-11-11) reports the
  identical error from a Fedora 45 based image with Bluefin's Titanoboa/Anaconda setup, says
  partitioning and image content were ruled out, and fixed it by going back to Fedora 44.
  That PR is one project's reasoning, not proof. Bazzite's first Fedora 45 release was
  45.20261105; its public ISOs were last uploaded 2026-10-13, so a Fedora 45 Bazzite ISO
  may never have been install-tested in public. No Bazzite or Anaconda issue found for it.
- Re-run by hand in the live session (2026-11-13): the same command exits 73 again and
  **prints nothing**, and the journal has only Anaconda's "Return code of systemd-tmpfiles:
  73". Yet `/mnt/sysroot/var/home` exists (root:root 0755, created the minute Anaconda ran
  the step). So the visible job is done and the tool still reports failure, silently.
- Ruled out: memory (the VM had 5.2 GiB, 3.1 GiB available, swap half used); a missing or
  wrongly-owned `/var` or `/var/home`.
- The live session is Fedora 45 (Anaconda runs under Python 3.15).
- Not known: which tmpfiles rule fails. Next step is the debug log:
  `sudo SYSTEMD_LOG_LEVEL=debug systemd-tmpfiles --create --boot --root=/mnt/sysroot --prefix=/var/home 2>&1 | tail -40`
  and the rules themselves:
  `sudo grep -rn "/var/home\|^[a-zA-Z+!-]* */home" /mnt/sysroot/usr/lib/tmpfiles.d /mnt/sysroot/etc/tmpfiles.d`.
- Until this is solved the ISO does not install. The rebase route (README 3B) does not use
  this installer and is unaffected, but is itself untested.

Not verified for the ISO (see `docs/TESTING.md`, Part I): that the installer completes;
that the image's signature policy satisfies `--enforce-container-sigpolicy` at the end of
the install; that an install with 5.5 GB of VM memory gets through; that the flash drive
boots on the two machines; whether GitHub bills a public repo for artifact storage (its
docs do not say).

## Artwork notes

- `branding/Logo.png` is the user's logo. It is JPEG data despite the `.png` name, so its
  dark background carries 1-2 levels of compression mottling. That is in the source, not a
  seam; a lossless or vector original would be cleaner if the user has one.
- `branding/make-branding.ps1` finds the emblem / "VEIL" / "CLIENT" bands by itself, erases
  the last band, and **fails** if the wallpaper seam or the erased strip would be visible.
  Do not hand-edit the two generated PNGs; change the logo or the script and re-run.
- The splash logo keeps a thin band of the red glow by default (emblem cut out along its
  own closed black outline). `-CleanSplash` drops the glow.

## How to check changes locally (Windows, no Linux needed)

- `bash -n files/scripts/*.sh` in Git Bash for syntax.
- No CRLF: `grep -rlI $'\r' --exclude-dir=.git .` must print nothing.
- Scripts must stay executable in git: `git ls-files -s files/scripts` shows `100755`.
- Module keys: compare with `https://schema.blue-build.org/modules/<module>-latest.json`.
- The scripts were dry-run against a fake root mirroring Bazzite's os-release and KDE setup
  scripts (edits, guards and the os-release restore all behaved). That harness is not in the
  repo; the GitHub Actions build remains the only real test.

## Status

See the "Status" section at the bottom of `README.md` for what has been built and tested.
Keep that table current: add a row whenever something is built, booted or tested.
