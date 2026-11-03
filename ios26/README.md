<div align="center">

# ASoftware iOS 26 (research preview)

**iOS 26 in a window on a Windows PC, its interface drawn by the PC's own GPU.**

<img src="screenshots/ios26-gpu.gif" width="420" alt="iOS 26 in the ASoftware window: Settings, scrolling, General, the home screen">

<sub>In real time, the pauses between gestures cut, on Windows 11 with an RTX 4080 Laptop: Settings (opened once before), scrolling, General, Home, the home screen's pages.</sub>

English · [Türkçe](#turkce)

</div>

Apple's iOS 26.6.2 userland boots on QEMU on an ordinary x86-64 Windows PC, on the kernel of
Apple's own research VM platform (vphone600, from cloudOS 26.4b). iOS's Metal driver in the guest
sends its work to a paravirtual GPU, and on the PC that work runs on the host GPU through Vulkan:
the lock screen, SpringBoard, Settings and the system apps draw on an NVIDIA RTX 4080 under
Windows. [vphone-linux](https://github.com/YahiaAngelo/vphone-linux) runs the same guest on the
same GPU stack on Linux; this is the Windows host.

> [!WARNING]
> A research preview, not a product. `Install-iOS26.cmd` runs the build below for you, but it
> needs about 50 GB at its peak and two to three hours (no WSL needed). Apple's security model is mostly switched off. Not
> affiliated with Apple. No Apple software is in this repository or in our forks: you build
> everything from your own downloads from Apple, the guest's GPU driver too (the installer takes it
> out of Apple's cloudOS IPSW on your PC).

## What works

| | |
| --- | --- |
| **GPU** | iOS's own Metal draws the interface; the PC's GPU runs it through Vulkan (tested: NVIDIA RTX 4080 Laptop, Windows 11) |
| **iOS** | Lock screen, home screen with the system apps, Settings and its pages, Weather |
| **Input** | Mouse as the touchscreen (tap, swipe, scroll), the PC keyboard, Home, side button and volume |
| **Gestures** | A Face ID iPhone's (an iPhone 16 Pro's layout: Dynamic Island, its status bar): swipe up to open and to go home, swipe up and hold for the app switcher, Control Center from the top right, Notification Center from the top left, back from the left edge. A drag from the display's left edge becomes iOS's back gesture (a quick swipe is too fast for the emulated app), and the side bar has Back and App switcher |
| **Window** | The ASoftware window and side bar of the iOS 16 build: Home, Lock, App switcher, volume, screenshots, full screen, pasted text |
| **Disk** | As the iOS 16 launcher: a throwaway overlay by default, `-Persist` keeps iOS's changes in a user overlay (the start menu's default), `-Keep` writes the base image |
| **Quick boot** | On a disk that keeps its changes: closing the window saves iOS as it is, and the next start goes on from there, its screen in about 8 s. `-NoQuickBoot`, or `[B]` in the menu, boots iOS every time |
| **Saved states** | The side bar's *Save state* and *Saved states…* |
| **Network** | `-Net`: a virtio-net NIC on QEMU's user-mode network; iOS brings `en0` up with 10.0.2.15 and Safari loads pages from the internet through it (checked by hand with a real site; DNS and TLS timings not measured) |
| **Wallpaper** | iOS 26's own wallpaper (MercuryPoster: a 3D scene iOS's Metal draws on the PC's GPU) on the lock and home screens, the Liquid Glass clock over it; `-Wallpaper collections` for iOS 17's Collections one (build step 5.3.6) |
| **OpenGL ES** | Apple's older graphics API, which many older iOS games and apps still draw with: without it they get no context and crash or draw nothing. Here OpenGL ES 1, 2 and 3 contexts open and OpenGL ES 2.0 draws on the PC's GPU (so far only our own test app, see below: no real game yet, textures and depth untested) |
| **Speed** | All CPU work is emulated (QEMU TCG). Measured on an i7-13700HX: lock screen about 2 minutes after start, Settings opens in about 4 s, a scroll answers in 0.3 s |

<img src="screenshots/lock-screen-wallpaper.png" width="24%" alt="Lock screen with iOS 26's wallpaper"> <img src="screenshots/lock-screen.png" width="24%" alt="Lock screen with iOS 17's Collections wallpaper"> <img src="screenshots/home-screen.png" width="24%" alt="Home screen"> <img src="screenshots/settings.png" width="24%" alt="Settings">

A saved state, and quick boot's, is about 3.7 GB on the disk iOS runs on: leave that much free. A
throwaway run loses them at exit. After a quick boot or a loaded state iOS's clock moves on by the
time away (qemu-sptm **ad92276** or later: XNU reads the hardware clock only at boot, so QEMU moves the
guest's counter on when it loads a state; a disk quick-booted on an older build keeps the time it
already lost until one `-NoQuickBoot` boot). While it runs, the guest's clock gains about a minute an
hour (the counter's 41 ns tick at 24 MHz). iOS also takes the PC's time zone, region format and 24- or
12-hour clock, as the iOS 16 build does: the launcher finds them (the Windows time zone through
Windows' ICU, the region and the clock from Windows' region format; `-TimeZone Europe/Istanbul`,
`-Region TR`, `-Clock 24` override them) and, on a cold boot, `scripts\guest-clock.py` sets in iOS
each one that differs from what this disk was given last (`<disk>.host.txt` next to it) over the
serial root shell: the time zone link, the region as iOS's Settings writes it (English with Türkiye:
`AppleLocale` `en_TR`, first language `en-TR`) and the 24-hour switch, then restarts SpringBoard, as
Settings does after a region change. A saved state is dropped for that once: that start is a full
boot, and about 4 minutes in the lock screen restarts once with the new settings; the next window
close saves a state with them. What you change in iOS's Settings stays until the PC's own setting
changes. The installer sets them in its wallpaper boot. It needs Python (the installer's
`tools\python`, or `pythonw.exe` on the PATH). With English and Türkiye the lock screen still writes
its short date the US way (*Sun Nov 1*), as it does when you pick Türkiye in iOS's Settings
yourself; iOS's own date formats are the Turkish ones there (19.08.2026, *19 August 2026
Wednesday*). *Restore* into an emulator that booted on its own needs
reims-vgpu **ae389a2c** and metal2vulkan **fbb1ae35**: an older build kept the GPU addresses of heaps
the running emulator had deleted, and the restored state came up with its dock flickering and black
squares for icons. A state another run saved needs reims-vgpu **ac33003f**: an older one kept Metal's own GPU ranges where the running emulator first made
them and refused the state's buffers there, and the loaded screen froze while the guest's GPU
restarted.

