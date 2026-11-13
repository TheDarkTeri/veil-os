# Veil OS test checklist

Two places to test, and they prove different things.

| | VMware VM | Real NVIDIA hardware |
|---|---|---|
| Image builds, pulls, boots | Yes | Yes |
| Rebase, update, rollback flow | **Yes, test it here first** | Repeat once |
| ISO boots, installs, tracks Veil OS | **Yes, test it here first** | Repeat on both machines |
| Branding (name, splash, wallpaper) | Yes | Yes |
| Packages and tweaks are present | Yes | Yes |
| NVIDIA driver | No (the VM has no NVIDIA card) | **Only here** |
| Steam Gaming Mode (gamescope) | No (not expected to start) | **Only here** |
| Games, performance, controllers, suspend | No | **Only here** |

Rule of thumb: the VM answers "did I break the image?", the hardware answers "does it game?".
Do the VM pass first; a broken rebase is free to fix in a VM and annoying on a real disk.

Record the result of every run in the Status table at the bottom of `README.md`.

---

## Part A: VMware

### Setup

- New VM, guest type "Other Linux 6.x kernel 64-bit" (or Fedora 64-bit).
- Firmware: **UEFI**. CPU: 4 cores. RAM: 8 GB. Disk: 64 GB or more (my suggestion, not an
  upstream requirement). Display: *Accelerate 3D graphics* on.
- Install stock **Bazzite, KDE variant**, from the official ISO. The non-NVIDIA desktop
  variant is fine for this first install.
- Take a VM snapshot once Bazzite is installed and updated. That is your "start over" point.

### Before rebasing: keep the VM on the desktop

Veil OS boots into Gaming Mode by default, and Gaming Mode will not start in a VM. Tell it
to log in to Plasma instead **before** the rebase:

```bash
sudo mkdir -p /etc/bazzite
```

```bash
sudo touch /etc/bazzite/desktop_autologin
```

