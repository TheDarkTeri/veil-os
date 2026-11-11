# Veil OS

A personal, gaming-focused Linux image, built as a learning project.

Veil OS is a thin layer on top of [Bazzite](https://bazzite.gg) (itself built on Fedora
Atomic / Universal Blue). It is assembled by [BlueBuild](https://blue-build.org) in GitHub
Actions and published as a container image:

```
ghcr.io/thedarkteri/veil-os:latest
```

It boots into Steam Gaming Mode (a gamescope session), with a normal KDE Plasma desktop one
click away. It is not affiliated with or supported by Bazzite, Universal Blue or BlueBuild;
please don't send them bug reports about this image.

**Target hardware:** Ryzen 5 7500F + RTX 3060 (desktop), Ryzen 5 4600H + GTX 1650 Ti (laptop).
Any PC with an NVIDIA GTX 16xx or RTX card should behave the same.

---

## 1. Architecture: what comes from where

The guiding rule is *minimal and working*: everything hard is inherited from the base image,
and this repo only adds what makes it mine.

| Area | From the base `bazzite-deck-nvidia` | Added by Veil OS | Why it is split this way |
|---|---|---|---|
| Kernel, NVIDIA driver, Secure Boot signing | Yes | Nothing | The kernel and driver must match exactly. Rebuilding them is the easiest way to get an unbootable image. |
| Gamescope session, autologin, Gaming Mode / Desktop switching | Yes | Nothing | A lot of integration work that already works on NVIDIA. |
| Steam, Lutris, MangoHud, gamescope, controller drivers and udev rules | Yes | Nothing | Already in the base. |
| Gaming tweaks (sysctl, I/O schedulers, zram, NVIDIA power management) | Yes | Documentation only ([section 6](#6-gaming-defaults-explained)) | Setting them twice adds risk and no benefit. |
| ProtonUp-Qt | Listed by Bazzite, but only installed by its ISO installer | Installed as a system Flatpak | So it is there however the system was installed. |
| Name, boot splash, wallpaper | Bazzite's | Veil OS's | Branding. |
| `ID=bazzite`, `VARIANT_ID`, `image-info.json` | Yes | Deliberately untouched | Bazzite's own scripts decide the login session and NVIDIA settings from these. |

GameMode is deliberately not included: Bazzite removes it on purpose, and this image does not
fight its base.

### How a build works

```
push / daily schedule / manual run
        |
        v
.github/workflows/build.yml  -->  blue-build GitHub Action
        |                              reads recipes/recipe.yml
        v
FROM ghcr.io/ublue-os/bazzite-deck-nvidia:stable
  1. files            copy files/system/* onto /        (splash logo, wallpaper)
  2. default-flatpaks ProtonUp-Qt
  3. script           branding.sh, regen-initramfs.sh
  4. signing          install this repo's public key + policy
        |
        v
signed with cosign  -->  pushed to ghcr.io/thedarkteri/veil-os
```

A running Veil OS system then pulls that image as its update. Nothing is compiled on your PC.

### Repo layout

| Path | Purpose |
|---|---|
| `recipes/recipe.yml` | The recipe: base image and modules, in order. Start reading here. |
| `files/system/` | Copied verbatim onto `/` of the image. |
| `files/scripts/branding.sh` | Build time: display name in os-release, default KDE wallpaper. |
| `files/scripts/regen-initramfs.sh` | Build time: rebuilds the initramfs so the new boot logo is in it. |
| `.github/workflows/build.yml` | BlueBuild's template workflow. |
| `branding/` | Source logo and the script that turns it into wallpaper + splash logo. |
| `docs/TESTING.md` | Test checklist: VMware vs. real hardware. |
| `CLAUDE.md` | Project context and rules for AI assistants (and humans). |
| `cosign.pub` | Public half of the signing key (added during setup). |

---

## 2. Build

### One-time setup

1. **Create the GitHub repository** `TheDarkTeri/veil-os` and push this folder to it.
   Make it public: public repos get free Actions minutes, and a public image can be
   pulled without logging in.
2. **Create the signing key.** Install
   [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) (on Windows it is
   in winget as `Sigstore.Cosign`):

   ```powershell
   winget install Sigstore.Cosign
   ```

   Then, in the repo folder (the winget package names the command
   `cosign-windows-amd64`; use that instead of `cosign` if you installed it that way, and
   open a new terminal first so it is on your PATH):

   ```bash
   cosign generate-key-pair
   ```

   When asked for a password, press Enter twice (no password; an encrypted key cannot be
   used by GitHub Actions). This writes `cosign.key` (private) and `cosign.pub` (public).
3. **Give GitHub the private key** as a repository secret named `SIGNING_SECRET`
   (run from Git Bash; PowerShell does not support `<`):

   ```bash
   gh secret set SIGNING_SECRET < cosign.key
   ```

   Or paste the contents of `cosign.key` at *Settings → Secrets and variables → Actions →
   New repository secret*.
4. **Commit `cosign.pub`** to the repo root. Never commit `cosign.key`; it is in
   `.gitignore`. Store it somewhere safe outside the repo, or delete it once the secret is
   set. If it is ever lost or leaked, generate a new pair and repeat steps 3 and 4.
5. Check that Actions are enabled (*Actions* tab).

### Building

Builds start on their own:

- on every push (except changes that only touch `*.md` files),
- every day at 06:00 UTC, which is how Bazzite's updates flow into Veil OS,
- on demand: *Actions → bluebuild → Run workflow*, or

  ```bash
  gh workflow run bluebuild
  ```

A build takes a while (the base image is several GB). When it is green, the image is at
`ghcr.io/thedarkteri/veil-os:latest`. After the **first** build, open
*github.com/TheDarkTeri → Packages → veil-os → Package settings* and make sure the
package's visibility is **Public**; otherwise the rebase below needs a registry login.

To check a published image's signature:

```bash
cosign verify --key cosign.pub ghcr.io/thedarkteri/veil-os
```

---

## 3. Install (rebase)

Veil OS has no installer of its own. You install Bazzite, then *rebase* it: tell the system
to use a different image as its OS. Your files, Flatpaks and settings stay.

1. Install Bazzite from [bazzite.gg](https://bazzite.gg). On the real machines pick the
   NVIDIA + KDE + Steam Gaming Mode variant (image name `bazzite-deck-nvidia`). In a VM
   any KDE variant will do; see [docs/TESTING.md](docs/TESTING.md) first.
2. Open a terminal (Desktop Mode → Konsole) and rebase to the image **without** signature
   checking. This first step is what installs Veil OS's public key on the machine.

   ```bash
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/thedarkteri/veil-os:latest
   ```

   ```bash
   systemctl reboot
   ```

3. Rebase again, this time to the **signed** image. From now on every update is verified
   against the key.

   ```bash
   rpm-ostree rebase ostree-image-signed:docker://ghcr.io/thedarkteri/veil-os:latest
   ```

   ```bash
   systemctl reboot
   ```

4. Confirm:

   ```bash
   rpm-ostree status
   ```

   The top (booted) entry should show `ghcr.io/thedarkteri/veil-os:latest`.

**Secure Boot.** Veil OS uses Bazzite's kernel and NVIDIA modules unchanged, so it needs
the same Universal Blue key enrolled as Bazzite does. If you enrolled it when installing
Bazzite, nothing changes. If not, Bazzite's documented way is `ujust enroll-secure-boot-key`,
then choose *Enroll MOK* on the blue screen at next boot (password `universalblue`).

---

## 4. Update

Updates are staged in the background and applied at the next reboot; the running system is
never modified in place.

```bash
rpm-ostree upgrade
```

```bash
systemctl reboot
```

Bazzite's own updater (in Gaming Mode: *Settings → System*) should keep working because it
follows whatever image the system is booted from. That has not been tested on this image yet.

---

## 5. Rollback

Every update keeps the previous system as a second *deployment*. Going back is one command
or one key press, and it does not touch your files in `/home`.

**The new version boots but something is wrong:**

```bash
rpm-ostree rollback
```

```bash
systemctl reboot
```

**The new version does not boot at all:** reboot, and in the boot menu pick the second
entry (the previous deployment). Once booted, run `rpm-ostree rollback` to make it the
default again.

**Keep a known-good version around** so later updates cannot push it out (`0` is the
booted deployment; `rpm-ostree status` lists them):

```bash
sudo ostree admin pin 0
```

**Go back to a specific older build of Veil OS:** every build is also published under a
dated tag (for example `20261111`, plus `20261111-45` with the Fedora version). Look the
tags up on the package page (*github.com/TheDarkTeri/veil-os → Packages*) and rebase to one:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/thedarkteri/veil-os:<tag>
```

**Leave Veil OS and return to stock Bazzite:**

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-deck-nvidia:stable
```

Do not use Bazzite's own rebase helpers for moving between Veil OS versions: they read
`image-info.json`, which still describes the Bazzite base, and would move you back to Bazzite.

### Gaming Mode and Desktop

| I want to... | How |
|---|---|
| Go to the desktop once | Steam button → Power → Switch to Desktop |
| Go back to Gaming Mode | The *Return to Gaming Mode* icon on the desktop |
| Always boot to the desktop | `steamosctl set-default-login-mode desktop` (or `ujust set-default-desktop`) |
| Always boot to Gaming Mode | `steamosctl set-default-login-mode game` (or `ujust set-default-game-mode`) |
| Gaming Mode shows a black screen | Ctrl+Alt+F4, log in, `steamosctl switch-to-desktop-mode` |

---

## 6. Gaming defaults, explained

Veil OS adds **no** performance tweaks of its own. All of these come from the Bazzite base;
this table explains what each one does so the system is not a black box. Values were read
from Bazzite's source on 2026-11-11 and can change upstream. The *Check* column shows what
your running system really has.

### Kernel and memory (`/usr/lib/sysctl.d/`)

| Setting | Value | What it does and why it helps games | Check |
|---|---|---|---|
| `kernel.split_lock_mitigate` | `0` | A "split lock" is an atomic memory operation that straddles two cache lines. By default the kernel deliberately slows down any program that does this. Some games do, and stutter because of it. `0` turns the slowdown off. | `sysctl kernel.split_lock_mitigate` |
| `vm.max_map_count` | `2147483642` | The number of separate memory regions one program may map. Some Windows games under Proton need far more than the usual limit and crash without it. Same value SteamOS uses. | `sysctl vm.max_map_count` |
| `kernel.watchdog`, `kernel.nmi_watchdog`, `kernel.soft_watchdog` | `0` | Switches off the kernel's "is this CPU stuck?" detectors, which interrupt every core on a timer. Fewer interruptions and a little less power draw. The cost: a hard freeze is not diagnosed automatically. | `sysctl kernel.watchdog kernel.nmi_watchdog` |
| `vm.swappiness` | `180` | How eagerly the kernel swaps. Swap here is zram (compressed RAM, see below), so swapping is cheap; a high value prefers it over throwing away cached game files that would have to be re-read from disk. | `sysctl vm.swappiness` |
| `vm.page-cluster` | `0` | Read one page at a time from swap. Read-ahead helps slow disks but only wastes time with zram. | `sysctl vm.page-cluster` |
| `vm.watermark_boost_factor`, `vm.watermark_scale_factor` | `0`, `125` | Makes background memory reclaim start earlier and more smoothly, so a game is less likely to be paused while the kernel frees memory in a hurry. | `sysctl vm.watermark_scale_factor` |
| `vm.dirty_bytes`, `vm.dirty_background_bytes` | 256 MB, 128 MB | Caps how much unwritten data may pile up in RAM. Start writing at 128 MB, throttle the writer at 256 MB. Prevents a multi-second stall when a big download finally flushes to disk mid-game. | `sysctl vm.dirty_bytes` |

### Network and files

| Setting | Value | What it does | Check |
|---|---|---|---|
| `net.ipv4.tcp_congestion_control` | `bbr` | Google's BBR congestion control: keeps throughput up and latency down on lossy or busy connections. | `sysctl net.ipv4.tcp_congestion_control` |
| `net.ipv4.tcp_mtu_probing` | `1` | Recovers automatically when a router silently drops large packets, instead of hanging. | `sysctl net.ipv4.tcp_mtu_probing` |
| `fs.inotify.max_user_watches`, `max_user_instances` | `524288`, `8192` | Lets programs watch more files for changes. Launchers and mod tools run out with the defaults. | `sysctl fs.inotify.max_user_watches` |

### Storage and swap

| Setting | Value | What it does | Check |
|---|---|---|---|
| I/O scheduler, SSD and NVMe | `kyber` | A lightweight scheduler that aims for low latency on fast drives. | `cat /sys/block/nvme0n1/queue/scheduler` |
| I/O scheduler, hard disks and SD cards | `bfq` | Shares a slow drive fairly, so the system stays responsive while a game installs. | `cat /sys/block/sda/queue/scheduler` |
| zram swap | zstd, half of RAM up to 16 GB | Swap that lives in compressed RAM instead of on disk. Much faster than disk swap, and spares the SSD. | `zramctl` |

### NVIDIA (`/usr/lib/modprobe.d/`)

| Setting | What it does | Check |
|---|---|---|
| `NVreg_DynamicPowerManagement=0x02` | Lets the NVIDIA GPU power down when nothing uses it. Matters on the laptop (battery, heat); no effect on the desktop. | `cat /proc/driver/nvidia/params \| grep DynamicPower` |
| `NVreg_EnableS0ixPowerManagement=1` | Allows the GPU to take part in modern standby. | `cat /proc/driver/nvidia/params \| grep S0ix` |
| `NVreg_RegistryDwords=RMDisableNoncontigAlloc=1` | Set by Bazzite's Gaming Mode NVIDIA image. Its source does not say why and I have not verified the reason, so I am not going to guess. | `cat /proc/driver/nvidia/params \| grep RegistryDwords` |

Also inherited and not configured here: Bazzite's gaming-patched kernel, the gamescope
compositor (Gaming Mode), and MangoHud for an FPS and frame-time overlay.

---

## 7. Branding

| What | Where in the image | Notes |
|---|---|---|
| Name | `/usr/lib/os-release` (`NAME`, `PRETTY_NAME`, `DEFAULT_HOSTNAME`, `BOOTLOADER_NAME`, URLs) | `ID` stays `bazzite` on purpose. |
| Boot splash logo | `/usr/share/plymouth/themes/spinner/watermark.png` | 104x96, transparent. Baked into the initramfs at build time. |
| Wallpaper | `/usr/share/wallpapers/VeilOS/` | 1920x1080. Default for new user accounts; an existing account keeps its wallpaper until you change it in *Desktop → Configure Desktop and Wallpaper*. |

Both images are generated from `branding/Logo.png`:

```powershell
powershell -ExecutionPolicy Bypass -File branding\make-branding.ps1
```

The script checks its own output and fails if the wallpaper would show a seam. Previews go
to `branding/preview/`. To change the artwork, replace `branding/Logo.png`, run the
script, commit the two PNGs.

The current `Logo.png` is JPEG-compressed, which leaves faint (1 to 2 brightness levels)
mottling in its dark background. It is not visible at normal contrast, but a lossless
original would give a cleaner wallpaper.

**Why the splash logo is 96 px tall.** Plymouth's spinner theme draws a 32x32 spinner
centred at 70% of the screen height, prints status messages 10 px below it, and puts the
logo's top edge at `0.96 × (screen height − logo height)`. Early in boot the screen can be
as small as 800x600 (firmware resolution, before the NVIDIA driver loads; common in VMs).

| Screen height | Logo 160 px tall | Logo 96 px tall |
|---|---|---|
| 1080 | clear | clear |
| 768 | touches a status line | clear |
| 600 | overlaps the spinner | clear |

`-SplashHeight` changes it; `-CleanSplash` removes the thin red glow around the emblem.

---

## 8. Known limits

Things that are **not verified yet**. Check them rather than trusting this README:

- Gaming Mode on the hybrid-graphics laptop (AMD iGPU + GTX 1650 Ti). If it misbehaves,
  boot to the desktop by default (table in section 5).
- Gaming Mode in a virtual machine: not expected to work, VMs have no suitable GPU.
- The boot menu title (it depends on which os-release field the bootloader reads).
- Whether the Veil OS wallpaper shows up in KDE's wallpaper picker.
- The lock screen and KDE's login splash still show Bazzite artwork.
- Flatpak setup: this image declares ProtonUp-Qt through BlueBuild's `default-flatpaks`
  module next to Bazzite's own Flatpak handling; check there is exactly one Flathub remote.

## 9. Status

| Date | What |
|---|---|
| 2026-11-11 | Repo written. Recipe keys checked against BlueBuild's module schemas; Bazzite paths and Plymouth layout checked against upstream source. Both build scripts dry-run on Windows against a fake copy of Bazzite's files (edits and guards behave). Artwork generated and seam-checked. |
| 2026-11-11 | **First GitHub Actions build succeeded** (commit `a174eba`). Published as `ghcr.io/thedarkteri/veil-os` with tags `latest`, `45`, `20261111`, `20261111-45`. The build log shows os-release rebranded (`ID=bazzite` kept), both KDE setup scripts repointed, the initramfs rebuilt for kernel `7.3.3-ogc1.1.fc45` with the plymouth module, and the ProtonUp-Qt ID accepted by Flathub. Signature verified from Windows with `cosign.pub`; the image pulls without a login. **Not yet booted anywhere: the VM and hardware checklists in `docs/TESTING.md` are still to do.** |

## Credits

Veil OS is almost entirely other people's work:
[Bazzite](https://github.com/ublue-os/bazzite) and
[Universal Blue](https://universal-blue.org) for the base image,
[BlueBuild](https://blue-build.org) for the build tooling, and the Fedora Project underneath.
