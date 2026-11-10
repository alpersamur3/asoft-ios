# visionOS 27.2 on ASoftware (research preview)

visionOS 27.2 (24N120) as an Apple Vision Pro (RealityDevice14,1) on QEMU's `-M vresearch`, its 3D compositor
drawn by your PC's GPU (reims-vgpu and metal2vulkan, Vulkan) into a 1920x1080 window: the headset's view. It is
built on the iOS 26 install of this PC (or only its base): its research kernel, SPTM, TXM, device trees, shell
ramdisk, sysroot, GPU driver and WSL distro. Nothing of Apple's is in this repository: the installer reads the
OS image from Apple's IPSW and the rooms from Apple's Simulator Runtime on your PC.

## Install

Choose **visionOS** in `Install-ASoftware.cmd` (it installs the iOS 26 base it needs), or answer **yes** to
visionOS with iOS 26; with iOS 26 or its base installed already, run `visionos\Install-visionOS.cmd` (it finds the
install through its config):

    visionos\Install-visionOS.cmd [-Work D:\ASoftware\work] [-AudioPlugin <folder>] [-QemuDir <folder>]

It needs:
- an iOS 26 install or base whose Linux steps ran in WSL 2, with a GPU driver (GPU-less iOS 26 is not enough:
  everything in visionOS is drawn through Metal)
- about 17.7 GB from Apple: the OS image is read where it is, in the IPSW (about 10 GB of its 12.35 GB, over
  HTTP, nothing stored but the root it builds), and the visionOS 27.2 Simulator Runtime (7.65 GB, from Apple's
  asset server, no account) for its six synthetic rooms (266 MB kept, the download is deleted)
- about 21 GB free on the install drive (the rooms step needs 8 GB for a while: the runtime's .dmg goes before
  the root is built), and 21 GB stay when it is done