**OpenGL ES**: iOS's kernel names no OpenGL ES renderer for Apple's paravirtual GPU, so every
`EAGLContext` is nil ([vphone-cli #793](https://github.com/Lakr233/vphone-cli/issues/793), which
[#798](https://github.com/Lakr233/vphone-cli/pull/798) closed for its Mac guests on 2026-11-02). The
installer's `gpu` step runs `scripts\kc-gles.py`, which adds AppleMetalGLRenderer (OpenGL ES on Metal,
in the guest's own shared cache) to the GPU's personality in the kernelcache. The renderer's shaders
then need GraphicLoader with this repository's patch from 9cadb5c (it completes their AIR metadata,
on which the guest's Metal compiler crashed), reims-vgpu **fd7bd0b5** (it faulted on the renderer's
primitive-restart index) and metal2vulkan **79e1dd02** (it refused their language tag). With all four,
the test app in `glestest\` gets OpenGL ES 1, 2 and 3 contexts, and its OpenGL ES 2.0 triangles (vertex
attributes, a uniform, varyings) draw on the PC's GPU and read back the expected pixels. Textures,
depth and `discard` are not tested yet. A compiler plugin of your own (`-GpuPlugin FILE`) or a driver
bundle of your own keeps the plain kernelcache, since other plugins crash on these shaders. To update
a folder installed before this release, run `Install-iOS26.cmd -Only qemu` and then `Install-iOS26.cmd`:
the new plugin redoes the GPU layer and what is built on it by itself, but not the QEMU.

Not yet: a live `.ipa` install (`.ipa`s install by direct placement at the next start, and that start
takes about 11 minutes while iOS rebuilds its app database), a clean shutdown from the window (closing it saves or quits at once), audio, the App Store and Apple ID
services. App switcher cards show a blank page, not the app's last screen. For about 3 minutes after
the lock screen appears iOS's daemons keep every vCPU busy, so the first taps are slow.

## Is it really the GPU?

Three checks, each from a different side.

**1. Windows' own counters.** Windows counts GPU use per process: the numbers in Task Manager's
GPU columns. Measured on the QEMU process while iOS 26 ran, on a laptop with two GPUs:

| The QEMU process, from the lock screen on | RTX 4080 Laptop | Intel UHD (the other GPU) |
| --- | --- | --- |
| Dedicated GPU memory | **1.5 to 2.2 GB** | none (0.24 GB shared) |
| 3D engine | **bursts up to 80 %** when iOS draws | flat, 2 to 12 % |

<img src="screenshots/gpu-chart.png" width="760" alt="GPU use of the QEMU process over a run: memory and 3D engine on the RTX 4080, the Intel GPU flat">

QEMU's memory on the RTX 4080 climbs as iOS boots and loads its interface, most of it as the lock
screen comes up, at about 130 s. The 3D engine works in bursts, when the lock screen comes up, as
Settings opens and scrolls, and at each Home and swipe, then waits: iOS's CPU work is emulated and
keeps four host cores busy, so the CPU, not the GPU, sets the pace. Measured on 2026-10-31, in the run
the GIF above comes from, on Windows 11, i7-13700HX, RTX 4080 Laptop (driver 610.74), 4 vCPUs, with
[`scripts/gpu-sample.ps1`](scripts/gpu-sample.ps1), drawn by [`scripts/gpu-chart.py`](scripts/gpu-chart.py).

**2. What iOS sends.** reims-vgpu can trace the paravirtual GPU's command stream
(`REIMS_VGPU_TRACE`). We counted it up to the lock screen:
- **Without the guest's Metal driver:** iOS sent 4 command buffers and no GPU textures. It draws
  every surface on the CPU and the host only shows them.
- **With the driver:** iOS sent 573 Metal command buffers and drew into 70 render-target surfaces.

The picture differs too. Without its Metal driver (the same disk with the bundle deleted) iOS has no
wallpaper, no dock platter and blank icons, as those are drawn with Metal:

<img src="screenshots/cpu-vs-gpu.png" width="760" alt="The home screen in the window, without and with the guest GPU driver">

**3. The library's log.** At start, reims-vgpu names the device it runs the guest's Metal on, and
metal2vulkan names the Vulkan driver it translates for:

```
reims_vgpu_core::device: device starting on Metal device NVIDIA GeForce RTX 4080 Laptop GPU, guest pages of 16 KiB
metal2vulkan: the device NVIDIA GeForce RTX 4080 Laptop GPU: its policy takes native device maths ...
```

To check it yourself, open Task Manager → *Details*, add the *GPU engine* and *Dedicated GPU
memory* columns, and look at `qemu-system-aarch64w.exe` while you use iOS.

## How it works

```
Windows ── QEMU: jprx/qemu-sptm + our -M vresearch machine (TCG)
  │          ├─ SPTM, TXM and the kernel of Apple's research VM platform (cloudOS 26.4b)
  │          │    └─ iOS 26.6.2 userland of the iPhone, on HFS+ disks
  │          │         └─ AppleParavirtGPU Metal driver ──► PVG device (pvg=reims)
  │          ├─ USB: touchscreen (a built-in digitizer), keyboard, consumer keys
  │          └─ software stand-ins for the absent Secure Enclave (keystore, ACM)
  └─ reims-vgpu (ported to Windows) ─► metal2vulkan ─► Vulkan ─► the PC's GPU
```

| Part | Where | What we added |
| --- | --- | --- |
| QEMU | [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/asoft), branch `asoft` | The `vresearch` machine (boot, device tree, SMP, PVG display and GPU, SEP/keystore/ACM stand-ins, HFS+ data protection), a USB touchscreen and consumer keys, the Windows build, the ASoftware GTK window (iOS 16's too: the same build boots it with `-M virt`) |
| GPU, host side | [alpersamur3/reims-vgpu](https://github.com/alpersamur3/reims-vgpu/tree/windows), branch `windows` | A Windows OS layer: guest RAM as section views (`MapViewOfFile3` placeholders), IOSurface backing, read-only imports through a writable twin, the x86-64 build serving 16 KiB guest pages |
| Metal → Vulkan | [alpersamur3/metal2vulkan](https://github.com/alpersamur3/metal2vulkan/tree/windows), branch `windows` | The `x86_64-pc-windows-gnu` build |
| This folder | `ios26/` | The launcher and the scripts that build the disk, device tree, trust cache and ramdisk |

## Build

> [!IMPORTANT]
> Written down from the runs that built our disk; `Install-iOS26.cmd` runs the steps in this
> order. The installer has built a disk iOS 26 boots from end to end once, on our PC, from an empty
> folder and a new WSL distro (2026-11-02); not yet on a second PC, and not yet without WSL. Read
> each script before you run it.

The easy way is the repository's one installer, `Install-ASoftware.cmd` at the top of the checkout
([Install](../README.md#install)): choose iOS 26 (or both), then *Fast install (WSL)* or *Install
without WSL*. It checks the PC once, shows the download, the disk space at the peak and after and
the time before it starts, runs `Install-iOS26.ps1` with the QEMU it shares with iOS 16, shows the
step and the time left in the window title, and goes on after a stop or a restart. On our PC
(i7-13700HX, 24 threads, NVMe, 40 Mbit/s):

| | Fast install (WSL) | Install without WSL |
| --- | --- | --- |
| Needs | WSL 2: if it is missing the installer offers to install it (administrator, one restart) | nothing more: the helper VM is in the release package |
| Linux steps run in | a WSL distro (Ubuntu 24.04, made and set up by the `linux` step) | the helper VM: our QEMU under TCG, up to 8 vCPUs and 4 GB |
| Download | 11.4 GB; a new distro and the kernel source for its hfsplus module another 0.9 GB | 11.4 GB |
| Disk: peak / after | 49 GB / 25 GB, and about 7 GB for the distro where WSL keeps them | 49 GB / 25 GB |
| Time | about 1 h 45 min (measured: 75 min of steps, plus the 11 GB from Apple, about 30 min at 52 Mbit/s); a new distro about 15 min more | about 1 h 40 min (its steps timed one by one, not end to end) |

`ios26\Install-iOS26.cmd` is the same build on its own:

```
ios26\Install-iOS26.cmd
ios26\Install-iOS26.cmd -Work D:\ios26
```

The installer takes a fresh Windows PC to a disk iOS 26 boots from. It prints the step it runs and
each step leaves a marker in `<work folder>\install`, so you can stop it and run it again: it goes
on where it stopped, the downloads too. A failed step says which README step it was and where its
log is; fix the cause and run it again. It never rebuilds disks it did not make: a folder that has
disks but no `install` folder is refused (`-List`, `-Check` and `-DryRun` still work there), and a
disk you put into its own folder stops the step that would rebuild it until `-From` or `-Only` names
that step.

The guest's GPU driver needs no Mac: the installer takes Apple's bundle out of the cloudOS IPSW it
downloads anyway and adds the Metal compiler plugin cloudOS lacks, built by our CI
([below](#the-guests-gpu-driver)). A driver bundle of your own, or none (GPU-less), is the menu's
**[G]**; change it and run the installer again: it redoes only the GPU layer and the wallpaper.
It needs **no WSL**, no administrator and no restart: the steps that need Linux (reading Apple's
APFS images, writing the HFS+ disk) run in WSL if it is installed, and otherwise in a small Linux VM
on the QEMU it downloads anyway, as iOS 16's installer does ([below](#without-wsl-the-helper-vm)).

QEMU comes prebuilt: the installer downloads `asoft-qemu-2026.11.03.zip` (125 MB) from
qemu-sptm's [`asoft-7364c4e` release](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)
(qemu-sptm `asoft` 7364c4e with reims-vgpu `windows` fd7bd0b5 and metal2vulkan `windows` 79e1dd02,
`qemu-img.exe` included; iOS 16's installer takes the same package), checks its SHA-256 and unpacks
it into `<Work>\qemu`. `-QemuFrom source`
builds it in MSYS2 instead (hours; MSYS2 is installed with winget if it is missing) and `-QemuFrom
D:\path\to\dist` takes a build you have (`win-build.sh`'s `dist`).

### You need

- Windows 10 2004 or later, or Windows 11, x64; 8 or more cores, 16 GB RAM (the guest gets 4 GB)
- About 55 GB free on the work folder's drive (the build peaks at about 49 GB and keeps about 25);
  with WSL, about 5 GB more on WSL's drive for its tools and the `hfsplus` module
- A Vulkan GPU whose driver has `VK_EXT_external_memory_host` (tested: NVIDIA RTX 4080 Laptop)

The installer gets the rest. By hand, you also need:

- MSYS2 with the UCRT64 toolchain: QEMU's build dependencies (`$MsysPackages` in `Install-iOS26.ps1`
  lists them), with GTK 3, ANGLE (`mingw-w64-ucrt-x86_64-angleproject`) and Rust (`mingw-w64-ucrt-x86_64-rust`)
- WSL 2 (Ubuntu 24.04), as root: [ipsw](https://github.com/blacktop/ipsw), `qemu-utils`, `hfsprogs`, `gdisk`,
  [apfs-fuse](https://github.com/sgan81/apfs-fuse), `python3`, `rsync`, and an `hfsplus` kernel module
  for WSL's kernel, which has none (`HFSPLUS_KO=path/to/hfsplus.ko`). `installer/wsl-setup.sh install`
  sets all of this up, `wsl-setup.sh check` lists what is missing. Or, without WSL, the helper VM
  and ipsw's Windows build ([Without WSL](#without-wsl-the-helper-vm))
- `sysroot/ios_sysroot.tar.gz` from [jprx/darwin-vm](https://github.com/jprx/darwin-vm): bash and
  coreutils for the shell ramdisk and the root

Folders (the installer saves them in the menu's config, below):

| Folder | Variable | Holds | Default | Installer option |
|---|---|---|---|---|
| Work folder | `ASOFT26` | Apple's files, the disks and the runs | `ios26` on the fixed drive with the most room | `-Work D:\ios26` |
| Sources | `ASOFT26_SRC` | sources and the QEMU build | `asoft26-src` on the work folder's drive | `-Src` |
| WSL scratch | `ASOFT26_LINUX` | scratch space inside WSL | `/root/ios26` | `-LinuxDir` |

The work folder is a drive-letter path without spaces; WSL sees it as, say, `/mnt/d/ios26`, and it
is `-Work D:\ios26` for `Start-iOS26.ps1`. In MSYS the sources folder is a path such as
`/c/asoft26-src`. The WSL distro is `ios-emu` (`-Distro`); the installer makes it if it is missing.

### 1. QEMU and the GPU library (MSYS2 UCRT64, started from PowerShell)

```
git clone -b asoft https://github.com/alpersamur3/qemu-sptm %ASOFT26_SRC%\qemu-sptm
git clone -b windows https://github.com/alpersamur3/reims-vgpu %ASOFT26_SRC%\reims-vgpu
git clone -b windows https://github.com/alpersamur3/metal2vulkan %ASOFT26_SRC%\metal2vulkan-win
```

qemu-sptm's branch was `ios26` until 2026-11-01: in an older clone, `git fetch -p`, `git branch -m
ios26 asoft` and `git branch -u origin/asoft` (in `%ASOFT26_SRC%\qemu-sptm`) move it over.

1. `win-nettle.sh`: a static nettle 3.10.1 (put GNU's `nettle-3.10.1.tar.gz` in `deps\dl` first).
2. `ucrt.ps1 ios26\scripts\reims-build.sh`: reims-vgpu → `reims-dist`.
3. `win-build.sh`: QEMU → `dist`. Copy it to `<ASOFT26>\qemu`. The same build runs iOS 16 with
   `-M virt` (the top-level README's [QEMU](../README.md#qemu)): one QEMU for both.

### 2. Apple's files (WSL)

- **cloudOS 26.4b (23E5207q)**, the IPSW of Apple's Private Cloud Compute research VM (vphone600):
  extract it into `$ASOFT26/cloudos`. Used, none of them encrypted:
  - `kernelcache.research.vphone600` (and `kernelcache.release.vphone600`: `kdec.sh` decompresses both)
  - `Firmware/sptm.vresearch1.release.im4p`, `Firmware/txm.iphoneos.research.im4p`
  - `Firmware/all_flash/DeviceTree.vphone600ap.im4p`
  - the ramdisk `094-39914-031.dmg` and its trust cache
  - for the GPU driver (5.2): the OS image `094-39278-029.dmg.aea` (755 MB, encrypted, but its key
    is in its own AEA header) and its trust cache `Firmware/094-39278-029.dmg.aea.trustcache`
- **iPhone17,3 iOS 26.6.2 (23G90)**: `ipsw-get.py URL MEMBER OUT` fetches single members of the IPSW
  into `$ASOFT26/iphone`:
  - `094-97246-090.dmg.aea` (the OS)
  - `094-95368-092.dmg.aea` (the SystemOS cryptex)
  - `094-96441-094.dmg` (AppOS)
  - `Firmware/*.trustcache`
- `sysos.sh` and `m2-decrypt.sh` decrypt the two AEA images into `$ASOFT26/os`. `ipsw fw aea` gets
  the keys from Apple's key service.

### 3. Firmware, device tree and ramdisk (WSL)

1. *By hand*, in `$ASOFT26`: `ipsw img4 im4p extract cloudos/Firmware/all_flash/DeviceTree.vphone600ap.im4p -o cloud/vphone600ap.adt`
2. `kdec.sh`, then `unwrap-fw.sh` → `fw/bootkc`, `fw/sptm`, `fw/txm`, `fw/dtree.orig`
3. `QEMU_SPTM=<qemu-sptm checkout> python3 dt-root26smp.py fw/dtree.orig dtree-smp4 --cpus 4`
   (`dtree-smp8 --cpus 8` too, if you like: we have not booted 8 yet). With qemu-sptm 5eba0a3 or
   later it fills the product's syscfg keys from the tree's own gestalt variant (it prints the 42
   it filled): without them iOS takes the VM for an iPhone with a Home button (the old status bar,
   "Press home to open", Control Center from the bottom, no home gestures). A disk already booted
   with an older tree keeps that answer in its MobileGestalt cache: `root26-mgcache.py reset` on it.
4. `SYSROOT_TAR=<darwin-vm>/sysroot/ios_sysroot.tar.gz sysroot-check.sh`
5. *By hand:* unwrap the cloudOS ramdisk to `$ASOFT26_LINUX/rd/rd.apfs` and put its trust cache at
   `cloud/rd.trustcache.im4p`. Then run `mk-ramdisk.sh` and copy `rd-shell.hfs` to `$ASOFT26`. The
   machine wants a ramdisk even though iOS's root is on the disk.

### 4. The root disk (WSL, as root)

1. `DROP_SYSOS=1 mk-root26.sh` → `root26.qcow2` and `root26.qcow2.hashes`, then `m2-finish.sh`: it
   completes the sysroot step if that stopped on `cp -a`'s ACLs, and applies `root26-tweaks.py` (the
   console's root shell among them, which steps 4.5 and 5 use).
2. `mktc.py -2 root.tc iphone/*.trustcache root26.qcow2.hashes`: the trust cache.
3. `mk-root26g.sh root26.qcow2 root26g.qcow2`: the partitioned disk (system and a 16 GB Data volume).
4. Through `root26-do.sh root26g.qcow2 'python3 SCRIPT $R ...'`, in this order:
   1. `root26-prefs.py`, `root26-sb-undiag.py`, `root26-bbd-fix.py`. `root26-prefs.py` also turns
      the side button's press and hold off: under TCG iOS reads a click that wakes the display as
      a press and hold, which opened Siri. On a disk built before 2026-10-29, run it again on the
      top overlay (it is idempotent).
   2. *by hand:* `/private/var/keybags/systembag.kb`, a plist with `KeyBagKeys` = the data `SWEET`
      (owner root, mode 0600)
   3. `root26-churn.py on`, `root26-dbg-off.py`. `root26-churn.py` also takes out DumpPanic, which
      crashes every two minutes for ever, and three daemons that do nothing offline.
   4. On a disk built before 2026-10-30: `root26-commcenter.py` on the top overlay. The old
      `root26-tweaks.py` removed CommCenter, and without it SpringBoard resets its idle timer every
      second: the display never slept, the Lock Screen was drawn for ever (half the guest's CPU in
      the first 30 minutes) and the side button seemed dead. Measured with it back: the Lock Screen
      goes dark in 7 s, the side button locks and wakes, and the work after a start ends in about 15
      minutes instead of 30. See vphone-cli's `Research/Guest/service_trimming.md` before cutting
      more: CommCenter, cloudd, mobileassetd, sleepd and siriactionsd make the guest worse when off.
   5. `root26-trim.py on`: vphone-cli's trimmed service profile for 26.6.2 (120 jobs, as launchd
      overrides in `disabled.plist`; `off` undoes it). `root26-prefs.py` also sets Auto-Lock to
      5 minutes and the Lock Screen to go dark after 60 s instead of 6. On an older disk, run both
      on the top overlay.
5. Boot it once (`Start-iOS26.ps1 -Disk root26g.qcow2`) and quit. Then, again through
   `root26-do.sh`, run `root26-persona.py on` and `root26-mgcache.py reset`. `root26-do.sh` replays
   the HFS+ journal first.

### 5. Activation, the GPU driver and the apps (overlays)

Put each layer in a qcow2 overlay on the one before it, for example
`qemu-img create -f qcow2 -b root26g.qcow2 -F qcow2 root26h.qcow2`. Name the top one `root.qcow2`.
Every binary you change or add needs its CDHash in the trust cache: get it with `cdhash.py FILE`
(or from the output of `reattest.py` / `dsc-patch.py`), then `mktc.py -2 root.tc root.tc hashes.txt`.

1. **Activation:**
   1. Copy `/usr/libexec/mobileactivationd` off the root as `mobileactivationd.orig`.
      `hact_patch.py mobileactivationd.orig mobileactivationd`, then
      `reattest.py mobileactivationd.orig mobileactivationd`.
   2. Put the result at `/usr/libexec/mobileactivationd` (same owner and mode) and add its new CDHash.
   3. We gave its entry the original's constraint category 3. `mktc.py` writes 0 for a text list;
      `amfi-lc-off=on` should make that work too, but we have not tried it.
2. **GPU driver** (optional, see below): `cloudos-gpu-driver.sh cloudos/094-39278-029.dmg.aea OUT
   cloudos/Firmware/094-39278-029.dmg.aea.trustcache` (WSL, as root) takes
   `AppleParavirtGPUMetalIOGPUFamily.bundle` out of the cloudOS OS image; add the compiler plugin
   `libAppleParavirtCompilerPluginIOGPUFamily.dylib` to it. Put the bundle into
   `/System/Library/Extensions` (root:wheel, 755/644) and add the CDHashes of its Mach-Os. Without
   it, iOS draws on the CPU and reims only shows the frames; that also reaches the home screen.
3. **Apps and wallpaper:**
   1. `apply-staged.sh`.
   2. Copy `dyld_shared_cache_arm64e*` from the root's
      `System/Cryptexes/OS/System/Library/Caches/com.apple.dyld` to `$ASOFT26/dsc`.
   3. `dsc-patch.py $ASOFT26/dsc 0x220649088 f6179f1a20070034 3600805239000014 $ASOFT26/dscpatch`
      (PosterBoard's purgeable-file call, which HFS+ refuses).
   4. `apply-apps.sh`, then `root26-nowatchdog.py`.
   5. Add the patched subcache's CDHash.
   6. The wallpaper: iOS 26's default poster, MercuryPoster (`space.dynamic`), is a 3D scene its
      Metal draws; it needs metal2vulkan's `windows` branch at 56705098 or later (before that it
      drew black: its uniforms are bound 4 bytes past a multiple of 16, which iOS allows and the
      translator read 4 bytes early). Boot once with `-Keep` and leave it for 6 minutes:
      PosterBoard's first run writes the poster store, and the throwaway overlay of a normal start
      would redo that every time.
      Optional, a lighter wallpaper (the poster's extension costs the emulated CPU): iOS 17's
      Collections one. PosterBoard picks it for two product types only
      (`_defaultLockScreenWallpaperExtensionIdentifier`, a `B.EQ`); make it unconditional with a
      second 4-byte patch on the same subcache,
      `dsc-patch.py $ASOFT26/dscpatch 0x22066ebc0 a0000054 05000014 $ASOFT26/dscpatch-wp`, write
      that `.42` into an overlay `root-collections.qcow2` on `root.qcow2` as in `apply-apps.sh`
      (`cat >`, keeping the hard link), delete PosterBoard's
      `Library/Application Support/PRBPosterExtensionDataStore` in its data container (its first
      run then sets up wallpaper 7565), copy `root.tc` to `root-collections.tc` with the new
      CDHash added, and bake the store as above with `-Wallpaper collections -Keep`.

4. **Gestures:** `edge-patch.py $ASOFT26/dsc $ASOFT26/dscpatch-edge` (UIKitCore's touch edge type,
   `edge-cave.s`: our touchscreen's driver sets no edge bits, and without them no touch is an edge
   touch: no home gesture, app switcher or edge swipe back). Write that `.03` into the image as
   `apply-apps.sh` writes `.42` and add the CDHash it prints (to `root-collections.tc` too).

Then run `Start-iOS26.ps1 -Work D:\ios26`. The lock screen comes after about 2 minutes; press Home (F1).

The disk works as in the iOS 16 launcher: by default iOS writes to a throwaway overlay and the
image is as built again at the next start; `-Persist` keeps what iOS writes (settings, apps) in
`root26-user.qcow2`, an overlay on the base image, with the `.ipa`s you install, and `-Persist -Reset`
drops that overlay first; `-Keep` writes the base image itself. On a disk that keeps its changes
closing the window saves the machine's state there, as its snapshot `asoft-quick`, and the next start
resumes it (QEMU deletes the state once the machine runs; one it cannot resume, of another build or
other options, is dropped and iOS boots). `-NoQuickBoot` boots every time, and an `.ipa` install drops
the state. Two launchers on one disk refuse to start. `-Net` adds a
virtio-net NIC on QEMU's user-mode network (see *What works*).

### Start menu and installer (Start-iOS26.cmd, Install-iOS26.cmd)

As the iOS 16 launcher does, `Start-iOS26.cmd` offers the start options every time and remembers
your setup. The menu's choices (work folder, wallpaper, disk mode, network, vCPUs) are saved in
`%LOCALAPPDATA%\ASoftware iOS 26\ios26.config.json`, so later starts reuse them; `Start-iOS26.cmd
-NoMenu` starts at once with the saved setup, and `Start-iOS26.ps1 ...` is still the launcher with
every option.

The first run (of the menu or of the installer) asks where the work folder is and where the guest
GPU driver comes from: Apple's cloudOS IPSW (the default; the installer extracts it), a driver bundle
folder you have (a folder picker), or none. Without a driver iOS runs *GPU-less*: it draws on the CPU
and the host only shows the frames — it reaches the home screen, but everything is slower. The
driver is baked into the disk when the disk is built, so this records the choice, it is not read at
run time: to change it later, choose again with the menu's **[G]** and run `Install-iOS26.cmd` again
(it redoes the GPU layer, step 5.2, and the wallpaper).

`Install-iOS26.cmd` runs the whole *Build* above: that setup, the Windows checks, the Linux tools (WSL's or the helper VM),
QEMU, only the needed members of Apple's two IPSWs (about 10.5 GB, resumable), the firmware, device
trees, ramdisk and disk, three boots without you (the first boot of 4.5, the wallpaper bake of 5.3.6
and, with `-Collections`, the Collections disk), the checklist of what the launcher needs, and a
Start-menu shortcut. Close a running iOS 26 before the boot steps and let their window close by
itself. The wallpaper step takes about an hour: most of it is iOS's DataMigration, once per disk, whose
bar under the Apple logo can sit still for a long time, and then the screen goes dark. Doing it here
is what makes your own first start take about 2.5 minutes instead of about 50. Options:

| Option | What it does |
|---|---|
| `-List` | The steps, the README step each runs, and which are done |
| `-Check` | What this PC has: Windows, the Linux tools (WSL or the helper VM), QEMU, the outputs. Changes nothing |
| `-DryRun` | Prints every command the steps would run. Runs nothing |
| `-From STEP`, `-Only STEP` | Redoes STEP and everything after it, or just STEP (a disk step: the disk steps after it are redone on the next run) |
| `-Collections`, `-NoCollections` | Also builds `root-collections.qcow2` (5.3.6); remembered. Also on when the menu's wallpaper is *collections* |
| `-QemuFrom auto\|release\|source\|FOLDER` | Where QEMU comes from. `auto`: the release package (`source` instead when it cannot be downloaded and MSYS2 is installed); with no package set, the work folder's QEMU, else `source` if MSYS2 is installed |
| `-CloudOsIpsw FILE`, `-IPhoneIpsw FILE` | Takes Apple's files from IPSWs you already have |
| `-GpuPlugin FILE` | Takes the GPU driver's compiler plugin from a file you have instead of our release |
| `-Linux auto\|wsl\|helper` | Where the Linux steps run: `auto` (the default) WSL if it is installed, else the helper VM ([Without WSL](#without-wsl-the-helper-vm)); remembered |
| `-KeepBuildFiles` | Keeps the decrypted images and the intermediate disk (about 32 GB) |
| `-BakeMinutes N` | How long the wallpaper boot leaves iOS running once its UI is up (6) |
| `-NoShortcut` | No Start-menu shortcut |

The installer puts each layer of step 5 in its own overlay with its own trust cache, so a driver
added later redoes only the layers above the apps: `root26g.qcow2`/`root26.tc` (4.3-4.5),
`root26-activation` (5.1), `root26-apps` (5.3-5.4), `root26-gpu` (5.2, with the driver),
`root.qcow2`/`root.tc` (the wallpaper, 5.3.6) and `root-collections` (with `-Collections`). A redone
step rebuilds its layer from scratch; your own overlays on a rebuilt disk (`root26-user.qcow2`, the
`-apps` overlays of `.ipa` installs) can no longer boot and are kept as `.old`. The encrypted and
decrypted Apple images and the intermediate disk are removed once used (`-KeepBuildFiles` keeps them).

The release package `-QemuFrom auto` downloads is `asoft-qemu-2026.11.03.zip` of qemu-sptm's
[`asoft-7364c4e` release](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e) (125 MB,
531 MB unpacked; `$QemuRelease` in `Install-iOS26.ps1` has its URL and SHA-256): `win-build.sh`'s
`dist` without its `backup-*` folders,
that is `qemu-system-aarch64.exe` and the windowless `qemu-system-aarch64w.exe` 11.1.0 (qemu-sptm
`asoft` **7364c4e**, `-M vresearch` for iOS 26 and `-M virt` for iOS 16, built with reims-vgpu
`windows` **fd7bd0b5** and metal2vulkan `windows` **79e1dd02**), `qemu-img.exe` from the same build
(the launcher's overlays, quick boot's saved states), the ANGLE, GTK and GLib runtime they load (DLLs, `lib\`, `share\`, from MSYS2 UCRT64)
and `BUILD.txt`. For a new build, `installer\Make-QemuPackage.ps1 -Dist <win-build.sh's dist>
-Version 2026.11.03 -Url https://...` makes the zip and prints the `$QemuRelease` line with its
SHA-256; put that line into `Install-iOS26.ps1` and `installer\Install-ASoftware.ps1`.

The published launcher needs a recent build: qemu-sptm `asoft` **4eee4e5** or later (older QEMU
rejects the `usb-kbd` `idle-reports` option and will not boot) and reims-vgpu `windows`
**65e09172** or later (the screen-off cover needs it). Saved states and quick boot need qemu-sptm
**52f3606**, reims-vgpu **ac33003f** and metal2vulkan `windows` **e5b58af7** or later, built together
(an older QEMU keeps the buttons off, an older metal2vulkan can end the emulator some seconds after
Home and a page swipe, an older reims-vgpu can break the dock and the icons when *Restore* loads a
state into a running emulator, a pair older than reims-vgpu 44a9dac6 and metal2vulkan e5b58af7 can
place a restored app's texture over another app's live one, and a reims-vgpu older than ac33003f
can refuse the buffers of a state another run saved, its GPU restarting until the screen freezes);
the clock catching up after a load needs qemu-sptm **ad92276**, and the right date at every cold
boot needs qemu-sptm **7364c4e**. The release package above has all of these. Rebuild QEMU (step 1) if
yours is older.

`.ipa` installs: the side bar's *Install .ipa…* and the `ipa` folder are wired in the launcher
(`ipa-server.py`, `ASOFT_IPA_DIR`, and `-Net`), and the `asoftinstalld` daemon (built on macOS, as
in the iOS 16 build) runs on the disk, fetches the `.ipa` and reaches installd. But installd wants
an APFS volume and the disk's Data volume is HFS+, so the *live* install stops there (error -4). An
app from an `.ipa` does run on iOS 26 another way: place its `.app` into `/Applications` with its
Mach-O's CDHash in the trust cache and rebuild LaunchServices, exactly as the system apps are
installed (step 5.3 / `apply-apps.sh`). `Install-Ipa.ps1` does that offline, in WSL or, on a PC set up
without WSL, in the helper VM (about a minute). Tested with a small Hello app: it appears on the home
screen and opens. The live `asoftinstalld` path is waiting on an APFS Data volume.

### Without WSL (the helper VM)

`-Linux` says where the Linux steps run (remembered in the config): `auto`, the default, takes WSL
if it is installed and the helper VM if not; `wsl` and `helper` force one. With the helper VM:

- **On Windows**, with [ipsw](https://github.com/blacktop/ipsw)'s Windows build (3.1.739, which the
  `linux` step downloads and checks by SHA-256): the AEA images are decrypted (2, 5.2), the im4p
  files unwrapped and the kernelcaches decompressed (3.1, 3.2, 3.5); `qemu-img.exe` makes the step 5
  overlays.
- **In the helper VM**, what mounts an APFS or HFS+ volume or writes a partition table: the ramdisk
  (3.5), the root disk (4.1), the partitioned disk (4.3), the tweaks and the persona (4.4, 4.5) and
  the copies onto and off the disk in step 5. It is iOS 16's installer's helper: Linux 6.12 and an
  Ubuntu 24.04 arm64 userland (apfs-fuse, hfsprogs, gdisk, rsync, Python), booted by the QEMU of
  step 1 under TCG with up to 8 vCPUs and 4 GB. The bash scripts above run in it unchanged; QEMU
  opens the work folder's disks (overlays with their backing files too) and the scripts get them as
  block devices instead of through `qemu-nbd`. The scripts and the step's inputs go in as a tar on
  a read-only disk, the outputs come back as a tar ([`installer/helper/job-run.sh`](../installer/helper/job-run.sh)),
  and the VM's console is in the step's log.

Measured on 2026-11-02 on an i7-13700HX (24 threads, NVMe), with an iOS 16 and an iOS 26 QEMU
running at the same time, Apple's files from local IPSWs:

| Step | Without WSL | With WSL | |
| --- | --- | --- | --- |
| decrypt | 4 s (the SystemOS, 2 GB) | 1.2 min (both images, 10.2 GB) | ipsw.exe / ipsw |
| firmware | 2 s | 9 s | ipsw.exe |
| ramdisk | 1.3 min | 24 s | |
| rootfs | 34.7 min | 6.1 min | without WSL 26 min of it the OS tree's copy out of APFS (apfs-fuse under TCG, about 8 MB/s) |
| partition | 2.6 min | 3.2 min | the 32 GiB copy |
| tweaks | 1.3 min | 8 s | |
| activation | 1.5 min | 13 s | two VM runs, the patch on Windows |
| apps | 6.1 min | 1.2 min | |
| gpu | 1.3 min | 20 s | |

The Linux steps took 49 minutes in all without WSL and 13 with it (the WSL column: the end-to-end
run through `Install-ASoftware.cmd` on the same PC the same day); each
VM run spends about 40 s starting and checking the disk's journal. With the downloads and the two
boots a build without WSL takes about 1 h 40 min on a PC like this one at 40 Mbit/s (an estimate:
not run end to end).

The VM is `installer/helper/out/Image.gz` and `initrd.gz`, which the `linux` step copies into
`<Work>\tools\helper` and tests. iOS 16's release package has them; one from before 2026-11-02
lacks tools these steps need (`job-run.sh`, `sgdisk`, `awk`), and the `linux` step says so. In a
git checkout build them once, as root on an x86-64 Linux or in WSL (on any PC: the files are the
same everywhere), with `mmdebstrap`, `cmake`, `gcc-aarch64-linux-gnu` and `g++-aarch64-linux-gnu`:

```
installer/helper/build-kernel.sh LINUX_SRC installer/helper/out
installer/helper/build-rootfs.sh APFS_FUSE_SRC installer/helper/out
```

`LINUX_SRC` is a Linux source tree (6.12 tested), `APFS_FUSE_SRC` a clone of
[apfs-fuse](https://github.com/sgan81/apfs-fuse) (66b86bd tested). The initrd is 29 MB.

### The guest's GPU driver

`AppleParavirtGPUMetalIOGPUFamily.bundle` is Apple firmware content. It is not in this repository
and never will be: vphone-cli stopped shipping it for the same reason. The installer (menu choice
*cloudOS*, the default) makes it on your PC from your own download, in two parts:

- **The driver** comes out of the cloudOS 26.4b IPSW's OS image, `094-39278-029.dmg.aea`: the
  23E5207q driver (64.4.4) that vphone-cli and vphone-linux get from a cloudOS restore, byte for byte.
  Apple's key server no longer gives out cloudOS keys (403 for every build), but each cloudOS OS
  image carries its AEA key in its own header (`encryption_key`), so `ipsw fw aea` decrypts it
  offline. [`scripts/cloudos-gpu-driver.sh`](scripts/cloudos-gpu-driver.sh) decrypts the image,
  mounts it read-only with apfs-fuse, copies the bundle, checks that its binary's CDHash
  (`113e1e21…`) is in that IPSW's own trust cache and deletes the 1.4 GB image: about 20 s for the
  whole GPU step here, the member read from a local IPSW.
- **The Metal compiler plugin**, `libAppleParavirtCompilerPluginIOGPUFamily.dylib`, is in no cloudOS,
  and without it backboardd crashes and iOS restarts into recovery. It is not Apple's:
  [GraphicLoader](https://github.com/Lakr233/vphone-cli/blob/main/VPhoneGuestComponents/GraphicLoader/README.md)
  in vphone-cli (MIT), 0xjohnnydev's clean-room reimplementation. Our workflow
  [`graphicloader.yml`](../.github/workflows/graphicloader.yml) builds it with vphone-cli's own make
  target (arm64e, ad-hoc signed) after one fix,
  [`graphicloader/main.mm.patch`](graphicloader/main.mm.patch): `main.mm` hands
  `MTLMetalLibCreateExecutableWithTriple` the shared module instead of the module's target triple,
  and unpatched the guest's libraries come out with a garbage triple that reims refuses (QEMU stops
  30 s into the boot). The installer downloads that build from the release
  [graphicloader-57bbc93-p1](https://github.com/alpersamur3/asoft-ios/releases/tag/graphicloader-57bbc93-p1)
  (vphone-cli 57bbc93 and the patch, with its license and build record) and checks its SHA-256
  (`$GpuPluginRelease`). `-GpuPlugin FILE` takes another build.

The installer puts both CDHashes into the GPU layer's trust cache. Or bring a bundle of your own
(menu choice *folder*), copied as it is with its plugin: [vphone-cli](https://github.com/Lakr233/vphone-cli)'s
`fw prepare` makes one on an Apple silicon Mac, and vphone-linux's
[CREATE-ON-LINUX.md](https://github.com/YahiaAngelo/vphone-linux/blob/main/docs/CREATE-ON-LINUX.md)
from a stock cloudOS restore under QEMU on Linux (we have not tried that route).

## Tools

- `Start-iOS26.cmd` / `Start-iOS26-Menu.ps1`: the start menu, `Install-iOS26.cmd` / `Install-iOS26.ps1`:
  the installer (both above); `installer/wsl-setup.sh` sets up WSL's tools and `installer/Make-QemuPackage.ps1`
  packages a QEMU build for a release.
- `scripts/ipa-server.py`: serves a Windows folder of `.ipa` files to the guest's `asoftinstalld`
  (the launcher starts it; the guest fetches `http://10.0.2.2:8765`).
- `qmp.py`: taps and swipes over QMP, for scripts and tests.
- `console.py`: the guest's root shell on the serial console (127.0.0.1:4451).
- `ppmfix.py`: decodes QEMU's PPM screendumps correctly. QEMU pads rows to 4 bytes, so a
  1179-pixel-wide frame looks sheared in most viewers.

## Credits and licenses

- [jprx/qemu-sptm](https://github.com/jprx/qemu-sptm): QEMU with Apple's SPTM/TXM and GXF, the base
  of our machine (GPL-2.0, as QEMU). [jprx/darwin-vm](https://github.com/jprx/darwin-vm): the sysroot.
- [steelbrain/reims-vgpu](https://github.com/steelbrain/reims-vgpu) and
  [steelbrain/metal2vulkan](https://github.com/steelbrain/metal2vulkan): the paravirtual Apple GPU
  on Vulkan and the Metal-to-Vulkan translator our Windows ports build on (their own licenses).
- [vphone-cli](https://github.com/Lakr233/vphone-cli): research on the vphone600 guest (Setup
  Assistant, activation, the guest GPU driver), and GraphicLoader, the GPU driver's compiler plugin
  our CI builds (MIT; its source is 0xjohnnydev's clean-room
  [metal-patch](https://github.com/0xjohnnydev/0xjohnnydev.github.io/blob/main/blog/assets/metal-patch/main.mm)).
- [vphone-linux](https://github.com/YahiaAngelo/vphone-linux): the same guest and GPU stack on Linux.
- The scripts in this folder are MIT, as is the rest of this repository.

<a name="turkce"></a>

## Türkçe

**iOS 26, Windows bilgisayarda bir pencerede; arayüzünü bilgisayarın kendi ekran kartı çiziyor.**

Apple'ın iOS 26.6.2 kullanıcı alanı, sıradan bir x86-64 Windows bilgisayarda QEMU üzerinde açılıyor.
Altta Apple'ın kendi araştırma VM platformunun (vphone600, cloudOS 26.4b) çekirdeği çalışıyor.
Misafirdeki iOS Metal sürücüsü işini sanal bir GPU'ya gönderiyor, bilgisayarda bu iş Vulkan üzerinden
ekran kartında koşuyor: kilit ekranı, SpringBoard, Ayarlar ve sistem uygulamaları Windows altında bir
NVIDIA RTX 4080'de çiziliyor. Aynı misafiri aynı GPU yığınıyla Linux'ta
[vphone-linux](https://github.com/YahiaAngelo/vphone-linux) çalıştırıyor; bu, Windows tarafı.

> [!WARNING]
> Bir araştırma önizlemesi, ürün değil. `Install-iOS26.cmd` yukarıdaki derleme adımlarını sizin
> yerinize yürütüyor, ama en çok yaklaşık 50 GB ve iki üç saat istiyor (WSL gerekmez). Apple'ın güvenlik modeli
> büyük ölçüde kapalı. Apple ile bir bağı yoktur. Bu repoda ve fork'larımızda Apple yazılımı yoktur:
> her şeyi Apple'dan kendi indirdiklerinizden üretirsiniz, misafirin GPU sürücüsünü de (kurucu onu
> sizin bilgisayarınızda Apple'ın cloudOS IPSW'sinden çıkarır).

**Çalışanlar:**
- **GPU:** iOS'un kendi Metal'i arayüzü çiziyor, Vulkan üzerinden ekran kartı çalıştırıyor.
- **iOS:** kilit ekranı, sistem uygulamalarıyla ana ekran, Ayarlar ve sayfaları, Hava Durumu.
- **Giriş:** fare dokunmatik ekran gibi çalışıyor (dokunma, kaydırma), PC klavyesi, Home, yan tuş ve
  ses tuşları.
- **Pencere:** iOS 16 sürümündeki ASoftware penceresi ve yan çubuğu.
- **Hız:** i7-13700HX'te kilit ekranı açılıştan yaklaşık 2 dk sonra geliyor, Ayarlar yaklaşık 4 sn'de
  açılıyor, kaydırma 0,3 sn'de tepki veriyor.
- **Hareketler:** Face ID'li iPhone düzeni (iPhone 16 Pro: Dynamic Island, onun status bar'ı): yukarı
  kaydırıp açma ve eve dönme, kaydırıp bekleyince uygulama değiştirici, sağ üstten Denetim Merkezi, sol
  üstten Bildirim Merkezi, sol kenardan geri. Ekranın sol kenarından başlayan sürükleme iOS'un geri
  hareketine çevriliyor (hızlı bir kaydırma emüle edilen uygulamaya fazla hızlı); yan çubukta Back ve
  App switcher var.
- **Duvar kağıdı:** iOS 26'nın kendi duvar kağıdı (MercuryPoster: iOS'un Metal'inin ekran kartında
  çizdiği 3B sahne), üstünde Liquid Glass saat; `-Wallpaper collections` iOS 17 Collections duvar kağıdı
  (derleme adımı 5.3.6, misafir CPU'suna daha hafif).
- **OpenGL ES:** Apple'ın eski grafik arayüzü; birçok eski iOS oyunu ve uygulaması hâlâ onunla çiziyor,
  o olmadan bağlam alamıyor, çöküyor ya da hiçbir şey çizmiyor. Burada OpenGL ES 1, 2 ve 3 bağlamları
  açılıyor, OpenGL ES 2.0 ekran kartında çiziyor (şimdilik yalnız kendi test uygulamamız: gerçek bir oyun
  henüz denenmedi, doku ve derinlik denenmedi).

**Kayıtlı durumlar ve hızlı açılış:** yan çubuğun *Save state* ve *Saved states…* düğmeleri çalışıyor.
Değişikliklerini tutan bir diskte pencereyi kapatmak iOS'u olduğu gibi kaydeder, sonraki açılış oradan
devam eder, ekran yaklaşık 8 sn'de gelir (`-NoQuickBoot` ya da menüde `[B]` her seferinde baştan açar).
Her kayıt, iOS'un çalıştığı diskte yaklaşık 3,7 GB tutar; geçici koşuda çıkışta kaybolur. Yüklemeden
sonra iOS'un saati aradaki süre kadar ileri gider (qemu-sptm ad92276 ve sonrası; eski yapıyla hızlı
açılmış bir disk kaybettiği süreyi bir `-NoQuickBoot` açılışına kadar geride tutar). Çalışırken misafir
saati saatte yaklaşık 1 dk ileri gider. iOS bilgisayarın saat dilimini, bölge biçimini ve 24/12 saat
ayarını da alır, iOS 16 sürümündeki gibi: başlatıcı bunları bulur (Windows saat dilimi Windows'un
ICU'suyla, bölge ve saat Windows'un bölge biçiminden; `-TimeZone Europe/Istanbul`, `-Region TR`,
`-Clock 24` ile ezilir) ve soğuk açılışta `scripts\guest-clock.py`, bu diske en son verilenden
(`<disk>.host.txt`, diskin yanında) farklı olan her birini seri kök kabuğundan iOS'a yazar: saat dilimi
bağlantısı, bölge iOS Ayarlar'ının yazdığı gibi (İngilizce ve Türkiye: `AppleLocale` `en_TR`, ilk dil
`en-TR`) ve 24 saat anahtarı; sonra SpringBoard'u yeniden başlatır (Ayarlar da bölge değişince
yapıyor). Bunun için kayıtlı durum bir kez bırakılır: o açılış tam açılıştır ve yaklaşık 4 dakika
sonra kilit ekranı yeni ayarlarla bir kez yeniden başlar; sonraki pencere kapanışı onlarla bir durum
kaydeder. iOS Ayarlar'ında yaptığınız değişiklik, bilgisayardaki ayar değişene kadar kalır. Kurucu
bunları duvar kağıdı açılışında yazar. Python ister (kurucunun `tools\python`'ı ya da PATH'te
`pythonw.exe`). İngilizce ve Türkiye ile kilit ekranı kısa tarihi yine ABD düzeninde yazar
(*Sun Nov 1*); Türkiye'yi iOS Ayarlar'ından kendiniz seçince de öyle. iOS'un kendi tarih
biçimleri Türk düzenindedir (19.08.2026, *19 August 2026 Wednesday*). Kendi açılmış bir emülatöre
*Restore* ile durum yüklemek
reims-vgpu ae389a2c ve metal2vulkan fbb1ae35 ister: eski derleme çalışan emülatörün sildiği heap'lerin
GPU adreslerini tutuyordu, yüklenen durumun dock'u yanıp sönüyor, ikonları siyah kare çıkıyordu.
Başka bir çalışmanın kaydettiği durum reims-vgpu ac33003f ister: eski derleme Metal'in kendi GPU aralıklarını emülatörün onları ilk yaptığı yerde
tutuyor, durumun buffer'larını orada reddediyordu; yüklenen ekran donuyor, misafirin GPU'su yeniden
başlıyordu.

**OpenGL ES**: iOS çekirdeği Apple'ın paravirtual GPU'su için bir OpenGL ES renderer'ı adlandırmıyor, bu
yüzden her `EAGLContext` nil ([vphone-cli #793](https://github.com/Lakr233/vphone-cli/issues/793); bunu
[#798](https://github.com/Lakr233/vphone-cli/pull/798) 2026-11-02'de kendi Mac misafirleri için kapattı).
Kurucunun `gpu` adımı `scripts\kc-gles.py`'yi çalıştırır: kernelcache'te GPU'nun personality'sine
AppleMetalGLRenderer'ı (Metal üstünde OpenGL ES, misafirin kendi shared cache'inde) ekler. Renderer'ın
shader'ları ayrıca bu deponun 9cadb5c'deki yamasıyla GraphicLoader'ı (misafirin Metal derleyicisinin
çöktüğü AIR metadata'sını tamamlar), reims-vgpu **fd7bd0b5**'i (renderer'ın primitive-restart index'inde
fault veriyordu) ve metal2vulkan **79e1dd02**'yi (dil etiketlerini reddediyordu) ister. Dördüyle
`glestest\`'teki test uygulaması OpenGL ES 1, 2 ve 3 bağlamı alıyor; OpenGL ES 2.0 üçgenleri (vertex
attribute, uniform, varying) bilgisayarın GPU'sunda çiziliyor ve beklenen pikseller okunuyor. Texture,
derinlik ve `discard` henüz denenmedi. Kendi derleyici eklentiniz (`-GpuPlugin DOSYA`) ya da kendi sürücü
paketiniz düz kernelcache'i korur, çünkü başka eklentiler bu shader'larda çöküyor. Bu sürümden önce
kurulmuş bir klasörü güncellemek için önce `Install-iOS26.cmd -Only qemu`, sonra `Install-iOS26.cmd`
çalıştırın: yeni eklenti GPU katmanını ve üstüne kurulanları kendiliğinden yeniden yapar, QEMU'yu yapmaz.

**Henüz yok:** canlı `.ipa` kurma (`.ipa` bir sonraki açılışta doğrudan yerleştirilir), pencereden temiz
kapanış, ses, App Store ve Apple ID hizmetleri. Uygulama değiştirici kartları uygulamanın son ekranı
yerine boş sayfa gösteriyor.

**Başlatıcı:** disk iOS 16 başlatıcısındaki gibi; varsayılan geçici overlay, `-Persist` iOS'un yazdıklarını
ve kurulan `.ipa`'ları kullanıcı overlay'inde tutar (başlat menüsünün varsayılanı), `-Keep` taban görüntüye yazar. `-Net` virtio-net verir (en0, 10.0.2.15); Safari bu bağlantıyla internetteki sayfaları açar (gerçek bir siteyle elle denendi; DNS ve TLS süreleri ölçülmedi).
16K softmmu sayfası varsayılan (`-Page4K` eskisi): kilit ekranı 135 → ~100 sn.

**Gerçekten ekran kartı mı?** Yukarıdaki *Is it really the GPU?* bölümünde Windows'un kendi sayaçlarıyla
ölçüm var: QEMU işlemi RTX 4080'de 1,5-2,2 GB bellek tutuyor, 3D motoru iOS her çizdiğinde %80'e kadar
çıkıyor; diğer GPU (Intel) ne yapılırsa yapılsın %2-12'de düz kalıyor.

**Derleme:** `ios26\Install-iOS26.cmd` yukarıdaki *Build* adımlarını sırayla yürütür: Linux araçları,
QEMU, Apple'ın iki IPSW'sinden yalnız gereken dosyalar (yaklaşık 10,5 GB), disk, üç otomatik açılış
(ilk açılış, duvar kağıdı, istenirse Collections) ve Başlat menüsü kısayolu. Her adım iş klasöründeki
`install\` altında iz bırakır; durdurup yeniden çalıştırınca kaldığı yerden devam eder (`-List`,
`-Check`, `-DryRun`, `-From ADIM`, `-Only ADIM`, `-Collections`, `-QemuFrom`, `-Linux`; ayrıntı yukarıda).
WSL, yönetici yetkisi ve yeniden başlatma gerekmez: Linux isteyen adımlar (Apple'ın APFS imajlarını
okumak, HFS+ diski yazmak) WSL kuruluysa WSL'de, değilse iOS 16 kurucusunun yardımcı VM'inde (zaten
indirilen QEMU'da küçük bir Linux) çalışır; şifre çözme ve im4p işleri Windows'ta ipsw.exe ile
yapılır (`-Linux auto|wsl|helper`, *Without WSL* bölümü). i7-13700HX'te yardımcı VM'le Linux
adımları toplam 49 dk sürdü, 35 dk'sı kök disk (APFS'ten kopya, TCG altında); WSL'de aynı adımlar
13 dk.

**Kolay yol:** depo kökündeki tek kurucu `Install-ASoftware.cmd` ([Kurulum](../README.md#kurulum)):
iOS 26'yı (ya da ikisini) seçin, sonra *Hızlı kurulum (WSL)* ya da *WSL'siz kurulum*. Kurucu
bilgisayarı bir kez denetler; başlamadan önce indirmeyi, en çok ve sonra kalan disk alanını ve
süreyi gösterir. Ardından `Install-iOS26.ps1`'i iOS 16 ile ortak QEMU'yla yürütür, pencere
başlığında adımı ve kalan süreyi gösterir, durunca ya da yeniden başlayınca kaldığı yerden sürer.
Bizim bilgisayarda (40 Mbit/s): WSL'li yol yaklaşık **1 sa 45 dk** (ölçülen 75 dk adım süresi, 52 Mbit/s'de ~30 dk indirme; 11,4 GB indirme, disk en çok 49 GB,
sonra 25 GB; yeni bir WSL dağıtımı 0,9 GB ve ~15 dk daha, dağıtım için ayrıca ~7 GB); WSL'siz yol
tahminen **1 sa 40 dk**, yönetici ve yeniden başlatma gerekmez. Kurucu 2026-11-02'de bu bilgisayarda
boş bir klasör ve yeni bir WSL dağıtımından uçtan uca iOS 26'nın açıldığı bir disk kurdu.
QEMU hazır gelir: kurucu qemu-sptm'nin
[`asoft-7364c4e` sürümündeki](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)
`asoft-qemu-2026.11.03.zip`'i (125 MB; qemu-sptm `asoft` 7364c4e, reims-vgpu `windows` fd7bd0b5,
metal2vulkan `windows` 79e1dd02, `qemu-img.exe` ile) indirir, SHA-256'sını denetler ve `<Work>\qemu`'ya
açar (aynı derleme iOS 16'yı `-M virt` ile açar, iOS 16 kurucusu da bu paketi alır); `-QemuFrom
source` onu MSYS2'de derler (saatler), `-QemuFrom KLASÖR` elinizdeki bir yapıyı alır. Kendi yapmadığı diskleri yeniden kurmaz: elle kurulmuş bir klasörü reddeder. Henüz ikinci bir bilgisayarda
ve WSL'siz uçtan uca denenmedi. Adımlar ve komutlar yukarıdaki *Build* bölümünde (komutlar
dilden bağımsız). Misafirin GPU sürücüsü (`AppleParavirtGPUMetalIOGPUFamily.bundle`) Apple'ın donanım
yazılımı içeriğidir, bu repoda yoktur ve olmayacak. Mac gerekmez: kurucu onu zaten indirdiği cloudOS
26.4b IPSW'sinin OS imajından (`094-39278-029.dmg.aea`) çıkarır. Apple'ın anahtar sunucusu cloudOS
anahtarı vermiyor, ama her cloudOS OS imajı AEA anahtarını kendi başlığında taşıyor; `ipsw fw aea` onu
çevrimdışı çözer, `scripts/cloudos-gpu-driver.sh` paketi alır ve ikilinin CDHash'inin (`113e1e21…`)
IPSW'nin kendi trust cache'inde olduğuna bakar. cloudOS'ta olmayan Metal derleyici eklentisi
(`libAppleParavirtCompilerPluginIOGPUFamily.dylib`; eklentisiz backboardd çöküyor) Apple'ın değil:
vphone-cli'nin GraphicLoader'ı (MIT), bizim `graphicloader.yml` iş akışımız tek bir düzeltmeyle
(`graphicloader/main.mm.patch`: `MTLMetalLibCreateExecutableWithTriple`'a modülün target triple'ı
verilir; yamasız derlemede reims misafirin kütüphanelerini reddeder ve QEMU durur) derliyor, kurucu onu
[graphicloader-57bbc93-p1](https://github.com/alpersamur3/asoft-ios/releases/tag/graphicloader-57bbc93-p1)
sürümünden indirip SHA-256'sını denetler (`-GpuPlugin DOSYA` başka bir derlemeyi alır).
Menüde `[G]` ile kendi paketinizi (klasör) ya da GPU'suz çalışmayı seçebilirsiniz; seçimi değiştirince
kurucuyu yeniden çalıştırın, yalnız GPU katmanını ve duvar kağıdını yeniden yapar.
