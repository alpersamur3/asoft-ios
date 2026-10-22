# ASoftware iOS

**Apple's iOS 16 running in a window on a Windows PC.**

ASoftware iOS boots the unmodified iOS 16.7.16 (20H392) userland of the iPhone X on QEMU's `virt`
machine: launchd, the system daemons, backboardd, SpringBoard and the stock apps. The kernel is
Apple's open-source XNU (xnu-8796) with the patches of [ios-sweet](https://github.com/dipa-studio/ios-sweet)
by dipa-studio, which first brought this userland up on a Redmi Note 10 Pro, plus our own patches
for QEMU's virtual hardware.

> Experimental. Everything renders on the CPU (no GPU), so it is slow, and Apple's security model
> is mostly switched off. Not affiliated with Apple. No Apple software is in this repository: you
> supply the IPSW, and the tools build the iOS disk from it on your PC.

## What works

| Area | State |
| --- | --- |
| Boot | Lock screen in about 2 minutes (4 vCPUs, TCG, i7-13700HX) |
| GUI | Lock and home screen, wallpapers and widgets, Control Center, Settings, Safari |
| Input | Mouse as the touchscreen; F1 Home, F2 side button, F3/F4 volume; the PC keyboard as a hardware keyboard |
| Network | QEMU user networking (virtio-net); Safari loads web pages |
| Apps | `.ipa` files dropped into a Windows folder install while iOS runs (`asoftinstalld`) |
| Power | Closing the window shuts iOS down cleanly (sync, unmount, power off) |
| Storage | What iOS writes is kept in a per-user disk layered on the built image |
| Window | Sized to the phone's shape, with a side bar: Home, Lock, Volume, Screenshot, Install .ipa, Shut down |

Not yet: audio, GPU acceleration, the App Store and other Apple services.

## Running it

`Start-iOS.cmd` boots iOS through `scripts/run-windows.ps1`. Everything that is not in the repo lives
in one work folder (`ASOFT_WORK`, default `work\` in the repo):

| In the work folder | What |
| --- | --- |
| `qemu\v11.1.2-asoft\` | Our QEMU build (`qemu/build-windows.sh`, or the `qemu-win` workflow) |
| `root\ios16-root-20H392-v3.qcow2` | The iOS disk, built from the IPSW |
| `root\ios16-user.qcow2` | What iOS writes; created on first start, `-Reset` starts over |
| `ipa\` | Drop `.ipa` files here while iOS runs |
| `runs\` | Kernel logs of each start |

The kernel comes from the `xnu` workflow (macOS) into `xnu/out-NNNN/`. A one-click installer that
sets all of this up is planned; until then the pieces are built as below.

## Building the pieces

- **QEMU** (Windows, MSYS2 UCRT64): `qemu/build-windows.sh`, see its header.
- **Kernel** (macOS): `.github/workflows/xnu.yml` builds Apple's XNU with
  [blacktop/darwin-xnu-build](https://github.com/blacktop/darwin-xnu-build) and `xnu/patches/`.
- **iOS disk** (WSL, Ubuntu 24.04, run as root): `scripts/wsl-build-hfsplus.sh` adds HFS+ to the WSL
  kernel; `scripts/build-root.sh` turns the IPSW's disk images into one HFS+ root
  (`tools/mkiosroot.sh`, `tools/sweet-root-tweaks.py`). The first boot rebuilds iOS's LaunchServices
  database, which takes about 20 minutes once. `tools/asoft-disk.sh installer` then adds
  `asoftinstalld`.
- **iOS apps** (macOS): `.github/workflows/ios-apps.yml` builds `asoftinstalld` and the test app.

## Layout

| Path | What |
| --- | --- |
| `xnu/patches/` | Patches on Apple's XNU: 0001-0081 from ios-sweet (the phone's drivers, inactive under QEMU), 0082 on for QEMU (PL011 console, virtio block/net/input, ramfb display, AMFI, power key, ...) |
| `qemu/` | Patches on QEMU 11.1.2 (redraw rate, close button powers iOS down, window title, phone-shaped window, side bar) and the Windows build script |
| `tools/` | Device tree (`mkadt.py`), boot payload (`mkpayload.py`), QEMU launcher (`qemu-sweet.py`), iOS root builder, disk tool (`asoft-disk.sh`) |
| `apps/` | Our iOS programs: `asoftinstalld` (installs .ipa files) and a test app |
| `scripts/` | Windows launcher, .ipa server, WSL disk build; `dev/` holds benchmark and debugging tools |
| `.github/workflows/` | Kernel, QEMU for Windows, iOS apps |

## Licenses

- This repository: MIT, see [LICENSE](LICENSE) (ASoftware and dipa-studio).
- `xnu/patches/` modify Apple's XNU, which is under the Apple Public Source License 2.0; a kernel
  built from them is under the APSL too.
- `qemu/patches/` modify QEMU and are under its GPL v2.
- iOS itself is Apple's and is not distributed here.
