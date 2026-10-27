<div align="center">

# ASoftware iOS 26 (research preview)

**iOS 26 in a window on a Windows PC, its interface drawn by the PC's own GPU.**

<img src="screenshots/lock-screen.png" width="30%" alt="Lock screen"> <img src="screenshots/home-screen.png" width="30%" alt="Home screen"> <img src="screenshots/settings.png" width="30%" alt="Settings">

English · [Türkçe](#turkce)

</div>

Apple's iOS 26.6.2 userland boots on QEMU on an ordinary x86-64 Windows PC, on the kernel of
Apple's own research VM platform (vphone600, from cloudOS 26.4b). iOS's Metal driver in the guest
sends its work to a paravirtual GPU, and on the PC that work runs on the host GPU through Vulkan:
the lock screen, SpringBoard, Settings and the system apps draw on an NVIDIA RTX 4080 under
Windows. [vphone-linux](https://github.com/YahiaAngelo/vphone-linux) runs the same guest on the
same GPU stack on Linux; this is the Windows host.

> [!WARNING]
> A research preview, not a product: there is no installer, and building the inputs takes the
> steps below, WSL and several hours. Apple's security model is mostly switched off. Not
> affiliated with Apple. No Apple software is in this repository or in our forks: you build
> everything from your own downloads from Apple, and the guest's GPU driver you extract yourself.

## What works

| | |
| --- | --- |
| **GPU** | iOS's own Metal draws the interface; the PC's GPU runs it through Vulkan (tested: NVIDIA RTX 4080 Laptop, Windows 11) |
| **iOS** | Lock screen, home screen with the system apps, Settings and its pages, Weather |
| **Input** | Mouse as the touchscreen (tap, swipe, scroll), the PC keyboard, Home, side button and volume |
| **Window** | The ASoftware window and side bar of the iOS 16 build: Home, Lock, App switcher, volume, screenshots, full screen, pasted text |
| **Speed** | All CPU work is emulated (QEMU TCG). Measured on an i7-13700HX: lock screen about 100 s after start, Settings opens in about 4 s, a scroll answers in 0.3 s |

Not yet: the wallpaper (black), quick boot and saved states (the GPU device blocks migration for
now), `.ipa` installs, audio, the App Store and Apple ID services. For about 3 minutes after the
lock screen appears iOS's daemons keep every vCPU busy, so the first taps are slow.

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
| QEMU | [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/ios26), branch `ios26` | The `vresearch` machine (boot, device tree, SMP, PVG display and GPU, SEP/keystore/ACM stand-ins, HFS+ data protection), a USB touchscreen and consumer keys, the Windows build, the ASoftware GTK window |
| GPU, host side | [alpersamur3/reims-vgpu](https://github.com/alpersamur3/reims-vgpu/tree/windows), branch `windows` | A Windows OS layer: guest RAM as section views (`MapViewOfFile3` placeholders), IOSurface backing, read-only imports through a writable twin, the x86-64 build serving 16 KiB guest pages |
| Metal → Vulkan | [alpersamur3/metal2vulkan](https://github.com/alpersamur3/metal2vulkan/tree/windows), branch `windows` | The `x86_64-pc-windows-gnu` build |
| This folder | `ios26/` | The launcher and the scripts that build the disk, device tree, trust cache and ramdisk |

## Build

> [!IMPORTANT]
> Written down from the runs that built our disk. Not yet repeated end to end on a second PC, and
> the steps marked *by hand* have no script yet. Read each script before you run it.

### You need

- Windows 10/11 x64, 8 or more cores, 16 GB RAM (the guest gets 4 GB), about 60 GB free
- A Vulkan GPU whose driver has `VK_EXT_external_memory_host` (tested: NVIDIA RTX 4080 Laptop)
- MSYS2 with the UCRT64 toolchain: QEMU's build dependencies (as for [`qemu/build-windows.sh`](../qemu/build-windows.sh)),
  plus GTK 3, ANGLE (`mingw-w64-ucrt-x86_64-angleproject`) and Rust (`mingw-w64-ucrt-x86_64-rust`)
- WSL 2 (Ubuntu), as root: [ipsw](https://github.com/blacktop/ipsw), `qemu-utils`, `hfsprogs`, `gdisk`,
  [apfs-fuse](https://github.com/sgan81/apfs-fuse), `python3`, `rsync`, and an `hfsplus` kernel module
  for WSL's kernel, which has none (`HFSPLUS_KO=path/to/hfsplus.ko`)
- `sysroot/ios_sysroot.tar.gz` from [jprx/darwin-vm](https://github.com/jprx/darwin-vm): bash and
  coreutils for the shell ramdisk and the root

Two folders, set as environment variables:
- `ASOFT26_SRC`: sources and builds, an MSYS path such as `/c/asoft26-src`.
- `ASOFT26`: Apple's files, the disks and the runs. WSL sees it as, say, `/mnt/d/ios26`, and it is
  `-Work D:\ios26` for `Start-iOS26.ps1`.

`ASOFT26_LINUX` (default `/root/ios26`) is scratch space inside WSL.

### 1. QEMU and the GPU library (MSYS2 UCRT64, started from PowerShell)

```
git clone -b ios26 https://github.com/alpersamur3/qemu-sptm %ASOFT26_SRC%\qemu-sptm
git clone -b windows https://github.com/alpersamur3/reims-vgpu %ASOFT26_SRC%\reims-vgpu
git clone -b windows https://github.com/alpersamur3/metal2vulkan %ASOFT26_SRC%\metal2vulkan-win
```

1. `win-nettle.sh`: a static nettle 3.10.1 (put GNU's `nettle-3.10.1.tar.gz` in `deps\dl` first).
2. `ucrt.ps1 ios26\scripts\reims-build.sh`: reims-vgpu → `reims-dist`.
3. `win-build.sh`: QEMU → `dist`. Copy it to `<ASOFT26>\qemu`.

### 2. Apple's files (WSL)

- **cloudOS 26.4b (23E5207q)**, the IPSW of Apple's Private Cloud Compute research VM (vphone600):
  extract it into `$ASOFT26/cloudos`. Used, none of them encrypted:
  - `kernelcache.research.vphone600`
  - `Firmware/sptm.vresearch1.release.im4p`, `Firmware/txm.iphoneos.research.im4p`
  - `all_flash/DeviceTree.vphone600ap.im4p`
  - the ramdisk `094-39914-031.dmg` and its trust cache
- **iPhone17,3 iOS 26.6.2 (23G90)**: `ipsw-get.py URL MEMBER OUT` fetches single members of the IPSW
  into `$ASOFT26/iphone`:
  - `094-97246-090.dmg.aea` (the OS)
  - `094-95368-092.dmg.aea` (the SystemOS cryptex)
  - `094-96441-094.dmg` (AppOS)
  - `Firmware/*.trustcache`
- `sysos.sh` and `m2-decrypt.sh` decrypt the two AEA images into `$ASOFT26/os`. `ipsw fw aea` gets
  the keys from Apple's key service.

### 3. Firmware, device tree and ramdisk (WSL)

1. *By hand*, in `$ASOFT26`: `ipsw img4 im4p extract cloudos/all_flash/DeviceTree.vphone600ap.im4p -o cloud/vphone600ap.adt`
2. `kdec.sh`, then `unwrap-fw.sh` → `fw/bootkc`, `fw/sptm`, `fw/txm`, `fw/dtree.orig`
3. `QEMU_SPTM=<qemu-sptm checkout> python3 dt-root26smp.py fw/dtree.orig dtree-smp4 --cpus 4`
   (`dtree-smp8 --cpus 8` too, if you like: we have not booted 8 yet)
4. `SYSROOT_TAR=<darwin-vm>/sysroot/ios_sysroot.tar.gz sysroot-check.sh`
5. *By hand:* unwrap the cloudOS ramdisk to `$ASOFT26_LINUX/rd/rd.apfs` and put its trust cache at
   `cloud/rd.trustcache.im4p`. Then run `mk-ramdisk.sh` and copy `rd-shell.hfs` to `$ASOFT26`. The
   machine wants a ramdisk even though iOS's root is on the disk.

### 4. The root disk (WSL, as root)

1. `DROP_SYSOS=1 mk-root26.sh` → `root26.qcow2` and `root26.qcow2.hashes`. If its sysroot step
   stops on `cp -a`'s ACLs, `m2-finish.sh` completes it and applies `root26-tweaks.py`.
2. `mktc.py -2 root.tc iphone/*.trustcache root26.qcow2.hashes`: the trust cache.
3. `mk-root26g.sh root26.qcow2 root26g.qcow2`: the partitioned disk (system and a 16 GB Data volume).
4. Through `root26-do.sh root26g.qcow2 'python3 SCRIPT $R ...'`, in this order:
   1. `root26-prefs.py`, `root26-sb-undiag.py`, `root26-bbd-fix.py`
   2. *by hand:* `/private/var/keybags/systembag.kb`, a plist with `KeyBagKeys` = the data `SWEET`
      (owner root, mode 0600)
   3. `root26-churn.py on`, `root26-dbg-off.py`
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
2. **GPU driver** (optional, see below): put `AppleParavirtGPUMetalIOGPUFamily.bundle` into
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

Then run `Start-iOS26.ps1 -Work D:\ios26`. The lock screen comes after about 100 s; press Home (F1).

### The guest's GPU driver

`AppleParavirtGPUMetalIOGPUFamily.bundle` is Apple firmware content. It is not in this repository
and never will be: vphone-cli stopped shipping it for the same reason. Extract your own:

- **On an Apple silicon Mac:** [vphone-cli](https://github.com/Lakr233/vphone-cli)'s `fw prepare` copies it
  from the cloudOS image. Its compiler plugin is built with
  [GraphicLoader](https://github.com/Lakr233/vphone-cli/blob/main/VPhoneGuestComponents/GraphicLoader/README.md).
- **Without a Mac:** vphone-linux's
  [CREATE-ON-LINUX.md](https://github.com/YahiaAngelo/vphone-linux/blob/main/docs/CREATE-ON-LINUX.md)
  gets it from a stock cloudOS restore under QEMU on Linux. We have not tried that route.

## Tools

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
  Assistant, activation, the guest GPU driver).
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
> Bir araştırma önizlemesi, ürün değil: kurulum programı yok. Girdileri üretmek yukarıdaki
> adımları, WSL'i ve birkaç saati gerektiriyor. Apple'ın güvenlik modeli büyük ölçüde kapalı. Apple
> ile bir bağı yoktur. Bu repoda ve fork'larımızda Apple yazılımı yoktur: her şeyi Apple'dan kendi
> indirdiklerinizden üretirsiniz, misafirin GPU sürücüsünü de kendiniz çıkarırsınız.

**Çalışanlar:**
- **GPU:** iOS'un kendi Metal'i arayüzü çiziyor, Vulkan üzerinden ekran kartı çalıştırıyor.
- **iOS:** kilit ekranı, sistem uygulamalarıyla ana ekran, Ayarlar ve sayfaları, Hava Durumu.
- **Giriş:** fare dokunmatik ekran gibi çalışıyor (dokunma, kaydırma), PC klavyesi, Home, yan tuş ve
  ses tuşları.
- **Pencere:** iOS 16 sürümündeki ASoftware penceresi ve yan çubuğu.
- **Hız:** i7-13700HX'te kilit ekranı açılıştan yaklaşık 100 sn sonra geliyor, Ayarlar yaklaşık 4 sn'de
  açılıyor, kaydırma 0,3 sn'de tepki veriyor.

**Henüz yok:** duvar kağıdı (siyah), hızlı açılış ve kayıtlı durumlar, `.ipa` kurma, ses, App Store ve
Apple ID hizmetleri.

**Derleme:** adımlar ve komutlar yukarıdaki *Build* bölümünde (komutlar dilden bağımsız). Misafirin GPU
sürücüsü (`AppleParavirtGPUMetalIOGPUFamily.bundle`) Apple'ın donanım yazılımı içeriğidir, bu repoda
yoktur ve olmayacak. Kendiniz çıkarın: Apple silicon Mac'te vphone-cli'nin `fw prepare` komutuyla, ya da
Mac olmadan vphone-linux'un anlattığı yolla.
