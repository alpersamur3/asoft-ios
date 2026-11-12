# tvOS 27.2 on ASoftware (research preview)

tvOS 27.2 (24K122) as an Apple TV 4K (3rd generation, AppleTV14,1, J255) on QEMU's `-M vresearch`, drawn by your
PC's GPU (reims-vgpu and metal2vulkan, Vulkan) into a 3840x2160 picture. It is built on the iOS 26 install of this
PC (or only its base): its research kernel, SPTM, TXM, device trees, shell ramdisk, sysroot, GPU driver and WSL
distro. Nothing of Apple's is in this repository: the installer downloads Apple's own OTA update for the Apple TV
4K and builds the root disk out of it on your PC.

## Install

Choose **tvOS** in `Install-ASoftware.cmd` (it installs the iOS 26 base it needs), or answer **yes** to tvOS with
iOS 26; with iOS 26 or its base installed already, run `tvos\Install-tvOS.cmd` (it finds the install through its
config):

    tvos\Install-tvOS.cmd [-Work D:\ASoftware\work] [-QemuDir <folder>] [-OtaFile <file>] [-CdnEdge 17.253.x.x]

It needs:
- an iOS 26 install or base whose Linux steps ran in WSL 2, with a GPU driver (GPU-less iOS 26 is not enough:
  tvOS draws through Metal)
- 4.97 GB from Apple: the full OTA of tvOS 27.2 for AppleTV14,1 (Apple publishes no tvOS IPSW for the Apple TV
  4K). It is pinned by URL, size, SHA-256 and AEA key; `-OtaFile <file>` reads a copy you have instead (checked
  the same way, never removed). The key is the one Apple's update server (Pallas) gives for this asset, whose
  listing there expires on 2027-02-06; the file on Apple's CDN stays as long as Apple keeps it
- liblzraven, fetched from GitHub at one pinned commit and built in WSL (see Credits): OS 27's OTA payloads are
  LZRAVEN-compressed, which `ipsw` cannot decode off macOS 27
- about 23 GB free on the install drive at the peak (the OTA, its decrypted archive and the unpacked root's image
  meet there for a while), about 12.5 GB when it is done; the work drive must be NTFS (the unpacked root's image
  is a sparse file)