(Bazzite's `/usr/libexec/bazzite-autologin` picks the Plasma session when that file exists.)

If you forget and land on a black screen: Ctrl+Alt+F4, log in, run
`steamosctl switch-to-desktop-mode`.

### Checklist

| # | Check | How | Pass looks like |
|---|---|---|---|
| A1 | Unsigned rebase | README section 3, step 2, then reboot | Boots to the Plasma desktop |
| A2 | Signed rebase | README section 3, step 3, then reboot | Command succeeds without a signature or policy error |
| A3 | Running the right image | `rpm-ostree status` | Booted entry is `ghcr.io/thedarkteri/veil-os:latest` |
| A4 | Signature | On any machine with cosign: `cosign verify --key cosign.pub ghcr.io/thedarkteri/veil-os` | "The cosign claims were validated" |
| A5 | Boot menu name | Reboot, hold Esc/Shift if the menu is hidden | Entry says "Veil OS", not "Bazzite". *Not verified in advance.* |
| A6 | Boot splash | Watch the boot (it is quick; reboot again or record the VM window) | Red V emblem bottom-centre, **below** the spinner and any status text, not touching them |
| A7 | Splash is in the initramfs | `sudo lsinitrd /usr/lib/modules/$(uname -r)/initramfs.img \| grep watermark` | Lists `usr/share/plymouth/themes/spinner/watermark.png` |
| A8 | OS name | `cat /etc/os-release` | `NAME="Veil OS"`, `PRETTY_NAME="Veil OS"`; `ID=bazzite` still there |
| A9 | About dialog | System Settings → About this System | Shows Veil OS |
| A10 | Wallpaper, new user | System Settings → Users → add a user, log in as them | Veil wallpaper, logo centred, no visible rectangle around it |
| A11 | Wallpaper, picker | Right-click desktop → Configure Desktop and Wallpaper | "Veil OS" is in the list. *Not verified in advance.* |
| A12 | ProtonUp-Qt | `flatpak list --system \| grep pupgui2` | One line with `net.davidotek.pupgui2`. It installs shortly after first boot and needs network. |
| A13 | Flathub not duplicated | `flatpak remotes --system` | Exactly one `flathub` |
| A14 | Steam, Lutris present | `rpm -q steam lutris` | Two package versions, no "not installed" |
| A15 | MangoHud present | `which mangohud` | A path |
| A16 | Tweaks | Run the *Check* commands in README section 6 | Values match the tables (NVIDIA rows: skip in a VM) |
| A17 | Update | Start a new build (`gh workflow run bluebuild`), wait for green, then `rpm-ostree upgrade` and reboot | `rpm-ostree status` shows a newer version on top, the old one below |
| A18 | Rollback | `rpm-ostree rollback`, reboot | Booted entry is the older version |
| A19 | Rollback from the boot menu | Reboot, pick the second entry | Boots the other deployment |
| A20 | Back to stock Bazzite | README section 5, last command, reboot | `rpm-ostree status` shows `ublue-os/bazzite-deck-nvidia` |

### Expected "failures" in a VM (not bugs)

- `nvidia-smi` reports no device. There is no NVIDIA card.
- Gaming Mode does not start.
- Anything about frame rates.

---

## Part I: Installing from the ISO

The ISO is the least-tested part of this project: it is Bazzite's installer, adapted to
install an image that is not called "bazzite". Test it in VMware before putting it on a
flash drive. Build and download it as described in README section 3A.

VM setup as in Part A, but with nothing installed: attach `veil-os-live-amd64.iso` as the
CD drive, firmware **UEFI**.

**VM memory: at least 5632 MB (5.5 GB).** The live session refuses to install when the
guest sees less than 5,000,000 kB of RAM: it shows "Not enough memory" with only a Shutdown
button, and reopens if closed. A VM set to 4 GB sees 3.8 GB and is blocked; 5 GB lands
right on the limit. Bazzite's own minimum is 8 GB, so anything under that may still fail
during the install. On a host with 8 GB, close everything else first and expect it to be slow.

| # | Check | How | Pass looks like |
|---|---|---|---|
| I1 | Checksum | `Get-FileHash .\veil-os-live-amd64.iso -Algorithm SHA256` | Same as in the workflow run's summary |
| I2 | ISO boots | Start the VM | Menu with *Start Veil OS Installer*; then a KDE desktop and a welcome window with *Install Veil OS* |
| I3 | Installs without network | Disconnect the VM's network adapter, then install: language, disk, user | Finishes with no error window. (An error window shows the installer log; the last steps are "bootc-switch" and "install-flatpaks".) |
| I4 | First boot | Reboot, detach the ISO | In a VM: Gaming Mode cannot start, so expect a black screen. Ctrl+Alt+F4, log in, `steamosctl switch-to-desktop-mode`. On real hardware: Gaming Mode. |
| I5 | Tracks Veil OS | `rpm-ostree status` | Booted entry is `ostree-image-signed:docker://ghcr.io/thedarkteri/veil-os:latest` |
| I6 | Updates work | Reconnect the network, `rpm-ostree upgrade` | "No upgrade available" or a staged update; no signature or policy error |
| I7 | Default apps came along | `flatpak list --system` | Firefox and the other apps from Bazzite's list; ProtonUp-Qt (`net.davidotek.pupgui2`) appears a little after the first boot with network |
| I8 | Branding | Checks A5 to A11 in Part A | Same as there |
| I9 | Rollback still works | Checks A17 and A18 | Same as there |

Then, on each real machine (writing the flash drive and installing erase disks; that part
is yours to do):

| # | Check | How | Pass looks like |
|---|---|---|---|
| I10 | Flash drive boots | Boot from the drive (UEFI, not legacy) | Menu, then the live desktop on the NVIDIA card. If the screen stays black, use *Basic Graphics Mode*. |
| I11 | Secure Boot | Install with Secure Boot on | Blue *Enroll MOK* screen on the next boot (password `universalblue`); afterwards `mokutil --sb-state` says enabled and the system boots |
| I12 | The rest | Part B from B3 onwards | Same as there |

---

## Part B: Real hardware (both machines)

Install stock `bazzite-deck-nvidia` from the official ISO first, confirm it works, **then**
rebase. That way, if something is wrong after the rebase, you know it is Veil OS.

| # | Check | How | Pass looks like |
|---|---|---|---|
| B1 | Secure Boot state | `mokutil --sb-state` | What you expect (enabled, if you enrolled the key) |
| B2 | Rebase (both steps) | README section 3 | Same as A1 to A3 |
| B3 | NVIDIA driver loaded | `nvidia-smi` | Shows the RTX 3060 / GTX 1650 Ti and a driver version |
| B4 | Kernel modules | `lsmod \| grep nvidia` | `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` |
| B5 | Boot splash at native resolution | Watch the boot | Emblem bottom-centre, clear of spinner |
| B6 | Boots into Gaming Mode | Cold boot | Steam Big Picture UI, no login prompt |
| B7 | To desktop and back | Steam button → Power → Switch to Desktop; then *Return to Gaming Mode* | Both directions work, no black screen |
| B8 | A native game runs | Any small Linux-native game | Launches, renders, exits cleanly |
| B9 | A Proton game runs | Any Windows game from your library | Launches, renders, exits cleanly |
| B10 | MangoHud overlay | Gaming Mode: `...` button → Performance → overlay level. Desktop: launch option `mangohud %command%` | FPS / frame-time overlay appears |
| B11 | ProtonUp-Qt | Open it from the desktop, install a GE-Proton build | Build appears in Steam → game → Properties → Compatibility after restarting Steam |
| B12 | Lutris | Open it | Starts without errors |
| B13 | Controller, USB | Plug in | Navigates Gaming Mode; works in a game |
| B14 | Controller, Bluetooth | Pair in Gaming Mode settings | Same, and reconnects after a reboot |
| B15 | Audio | Play something over the output you use (HDMI/DP/analog) | Sound, right device |
| B16 | Display | Check resolution and refresh rate | Native resolution, expected Hz |
| B17 | Suspend / resume | Suspend, wait a minute, wake | Picture and sound come back, game still running |
| B18 | Tweaks incl. NVIDIA rows | *Check* commands in README section 6 | Values match |
| B19 | Update + rollback | As A17 and A18 | Same |

### Laptop only (Ryzen 5 4600H + GTX 1650 Ti, hybrid graphics)

This is the riskiest combination: Gaming Mode has to pick the right GPU.

| # | Check | How | Pass looks like |
|---|---|---|---|
| L1 | Gaming Mode starts at all | Cold boot | Steam UI. If black screen: Ctrl+Alt+F4, log in, `steamosctl switch-to-desktop-mode`, then make the desktop the default (README section 5) |
| L2 | Games use the NVIDIA GPU | While a game runs, in another terminal or over SSH: `nvidia-smi` | The game's process is listed and GPU utilisation is not 0% |
| L3 | NVIDIA GPU sleeps when idle | On the desktop, nothing running. Find the card: `lspci \| grep -i nvidia`, then `cat /sys/bus/pci/devices/0000:<address>/power/runtime_status` | `suspended` (it shows `active` while something uses it) |
| L4 | External monitor | Plug into HDMI | Picture; note which GPU the port is wired to |
| L5 | Laptop basics | Brightness keys, lid close, battery indicator | All work |

### Desktop only (Ryzen 5 7500F + RTX 3060)

| # | Check | How | Pass looks like |
|---|---|---|---|
| D1 | Picture during early boot | Cold boot | Firmware logo, splash, then Gaming Mode, with no long black gap (the 7500F has no integrated GPU, so everything depends on the NVIDIA card) |
| D2 | High refresh rate / VRR | Display settings in Gaming Mode | Your monitor's modes are offered |

---

## When something fails

1. Get back to a working system first: boot the previous entry from the boot menu, or
   `rpm-ostree rollback` and reboot.
2. Then collect evidence from the working system:
   - errors from the boot that failed: `journalctl -b -1 -p err`
   - what is deployed: `rpm-ostree status`
   - the build log of that image: `gh run list --workflow bluebuild`, then `gh run view <id> --log`
3. Decide whether it is Veil OS or the base: rebase to stock `bazzite-deck-nvidia`
   (README section 5). If the problem is still there, it is not this repo's doing.