- our QEMU with visionOS's options in `work\qemu`, the one QEMU iOS 16, iOS 26, watchOS and visionOS run on:
  usb-touchscreen's walk mode with a held key and `-cpu x-tlbi-filter`. An install whose QEMU lacks them gets it
  from `-QemuDir <folder>` (a package folder, win-build.sh's dist) or the release package `installer\asoft-setup.json`
  names; a folder without them is refused before anything is copied. Replacing it needs every guest closed
- for sound, the virtio-snd HAL plug-in (VPhoneVirtIOSound, from vphone-cli, MIT, built for xrOS on macOS CI):
  not published yet, so `-AudioPlugin <folder>` (`VPhoneVirtIOSound.driver`, or the CI artifact's folder); its
  three files are checked against pinned SHA-256s and its CDHash. Without it visionOS is installed silent only;
  given (or published) after that install is finished, a new run adds the sound disk and leaves the silent one as
  it is

About 2 h 10 min on our PC (i7-13700HX, ~7 MB/s from Apple's CDN): rootfs 75 min and rooms 22 min of it, the
two boots about 18. Like the other installers it leaves a marker per step (`work\install\vision-*.done`) and
goes on where it stopped; `-List` shows the steps (time, download, done), `-DryRun` the commands, `-From STEP` /
`-Only STEP` redo steps. `-CdnEdge 17.253.x.x` sends the runtime's download to one of Apple's CDN edges where
your DNS's is slow.

| Step | What it does |
|---|---|
| check | the base (its files, WSL distro, GPU driver, plain kernel) and visionOS's apt packages in WSL (fusepy, cryptography, liblzfse, venv); copies `ios26\scripts`, two of `watchos\scripts` and `visionos\scripts` into `work\visionos\scripts`, where the steps run them |
| qemu | checks `work\qemu` for visionOS's options; replaces it when they are missing |
| rooms | asks Apple's asset server for the runtime (TLS checked against Apple Root CA, the answer pinned by size and path), streams its .dmg onto the work drive (a download that stopped goes on where it stopped: the finished parts, noted with their SHA-256 in `rt.dmg.parts`, are checked and kept), copies the six rooms (checked by `rooms.sha256`) and strips their acoustic prims (`usdacoustic.py`, usd-core 26.11) |
| ipsw | the IPSW's trust cache and N301AP device tree; the OS image's AEA key from Apple's key service and the index of its 67 clusters (pinned) |
| firmware | `kc-vision.py`: iOS 26's plain kernel + 13 checked patches (iOS 27's, IOGPU timeouts, sandbox syscall filters off), SHA-256 pinned; `dt-vision.py`: the Vision Pro's identity on the 4, 6 and 8 CPU trees |
| gpu | the GPU driver (`work\gpu-driver`), retargeted to visionOS, signed, into `visionos\gpu` (kept) |
| rootfs | `mk-rootx.sh`: the partitioned HFS+ root (`rootv.qcow2`, 17.4 GB) copied out of the OS image mounted over HTTP |
| audio | the audio plug-in, when there is one, checked, into `visionos\audio`; given later to an unfinished install, it redoes the disk steps from here, to a finished one only the disks step's sound disk is added (below) |
| patches | `rootx-patch.sh` on a new overlay, `rootv-p.qcow2`: launchd jobs and launchd's sandbox check, keybag, IOMobileFramebuffer and libxpc shared-cache patches, the staged apps built in, RealityLauncher's long press, prefs, feature flags, churn cuts, the rooms, the GPU driver, the audio plug-in, the keyboard camera |
| trustcache | `rootv.tc`: Apple's trust cache + the signed sysroot, patched binaries, GPU driver and audio plug-in (3,266 entries) |
| firstboot | boots once on `rootv-b.qcow2` until usermanagerd has written the persona manifest (about 6 min) |
| persona | the persona manifest, MobileGestalt, activation record, keyboard intro, environments' first-use gates, the audio ProductID |
| homeboot | boots again until Home is up (4-6 min), then 2 min more |
| disks | the Accessibility Shortcut off; `rootv-s.qcow2` (silent: VirtualAudio off, churn3) and, with the plug-in, `rootv-a.qcow2` (sound); on them the disks you use, `vision-silent.qcow2` and `vision.qcow2`. A plug-in that came after a finished silent install makes only `rootv-a.qcow2` (with the plug-in on it) and `vision.qcow2`, and `rootv.tc` gains its CDHash: `vision-silent.qcow2`, the layers under it and its saves stay as they are |
| cleanup, shortcut | removes the build's leftovers; Start menu "ASoftware visionOS" |

Redoing a disk step after a finished install (`-From`/`-Only`) keeps your disks as `visionos\vision.qcow2.old` and
`vision-silent.qcow2.old` (what visionOS wrote, on the old layers) and starts new ones; an `.old` an earlier redo
kept stays, and the next one is `.old2`, `.old3`, ...

## Use

`Start-visionOS.cmd` (or the Start menu shortcut):

    Start-visionOS.cmd [-Cpus 4|6|8] [-Sound] [-NoNet] [-NoFrame] [-Snapshot] [-NoQuickBoot] [-NoAutoSave]
                       [-LoadState NAME] [-MaxFps N]

- 8 vCPUs by default (each count has its own device tree); 4 GiB of guest RAM (the tree's)
- silent by default: sound (`-Sound`, the sound disk, a virtio-snd speaker on Windows' default output) costs
  about one vCPU
- one visionOS at a time (ports 4481-4483); iOS 26 and watchOS can run beside it
- quick boot, as iOS 26 and watchOS have it: closing the window saves the machine into the disk (about 4 GB),
  and the next start goes on from there in about 15 seconds instead of booting (about 5 minutes to Home). The
  save is resumed once and then stays as a way back (`-LoadState asoft-quick`); `-NoQuickBoot` boots every
  time. A save loads only with the `-Cpus` it was made with; the sound disk and the silent disk have each
  their own. After a cold start on a disk with no save yet, visionOS is also saved by itself once Home has
  been up for some minutes and you are not using it (`-NoAutoSave` turns that off). A resumed visionOS has
  the windows it was saved with and the time of your PC: the clock is set on its root shell (the serial
  console), a moment after it goes on
- visionOS draws 60 frames a second whether anything moves or not; `-MaxFps 30` halves that and takes about a
  tenth off the PC's load at rest (2.65 → 2.37 cores here)
- the window is a drawn Apple Vision Pro with the screen in its glass; F9 (or `-NoFrame`, or the side bar's
  Headset row) leaves the screen alone, as large as the window lets it be, and F11 is full screen

Controls:

| Input | In visionOS |
|---|---|
| mouse | where you look (hover), click = pinch |
| right button held | look around; with it W A S D walk, R F up and down, Shift + W A S D turn |
| middle button | walk mode on and off |
| F1, or a click on the drawn crown | Digital Crown (hold: recentre); the wheel over the crown is the volume |
| F2, or a click on the drawn top button | top button |
| F3 / F4 | volume down / up |
| F9 | the drawn headset on and off |
| F11 | full screen |
| F12 | shows the keys pressed |

Typing goes to the text field that has the focus; the head keys (W A S D, Q E, R F, Shift) move the head only in
walk mode (the right button held, or walk mode on), so a text with those letters in it does not walk you away.

Works: Home with its apps and the environments' places (the six synthetic rooms, White Sands, Morning Light),
Settings (About says 27.2), Safari with web pages, the keyboard, sound on the sound disk, the network. It runs
under TCG on your CPU, so it is slow: Home comes up about 5 minutes after the start, and the first taps after
it may need a second try.