- our QEMU in `work\qemu`, the one QEMU iOS 16, iOS 26, watchOS, visionOS and tvOS run on, as visionOS has it
  (usb-touchscreen's walk mode with a held key and `-cpu x-tlbi-filter`). An install whose QEMU is older gets it
  from `-QemuDir <folder>` (a package folder, win-build.sh's dist) or the release package `installer\asoft-setup.json`
  names; a folder without them is refused before anything is copied. Replacing it needs every guest closed

About 1 h 40 min on our PC (i7-13700HX, ~7 MB/s from Apple's CDN), an estimate from the hand build's steps: the
unpack and its signature check about 40 min, the root disk 20, the download about 12. Like the other installers
it leaves a marker per step (`work\install\tv-*.done`) and goes on where it stopped; `-List` shows the steps
(time, download, done), `-Estimate` the time, download and disk space of what is left, `-DryRun` the commands,
`-From STEP` / `-Only STEP` redo steps. `-KeepBuildFiles` keeps the OTA, its decrypted archive and the unpacked
root's image.

| Step | What it does |
|---|---|
| check | the base (its files, WSL distro, GPU driver, plain kernel) and the WSL packages tvOS needs (git, a C compiler, make, e2fsprogs); copies `ios26\scripts`, two of `watchos\scripts`, visionOS's `kc-vision.py` and `tvos\scripts` into `work\tvos\scripts`, where the steps run them |
| qemu | checks `work\qemu` for visionOS's options; replaces it when they are missing |
| lzraven | fetches liblzraven at its pinned commit (the checkout is checked to be that commit, clean), builds it, runs its test suite, and links `pbzm_dec` (`tvos\scripts\pbzm_dec.c`) against it, in WSL's Linux scratch |
| download | the OTA (`tvos\ota`), in 32 MiB pieces over 8 connections; a download that stopped goes on with the pieces it has; the whole file is checked by its SHA-256 |
| decrypt | `ipsw fw aea` with the pinned key into one Apple Archive (4.99 GB, checked by size and magic), indexed (`index_outer.py`), and its boot files taken out: the OS trust cache (1,623 entries), J255's device tree, the build manifest (24K122, AppleTV14,1). The downloaded OTA is removed then |
| unpack | the root out of the payload (`tvx.py` with `pbzm_dec`) into a sparse ext4 image (`tvos\build\root.ext4`, 20 GiB at most, 13 GB used); checked: every path of Apple's fixup manifest there, 24K122, and `vsig.py`: every code page of every Mach-O and shared-cache file against its signature, and their CDHashes against the OS trust cache (8 kexts, whose code is in the kernel cache, may be outside it). The decrypted archive is removed then |
| firmware | the kernel: visionOS's (`kc-vision.py`, the cloudOS 26.4b research kernel with iOS 27's patches, the IOGPU timeouts and the sandbox syscall filters off; SHA-256 pinned); `dt-tv.py`: J255's identity on the 4, 6 and 8 CPU trees (`dtree-t`, `-t6`, `-t8`) |
| gpu | the GPU driver (`work\gpu-driver`), retargeted to tvOS, signed, into `tvos\gpu` (kept) |
| rootfs | `mk-roott.sh`: the partitioned HFS+ root (`roott.qcow2`, root 16 GB and Data 8 GB) copied from the unpacked root; the image is removed then |
| patches | `roott-patch.sh` on a new overlay, `roott-p.qcow2`: launchd jobs, keybag, the shared-cache patches (IOMobileFramebuffer, libxpc), the GPU driver, prefs (screen saver and idle screen off) |
| trustcache | `roott.tc`: Apple's trust cache + the signed sysroot, the patched shared-cache files and the GPU driver |
| firstboot | boots once on `roott-b.qcow2` until usermanagerd has written the persona manifest and mobileactivationd its container |
| persona | the persona manifest, MobileGestalt, the activation record, tvOS's prefs |
| homeboot | boots again until Home is up (about 1.5 min on our PC), then 2 min more |
| disks | `tv.qcow2`, the disk you use, on `roott-b.qcow2` |
| cleanup, shortcut | removes the build's leftovers; Start menu "ASoftware tvOS" |

Redoing a disk step after a finished install (`-From`/`-Only` rootfs ... disks) keeps your disk as
`tvos\tv.qcow2.old` (what tvOS wrote, on the old layers) and starts a new one; an `.old` an earlier redo kept
stays, and the next one is `.old2`, `.old3`, ... A redo after the cleanup downloads and unpacks the OTA again.

## Use

`Start-tvOS.cmd` (or the Start menu shortcut):

    Start-tvOS.cmd [-Cpus 4|6|8] [-NoNet] [-NoFrame] [-Snapshot] [-NoQuickBoot] [-NoAutoSave]
                   [-LoadState NAME] [-MaxFps N] [-RamMiB N] [-PrintOnly]

- 4 vCPUs by default (each count has its own device tree; 6 and 8 are not measured on tvOS); 4 GiB of guest RAM
  (the tree's)
- 3840x2160 (`-Resolution 2160`, the default). `-Resolution 1080` is not wired in yet: a start in it says which
  files it lacks and stops
- one tvOS at a time (ports 4501-4503); iOS 26, watchOS and visionOS can run beside it
- quick boot, as the other guests have it: closing the window saves the machine into the disk (about the
  guest's RAM, 4 GB), and the next start goes on from there in seconds instead of booting. The save is resumed
  once and then stays as a way back (`-LoadState asoft-quick`); `-NoQuickBoot` boots every time. A save loads
  only with the `-Cpus` and RAM it was made with. After a cold start on a disk with no save yet, tvOS is also
  saved by itself once Home has been up a while and you are not using it (`-NoAutoSave` turns that off)
- the window is a TV with a Siri Remote beside it, whose parts you can click, when the QEMU has the TV window
  (usb-consumer `tv-remote`, our build from branch asoft-tv, not published yet; the start looks for it and
  otherwise opens the plain window). F9 (or `-NoFrame`) leaves the picture alone
- `-PrintOnly` prints the QEMU command line the start would run, and starts nothing

Controls:

| Input | In tvOS |
|---|---|
| arrow keys | move the focus (on a new screen the first one only puts the focus on the first item) |
| Return | select |
| Esc | back (Menu) |
| F1 | the TV button (held: Control Center) |
| F2 | power |
| F3 / F4 | volume down / up |
| F5 / F6 / F7 | Play/Pause, Mute, Siri (the TV window's remote only) |
| F9 | the drawn TV and remote on and off (the TV window only) |
| F11 | full screen |

A key takes 2-8 seconds (up to 19 when a row changes) to show on the screen: wait for it before the next one.

Works: Home with its apps, Settings (About says 27.2, 2160p), the network. Not yet: activation (About says
Activation: Failed), so the apps that need Apple's services (Search, Apple TV) say they are not available right
now. It runs under TCG on your CPU: Home comes up about 1.5 minutes after the start. QEMU takes about 5 GB of
memory at 4 GiB of guest RAM: leave about 11 GB of Windows' commit free before you start it.

## Credits

- [liblzraven](https://github.com/anat0m1a/liblzraven) (0BSD), a clean-room LZRAVEN decoder: the installer
  fetches it at commit 700b88c4b2e1b1d96e499d172dfa0b8e5d9134ab and builds it on your PC; it is not shipped here
- [ipsw](https://github.com/blacktop/ipsw) (MIT) decrypts the OTA and takes its boot files out, as for the other
  guests
