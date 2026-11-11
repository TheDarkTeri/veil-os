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
