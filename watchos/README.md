# watchOS 27.2 on ASoftware (research preview)

watchOS 27.2 (24S118) as an Apple Watch Series 9 (Watch7,1, 41 mm) on QEMU's `-M vresearch`, drawn
by your PC's GPU (reims-vgpu and metal2vulkan, Vulkan), in a drawn watch case that hangs from the
window and swings when you drag it. It does not need iOS 26, only the base it shares with it: cloudOS
26.4b's research kernel, SPTM, TXM and device tree, the shell ramdisk, darwin-vm's sysroot, the GPU
driver and the WSL distro (about 1 GB from Apple, no iPhone files). An iOS 26 install has that base
already. Nothing of Apple's is in this repository: the installers download it from Apple.

## Install

Choose **watchOS 27.2 only** in `Install-ASoftware.cmd` (`-Version watchos`; `ios16-watchos` adds iOS
16), or **iOS 26** and answer **yes** to watchOS. With iOS 26 (or the base) installed already, it goes
into the same folder and downloads only the watch's files. By hand:

    watchos\Install-watchOS.cmd [-Work D:\ASoftware\work]

finds the work folder through iOS 26's config; a work folder without the base gets it first (its check
step runs `ios26\Install-iOS26.ps1 -Base`).

It needs:
- WSL 2 (its Linux steps run there) and a GPU driver: the base takes Apple's out of cloudOS unless iOS
  26's settings chose another; a GPU-less iOS 26 is not enough, the watch face needs Metal
- 5.0 GB from Apple (the IPSW's OS image, its trust cache and the watch's device tree), plus about 1 GB
  for the base when it is not there yet, and about 21 GB free on the install drive while it builds,
  14 GB when it is done (16 GB with the base)
- our QEMU build with the watch's machine options (`qemu-watch\`): a copy of the work folder's `qemu\`
  or of the package's `qemu\bin`, from the 0.3.0 package on. For an older install or a checkout give one with `-QemuFrom <folder>`
  (`Install-ASoftware.cmd -WatchQemu <folder>`); a folder without the watch's devices is refused before
  anything is copied

Like the iOS 26 installer it leaves a marker per step (`work\install\watch-*.done`) and goes on where it
stopped; `-List` shows the steps, `-DryRun` the commands, `-From STEP` / `-Only STEP` redo steps.
`-WatchIpsw FILE` reads Apple's files from an IPSW you have, `-WatchDir DIR` takes them as single files
(several folders: `"D:\a|E:\b"`).

| Step | What it does |
|---|---|
| check | the base it shares with iOS 26 (its files, WSL distro, GPU driver, plain kernel), made first when it is not there; copies this version's `ios26\scripts` and `watchos\scripts` into `work\watchos\scripts`, where the steps run them |
| qemu | the watch QEMU into `qemu-watch\` |
| download | `141-08453-168.dmg.aea` (5.03 GB), its `.trustcache`, `DeviceTree.n207sap.im4p` |
| decrypt | the OS image (key from Apple's key service, as for iOS 26); the `.aea` goes |
| firmware | `kc-watch.py`: the base's plain kernel (`cloud\kernelcache.research.vphone600.decompressed`; an iOS 26 install's `fw\bootkc` has OpenGL ES's keys) + eight checked patches; `dt-watch.py`: the Series 9's identity on `dtree-smp4` and `dtree-smp8` |
| gpu | the GPU driver (`work\gpu-driver`, which the base's gpudriver step leaves there; an older iOS 26 install's off its disk), retargeted to watchOS, signed, into `watchos\gpu` (kept) |
| rootfs | `mk-rootw.sh`: the partitioned HFS+ root (`rootw.qcow2`); the image goes (redone later, it gets the image again) |
| patches | `rootw-patch.sh` on a new overlay, `rootw-p.qcow2`: launchd jobs, keybag, three shared-cache patches, prefs, Setup skipped, the display kept on, the staged apps built in; the GPU driver |
| trustcache | `rootw.tc`: Apple's trust cache + the signed sysroot, patched subcache and driver |
| firstboot | boots once on `watch.qcow2`, an overlay on `rootw-p.qcow2`, which is the disk you use, until mobileactivationd has made its data ark and the watch face is up: DataMigration and the face's first start hold the Apple logo for 14 min here, after which a start takes 6 |
| activation | seeds the activation record into that container (the step fails if there is none) |
| cleanup, shortcut | removes the build's leftovers; Start menu "ASoftware watchOS" |

Redoing a disk step (`-From`/`-Only` rootfs, patches or firstboot) after a finished install keeps the
watch's disk as `watchos\watch.qcow2.old` (what the watch wrote, on the old layers) and starts a new one;
until the redo is through, `Start-watchOS.cmd` says the install is not finished.

## Use

`Start-watchOS.cmd` (or the Start menu shortcut). The mouse is the touchscreen; the wheel over the watch
or a drag on the drawn Digital Crown turns it, a click presses it (hold for Siri); the side button opens
Control Center. iOS 26 can run beside it (the watch uses ports 4471-4473). `-Snapshot` keeps a session's
writes out of `watch.qcow2`; `-Smp 8` gives it eight CPUs (here the face came no sooner: 7 min, 6 with four).

Quick boot, as with iOS 26: closing the window saves the watch (memory and devices) into `watch.qcow2`, and
the next start goes on from there in seconds instead of booting again. The first minutes after a cold
start are slow, so a disk with no save yet is also saved once by itself about 15 minutes after the start (the
face shown for 5 minutes, and you not using it: its window not in front, or 2 minutes without input); a start
after a crash or a power cut then goes on from that save. A disk that has a save already keeps it: the automatic
save does not run. What it did: `watchos\runs\<run>\autosave.log`. A saved
state takes about 4 GB on the drive; with less than 5 GB free quick boot is off for that start. Saving takes
about 7 seconds, resuming about 20.
A save is resumed once; then it stays as a way back until closing the window saves again: a start after
*Turn off* boots the watch from its disk as it was left, and `-LoadState asoft-quick` (ASoftware.exe: *Go
back*) goes back to the save, undoing what was done since. `watchos\watch.qcow2.quick-used` names the save
that is the way back. `-NoQuickBoot` boots every time (a save stays as the way back); `-NoAutoSave` keeps
only the save at closing.

Works: the watch faces and their gallery, the app grid, Settings, Notification Center, Stopwatch, World
Clock, Calendar, Maps, Compass, touch, the crown, the side button, the network. Not yet: pairing with an
iPhone (watchOS's Setup is skipped), the App Store, Weather data, Control Center's controls (it opens
empty). It runs under TCG on your CPU, so it is slow: the face comes up about 6 minutes after the start.
