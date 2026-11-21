<p align="center">
  <img src="assets/banner.png" alt="ASoftware iOS for Windows: visionOS, iOS 26 and watchOS in their windows on Windows 11" width="100%">
</p>

<p align="center">
  <a href="https://github.com/alpersamur3/asoft-ios/releases/latest"><b>Download</b></a>
  &nbsp;·&nbsp; <a href="#will-it-run-on-my-pc">Will it run on my PC?</a>
  &nbsp;·&nbsp; <a href="#if-something-goes-wrong">If something goes wrong</a>
  &nbsp;·&nbsp; <a href="https://github.com/alpersamur3/asoft-ios-android">Android version</a>
  &nbsp;·&nbsp; <a href="#turkce">Türkçe</a>
</p>

Real iOS in a window on your Windows PC. iOS 16 is drawn by the CPU and runs on most PCs; iOS 26,
watchOS, visionOS and tvOS are drawn by your PC's GPU through Vulkan. The installer downloads iOS from
Apple's own servers and builds it on your PC: this repository and the release contain no Apple files.

It is a research preview: it is slower than a real iPhone, an install takes one to three hours, and some
PCs hit problems we have not solved yet (listed below). Not affiliated with Apple.

## Will it run on my PC?

| | What the PC needs | Free space while it installs | Space it keeps |
|---|---|---|---|
| **iOS 16** | Windows 10 1903 or newer, or Windows 11, 64-bit; 16 GB RAM, 4 cores. No GPU, WSL or administrator needed | about 27 GB | about 14 GB |
| **iOS 26** | Windows 10 2004 or newer, or Windows 11; a GPU whose Vulkan driver has version 1.2, `VK_EXT_external_memory_host` and is under two years old; 16 GB RAM and 8 logical processors recommended | about 50 GB | about 25 GB |
| **watchOS** | the same GPU, and WSL 2 | about 23 GB | about 16 GB |
| **visionOS** | the same GPU, and WSL 2 | about 22 GB | about 22 GB |
| **tvOS** | the same GPU, and WSL 2 | about 25 GB | about 14 GB |

- The installer checks all of this before anything is downloaded, and shows the download, the space and
  the time for your PC.
- The GPU path is tested on NVIDIA. AMD and Intel: see [If something goes wrong](#if-something-goes-wrong).
- A new WSL install takes about 7 GB more on the drive WSL keeps its files on.

## Install

1. In PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
   ```

   It downloads the newest release, checks it against `SHA256SUMS.txt` and starts the installer. Or
   download `ASoftware-iOS-<version>-win64.zip` from [Releases](https://github.com/alpersamur3/asoft-ios/releases/latest),
   unpack it and run `Install-ASoftware.cmd`.
2. Pick the system. For iOS 26 it also asks *Fast install (WSL)* or *Install without WSL*.
3. Leave the PC on. Stopped, or restarted for WSL? Run it again: it goes on where it stopped.
4. When it is done, open **ASoftware** from the Desktop or the Start menu and press **Start** on the system.

On our PC (i7-13700HX) iOS 16 takes about an hour, watchOS about an hour, iOS 26 two to three hours.

## Using it

- The mouse is the touchscreen, the wheel scrolls, the PC keyboard is a hardware keyboard and Ctrl+V
  types the PC's clipboard. The side bar has Home (F1), Lock (F2), the volume (F3/F4), Screenshot
  (Ctrl+S) and Full screen (F11).
- Closing the window saves iOS as it is: the next start goes on in seconds. ASoftware's **Save and
  close** does the same, and **Go back** returns to the last save.
- Apps: decrypted `.ipa` files through *Install .ipa…* in the side bar. iOS 26 takes them at its next
  start, which then sits on the Apple logo for about 11 minutes (longer on slower PCs): do not close it.
- Not working yet: sound, the App Store and Apple ID, and GPU drawing on iOS 16.

## If something goes wrong

1. Read the installer's message: it says why it stopped, and for most stops what to do.
2. Send us the logs: ASoftware's **Report a problem** opens a GitHub issue with your PC's details filled
   in, and **Pack logs (.zip)** puts the logs in a zip on your Desktop (look through it before you attach it).
3. Check the known problems first:
   - Windows or Chrome calls the zip a virus ([#5](https://github.com/alpersamur3/asoft-ios/issues/5), [#7](https://github.com/alpersamur3/asoft-ios/issues/7)):
     a false alarm on our unsigned `.exe` files. Compare the zip with `SHA256SUMS.txt`, or use the one-line installer.
   - Windows 10 cannot install WSL from the installer ([#15](https://github.com/alpersamur3/asoft-ios/issues/15)):
     choose *Install without WSL* (iOS 26 only).
   - QEMU closes a few seconds after iOS 26's first start, "no console on port 4451"
     ([#16](https://github.com/alpersamur3/asoft-ios/issues/16)): the PC has bottom-up ASLR turned off.
     In an administrator PowerShell run
     `Set-ProcessMitigation -Name qemu-system-aarch64.exe -Enable BottomUp,HighEntropy` and the same for
     `qemu-system-aarch64w.exe`, then restart Windows. The next version fixes it without this.
   - Intel UHD 630 loses the GPU during the install ([#12](https://github.com/alpersamur3/asoft-ios/issues/12)): still open.
   - AMD ([#1](https://github.com/alpersamur3/asoft-ios/issues/1)): fixed in 0.3.0 but not tried on a real AMD card since: a report is welcome.
   - There is no delete button yet ([#14](https://github.com/alpersamur3/asoft-ios/issues/14)). To remove
     everything, delete the install folder (`X:\ASoftware`), `ASoftware.lnk` on the Desktop and in the Start
     menu, `%LOCALAPPDATA%\ASoftware` and, if WSL was used, run `wsl --unregister ios-emu`.

---

The rest of this page is the technical detail: what each system is, what the installer does, the
keys, the disk, how it works and the licenses.

<p align="center">
<img src="ios26/screenshots/ios26-gpu.gif" width="420" alt="iOS 26 in the ASoftware window: Settings, scrolling, General, the home screen"><br>
<sub>iOS 26.6.2 in the ASoftware window on Windows 11, in real time with the pauses between gestures cut: iOS's own Metal draws the interface, on an NVIDIA RTX 4080 through Vulkan.</sub>
</p>

## Two iOS versions

| | iOS 16 | iOS 26 (new) |
| --- | --- | --- |
| **State** | Ready: a one-line installer | Research preview: the same installer builds it on your PC (two to three hours, about 50 GB at the peak) |
| **Graphics** | The CPU | **The PC's GPU**: iOS's own Metal, through Vulkan |
| **iOS** | 16.7.16 of the iPhone X | 26.6.2 of the iPhone 16, on the kernel of Apple's research VM |
| **Apps** | Safari with real web pages, `.ipa` installs | Safari with real web pages, `.ipa` installs (at the next start), the system apps, Settings, [OpenGL ES](ios26/README.md#what-works) (our test app so far) |
| **Quick boot** | Yes: iOS goes on in seconds | Yes: iOS goes on in seconds |
| **Start** | [Install](#install) | [Install](#install), then [`ios26/`](ios26/README.md) |

Is it really the GPU? See [the measurements](ios26/README.md#is-it-really-the-gpu).

**watchOS 27.2** (research preview): an Apple Watch Series 9 in a drawn case, on the same GPU path. It
does not need iOS 26, only the base it shares with it (cloudOS's kernel and firmware, the GPU driver:
about 1 GB from Apple), which an iOS 26 install has already. See [`watchos/`](watchos/README.md).

**visionOS 27.2** (research preview): the Apple Vision Pro's Home, Settings and Safari in a window drawn
as the headset, its 3D compositor on the same GPU path. The mouse is your eyes and your pinch; with the
right button held you look around and walk (W A S D). Like the watch it needs only the base it shares
with iOS 26, and WSL. It is slow (about 5 minutes to Home on a cold start, about 15 seconds from a quick
save) and silent for now: sound needs a plug-in that is not published yet. Its installer is new and has
not been run end to end yet. See [`visionos/`](visionos/README.md).

<!-- tvos:begin (Make-Release.ps1 -NoTvOS leaves this paragraph out of the package's README) -->
**tvOS 27.2** (research preview, not a usable Apple TV): the Apple TV 4K's Home and Settings in a window drawn as a TV with its
Siri Remote beside it, at 1080p or 4K, on the same GPU path; the keyboard is the remote. What does not work: About shows
Activation: Failed, Search and the Apple TV app say they are not available, a key can take 3 to 20 seconds to show, and
saves have not been tested. It needs only the base it shares with iOS 26, and WSL: iOS 26 itself does not have to be
installed. It is in the release package and the launcher (`Install-ASoftware.cmd -Version tvos`, which makes that base
when it is not there). Its installer ran to its end on our PC with Apple's files already downloaded and decrypted; its
download and decrypt steps have not been run from the package. See [`tvos/`](tvos/README.md).
<!-- tvos:end -->

**`ASoftware.exe`** is the launcher: it installs, starts and closes each system, holds its settings and
saves, sends iOS to an Android phone ([ASoftware iOS for Android](https://github.com/alpersamur3/asoft-ios-android))
and packs a problem report. The `.cmd` scripts below still work without it. One QEMU build runs all five
systems ([QEMU](#qemu)).

The rest of this page is about iOS 16; iOS 26 has [its own page](ios26/README.md).

ASoftware iOS boots the real, unmodified iOS 16.7.16 of the iPhone X on QEMU, on an ordinary
Windows PC: SpringBoard, Settings, Safari and the apps you install. The kernel is Apple's
open-source XNU with the patches of [ios-sweet](https://github.com/dipa-studio/ios-sweet), which
first brought this userland up on a Redmi Note 10 Pro, plus our own for QEMU's virtual hardware.

> [!NOTE]
> Experimental. Everything is emulated on the CPU (no GPU), so it is slower than a phone, and
> Apple's security model is mostly switched off. Not affiliated with Apple. No Apple software
> is in this repository: the installer downloads the iOS image from Apple and builds the disk
> on your PC.

## Features

| | |
| --- | --- |
| **iOS** | Lock and home screen, wallpapers and widgets, Control Center, Settings, Safari with real web pages |
| **Apps** | Install `.ipa` files from Windows while iOS runs: the side bar's *Install .ipa…* or a folder |
| **Input** | Mouse as the touchscreen, the wheel to scroll, the PC keyboard as a hardware keyboard, text pasted from the PC |
| **Window** | Phone-shaped, with a side bar in iOS's own dark style: Home, Lock, App switcher, volume, screenshots |
| **Quick boot** | Closing the window saves iOS as it is; the next start goes on from there in seconds. The save stays as a way back: after a *Shut down*, `ASoftware.exe`'s *Go back* returns to it until the next save replaces it |
| **States** | Pause and resume, save the whole machine and go back to it later; the clock catches up after either |
| **Clock** | Your PC's time zone, region format and 12/24-hour clock |
| **Disk** | What iOS writes is kept between starts; *Shut down* turns iOS off cleanly |
| **Network** | Internet through QEMU's user network |

Not yet: audio, GPU acceleration, the App Store and Apple ID services.

## Requirements

- Windows 10 (1903 or later) or 11, 64-bit; no admin rights, WSL or Mac needed. iOS 26 needs
  Windows 10 2004 or later; watchOS, visionOS and tvOS also need WSL 2
- A 4-core CPU or better and 16 GB of RAM (iOS gets 7 GB)
- About **27 GB** free while installing and **14 GB** once installed (see [Disk space](#disk-space))
- iOS 26 also wants a GPU whose Vulkan driver has version 1.2 and `VK_EXT_external_memory_host`, 8 or
  more logical processors and about 50 GB free while installing; the installer checks these first. It
  gets 4 GB of RAM unless you choose 3, 6 or 8 GB in `ASoftware.exe`, which checks for that much plus
  about 3.5 GB of free memory before it starts

## The installer

One installer for all of them: `Install-ASoftware.cmd`. Run it from `ASoftware-iOS-*-win64.zip`
([Releases](https://github.com/alpersamur3/asoft-ios/releases)), from a checkout of `main` (there
without *Install without WSL*), or in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
```

If an earlier install stopped, it first asks whether to go on or start over. Then:

1. **Which system:** iOS 16, iOS 26, both (one QEMU for both, downloaded once), or watchOS 27.2,
   visionOS 27.2 or tvOS 27.2 alone (only the base they share with iOS 26, not iOS 26 itself; they
   need WSL). With iOS 26 it also asks whether to add watchOS, visionOS and tvOS.
2. **For iOS 26, where its build runs Linux tools:** *Fast install (WSL)*, or *Install without
   WSL* (a small Linux VM in our QEMU; no administrator, no restart).
   - WSL is the default when it works.
   - If WSL is missing, it offers to install it, which needs an administrator and a restart; run
     the installer again afterwards and it goes on. Or it goes on without WSL.
   - With virtualization off in the BIOS/UEFI, WSL 2 cannot start, so it installs without WSL and
     says why.
   - iOS 16 never needs WSL.

Before anything starts it shows what each path takes on your PC:
- the download, exact, from the installers' own file lists;
- the disk space at the peak and after;
- the time, from our measured steps scaled to your PC's cores and to a 10 MB probe of Apple's servers.

On our PC (i7-13700HX, 24 threads, NVMe SSD; the estimates assume 40 Mbit/s, the measured runs give
their own speed):

| | Download | Disk: peak / after | Time |
| --- | --- | --- | --- |
| iOS 16 | 6.3 GB | 27 GB / 13.6 GB | about 1 h 5 min (measured: 43 min plus the download) |
| iOS 26, fast install (WSL) | 11.4 GB | 49 GB / 25 GB | about 1 h 45 min (measured: 75 min of steps, plus the 11 GB from Apple, about 30 min at 52 Mbit/s) |
| iOS 26, without WSL | 11.4 GB | 49 GB / 25 GB | about 2 h 35 min (measured end to end: 107 min of steps, plus the 11 GB from Apple, 47 min at about 32 Mbit/s) |
| Both (WSL) | 17.6 GB | 62 GB / 38 GB | about 2 h 50 min |
| watchOS alone (WSL) | 6.2 GB | 23 GB / 16 GB | about 1 h (measured end to end: 56 min, of which 32 min for the 6.2 GB from Apple at about 30 Mbit/s and 16 min for the watch's first start) |
| visionOS alone (WSL) | 18.8 GB | 22 GB / 22 GB | about 2 h 30 min (an estimate from the steps of our hand-run build: the installer has not been run end to end yet) |
| tvOS alone (WSL) | about 6 GB | 25 GB / 14 GB | about 1 h 40 min (an estimate: its download and decrypt steps have not been run from the package) |

The iOS 26 times were measured with 0.3.0; in 0.3.1 its wallpaper step is about 20 minutes shorter.
A new WSL distro for iOS 26 adds 0.9 GB to the download, about 15 minutes (the hfsplus module is
built for your WSL kernel) and about 7 GB on the drive WSL keeps its distros on.

While it runs, the window title shows the step, the time so far and the time left. At the end it
prints what it took and where everything is (also `install-summary.txt`). Everything goes into one
folder: `-Dir`, or `X:\ASoftware` on the drive with the most room (no spaces, for iOS 26).
Stopped, or restarted for WSL? Run it again: it goes on where it stopped.

| Option | Does |
| --- | --- |
| `-Version ios16\|ios26\|both\|watchos\|ios16-watchos\|visionos\|ios16-visionos\|tvos\|ios16-tvos`, `-Watch yes\|no`, `-Vision yes\|no`, `-Tv yes\|no`, `-Linux wsl\|helper`, `-IfNoWsl install\|nowsl` | Answers the questions (`watchos`, `visionos`, `tvos`: without iOS 26) |
| `-WatchQemu`, `-VisionQemu`, `-TvQemu <folder>` | watchOS, visionOS, tvOS from a checkout: a build of our QEMU with their options (release packages from 0.3.0 on have one in `qemu\bin`, which the installer finds itself) |
| `-Dir D:\ASoftware` | The install folder |
| `-Lang en\|tr` | The installer's language (Windows' by default) |
| `-Yes` | Asks nothing |
| `-Estimate` | Shows what it takes and stops |
| `-DryRun`, `-List`, `-Check` | What it would run, the steps, what is done; changes nothing |

iOS 16's part is `installer\Install-ASoftware.ps1`, which also runs alone (iOS 26's is
[`ios26\Install-iOS26.ps1`](ios26/README.md)):

1. the app, our QEMU build and Python
2. iOS 16.7.16 for the iPhone X, 6.2 GB from Apple (or `-Ipsw` with one you have), and the
   phone's device tree from it
3. the iOS disk, built from it by a small Linux VM in QEMU (21 min)
4. iOS's first start, which sets up its app database once (22 min)
5. a shortcut (through `Install-ASoftware.cmd`: `ASoftware` on the Desktop and in the Start menu)

A 4-core CPU takes longer. After that iOS starts in seconds with quick boot.

## Use

| In the window | Does |
| --- | --- |
| Mouse | Touch: click to tap, drag to swipe |
| **F1** / *Home* | Home (unlock, leave an app) |
| **F2** / *Lock* | Side button: lock, or wake when the screen is off |
| **F3** / **F4** | Volume down / up |
| Wheel | Scrolls: a swipe where the pointer is |
| *App switcher* | The app switcher (as the swipe up and hold) |
| Other keys | A hardware keyboard |
| **Ctrl+V** / *Paste text* | Types the PC's clipboard text (letters, digits and symbols of a US keyboard) |
| **Ctrl+S** / *Screenshot* | A PNG in `Pictures\iOS Screenshots` |
| **F11** / *Full screen* | Full screen and back |
| *Install .ipa…* | Installs apps; or drop `.ipa` files into the `ipa` folder |
| *Pause* / *Resume* | Stops iOS where it is, or goes on |
| *Save state* / *Saved states…* | Saves the whole machine (about 3.5 GB, about 10 s), or goes back to one or deletes it |
| Close the window | Saves iOS as it is and quits; the next start resumes it |
| *Shut down* | Turns iOS off cleanly (about 10 s); pressed again, quits at once |

## Disk space

| | While installing | Installed |
| --- | --- | --- |
| iOS image from Apple (IPSW) | 6.2 GB | removed (kept with `-KeepIpsw`) |
| iOS disk | 12.4 GB | 12.9 GB after the first start |
| Room to build it | 7.6 GB | removed |
| App, QEMU, Python, kernel | 0.7 GB | 0.7 GB |
| A saved state (quick boot, *Save state*) | | about 3.5 GB each |
| **Total** | **about 27 GB** | **about 13.6 GB**, plus what iOS stores as you use it |

## How it works

```
Windows ── QEMU (-M virt, TCG; our window: side bar, phone shape, power key, quick boot)
             └─ XNU kernel (ios-sweet + ASoftware patches: virtio disk/net/input, ramfb, AMFI, ...)
                  └─ iOS 16.7.16 userland of the iPhone X, unmodified, on one HFS+ disk
                       └─ asoftinstalld (ours): .ipa installs, time zone, region, clock
```

| Path | What |
| --- | --- |
| `xnu/patches/` | Patches on Apple's XNU: 0001-0081 from ios-sweet, 0082 on for QEMU |
| `installer/` | The installer, and the helper VM (arm64 Linux) that builds the iOS disk |
| `tools/` | Device tree, boot payload, QEMU launcher, iOS root builder, disk tool |
| `apps/` | Our iOS programs: `asoftinstalld` and a test app |
| `scripts/` | iOS 16's start script, .ipa server, WSL disk build, sending iOS to a phone; `dev/` for benchmarks and debugging |
| `launcher/` | `ASoftware.exe` |
| `ios26/`, `watchos/`, `visionos/`, `tvos/` | Each system's installer, start script and page |
| `assets/` | The logo and the banner |

Builds: the kernel and the iOS apps on macOS (`.github/workflows/xnu.yml`, `ios-apps.yml`),
QEMU on Windows ([below](#qemu)), the helper VM on Linux (`installer/helper/build-*.sh`).

### QEMU

One QEMU build runs all five systems: [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/asoft-release),
branch `asoft-release` (`asoft` before 0.3.0, `ios26` until 2026-11-01; QEMU 11.1 with jprx's
research-VM work and our iOS 26 machine), built by [`ios26/scripts/win-build.sh`](ios26/scripts/win-build.sh). `-M virt` boots
iOS 16 as before, `-M vresearch` boots iOS 26, watchOS, visionOS and tvOS. The release zip carries the
build in `qemu\bin` (in 0.3.1 built from [`asoft-tv`](https://github.com/alpersamur3/qemu-sptm/tree/asoft-tv):
`asoft-release` plus the TV's window), and every installer takes it from there.
From a checkout, the iOS 16 and iOS 26 installers download its release package
([`asoft-7364c4e`](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)), which does
not have the watch's, the headset's and the TV's options yet (the watch's screen and crown; the
headset's window, its walk mode and `-cpu x-tlbi-filter`; the TV's window): there, give watchOS,
visionOS and tvOS a build with `-WatchQemu` / `-VisionQemu` / `-TvQemu`. The launchers run it from
`work\qemu`; the watch's installer keeps its copy in `work\qemu-watch`, and visionOS's puts it in
place of `work\qemu`.

Our window for iOS 16 was eight patches on QEMU 11.1.2 in `qemu/patches/`. They are commits on
that branch now, unchanged:

| Patch | Commit | What |
| --- | --- | --- |
| 0002 | [`141c6c6`](https://github.com/alpersamur3/qemu-sptm/commit/141c6c6) | The window refreshes at most every 30 ms |
| 0003 | [`0b8513d`](https://github.com/alpersamur3/qemu-sptm/commit/0b8513d) | `window-close=off`: closing the window powers iOS down |
| 0004 | [`bceefed`](https://github.com/alpersamur3/qemu-sptm/commit/bceefed) | The window title is `-name` alone |
| 0005 | [`41c7c5b`](https://github.com/alpersamur3/qemu-sptm/commit/41c7c5b) | `zoom-to-fit` opens the window at the phone's shape |
| 0006 | [`e35ca2b`](https://github.com/alpersamur3/qemu-sptm/commit/e35ca2b) | The side bar with the phone's buttons |
| 0007 | [`96015e5`](https://github.com/alpersamur3/qemu-sptm/commit/96015e5) | The *Screen off* cover, from the kernel's Scroll Lock LED |
| 0008 | [`ec0de47`](https://github.com/alpersamur3/qemu-sptm/commit/ec0de47) | ASoftware's look: logo, icon, dark side bar |
| 0009 | [`b817605`](https://github.com/alpersamur3/qemu-sptm/commit/b817605) | Quick boot, saved states, pause, app switcher, wheel swipes, pasted text |

`qemu/patches/`, `qemu/build-windows.sh` and the `qemu-win` workflow (stock and patched QEMU
11.1.2, side by side) were removed: nothing ships that build any more, and keeping a second copy
of the same patches in step with the branch would be work for a QEMU nobody runs. Their last
version is in the history (`git show 4dd2fce:qemu/patches`), with the stock build the 30 ms
refresh was measured against (2026-10-21).

## Credits and licenses

- [ios-sweet](https://github.com/dipa-studio/ios-sweet) by dipa-studio and contributors (MIT): the
  XNU port this project is built on.
- This repository: MIT, see [LICENSE](LICENSE) (dipa-studio and ASoftware).
- `xnu/patches/` modify Apple's XNU (Apple Public Source License 2.0); a kernel built from them is
  under the APSL too. Our QEMU, [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm)
  (a fork of [jprx/qemu-sptm](https://github.com/jprx/qemu-sptm)), is QEMU's GPL v2.
- iOS is Apple's and is not distributed here. Apple, iPhone and iOS are trademarks of Apple Inc.

---

<a name="turkce"></a>

<details>
<summary><b>Türkçe</b></summary>

<br>

Windows bilgisayarınızda bir pencerede gerçek iOS. iOS 16'yı işlemci çizer ve çoğu bilgisayarda çalışır;
iOS 26'yı, watchOS'u, visionOS'u ve tvOS'u bilgisayarınızın ekran kartı Vulkan üzerinden çizer. Kurucu
iOS'u Apple'ın kendi sunucularından indirir ve bilgisayarınızda kurar: bu repoda ve sürüm paketinde Apple
dosyası yoktur.

Bu bir araştırma önizlemesidir: gerçek bir iPhone'dan yavaştır, kurulum bir ile üç saat sürer ve bazı
bilgisayarlar henüz çözemediğimiz sorunlara takılır (aşağıda). Apple ile bir bağı yoktur.

### Bilgisayarımda çalışır mı?

| | Bilgisayarın ihtiyacı | Kurulum sırasında boş alan | Kurulumdan sonra kalan |
|---|---|---|---|
| **iOS 16** | Windows 10 1903 ya da sonrası veya Windows 11, 64 bit; 16 GB RAM, 4 çekirdek. Ekran kartı, WSL ya da yönetici izni gerekmez | yaklaşık 27 GB | yaklaşık 14 GB |
| **iOS 26** | Windows 10 2004 ya da sonrası veya Windows 11; Vulkan sürücüsü 1.2 sürümünde, `VK_EXT_external_memory_host` destekli ve iki yıldan yeni bir ekran kartı; 16 GB RAM ve 8 mantıksal işlemci önerilir | yaklaşık 50 GB | yaklaşık 25 GB |
| **watchOS** | aynı ekran kartı ve WSL 2 | yaklaşık 23 GB | yaklaşık 16 GB |
| **visionOS** | aynı ekran kartı ve WSL 2 | yaklaşık 22 GB | yaklaşık 22 GB |
| **tvOS** | aynı ekran kartı ve WSL 2 | yaklaşık 25 GB | yaklaşık 14 GB |

- Kurucu bunların hepsine bir şey indirmeden önce bakar ve bilgisayarınız için indirmeyi, alanı ve süreyi
  gösterir.
- Ekran kartı yolu NVIDIA'da denendi. AMD ve Intel için: [Bir sorun çıkarsa](#bir-sorun-çıkarsa).
- Yeni bir WSL kurulumu, WSL'in dosyalarını tuttuğu sürücüde yaklaşık 7 GB daha ister.

### Kurulum

1. PowerShell'de:

   ```powershell
   powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
   ```

   En yeni sürümü indirir, `SHA256SUMS.txt` ile karşılaştırır ve kurucuyu başlatır. Ya da
   [Releases](https://github.com/alpersamur3/asoft-ios/releases/latest) sayfasından
   `ASoftware-iOS-<sürüm>-win64.zip`'i indirin, açın ve `Install-ASoftware.cmd`'yi çalıştırın.
2. Sistemi seçin. iOS 26 için ayrıca *Hızlı kurulum (WSL)* ya da *WSL'siz kurulum* sorar.
3. Bilgisayarı açık bırakın. Durdu mu, ya da WSL için yeniden başlatıldı mı? Yeniden çalıştırın: kaldığı
   yerden sürer.
4. Bitince Masaüstünden ya da Başlat menüsünden **ASoftware**'i açın ve sistemin **Start** düğmesine basın.

Bizim bilgisayarda (i7-13700HX) iOS 16 yaklaşık bir saat, watchOS yaklaşık bir saat, iOS 26 iki üç saat sürer.

### Nasıl kullanılır

- Fare dokunmatik ekrandır, tekerlek kaydırır, PC klavyesi donanım klavyesidir ve Ctrl+V PC panosundaki
  metni yazar. Kenar çubuğunda Home (F1), kilit (F2), ses (F3/F4), ekran görüntüsü (Ctrl+S) ve tam ekran
  (F11) var.
- Pencereyi kapatmak iOS'u olduğu gibi kaydeder: sonraki açılış saniyeler içinde oradan devam eder.
  ASoftware'deki **Save and close** aynısını yapar, **Go back** son kayda döner.
- Uygulamalar: kenar çubuğundaki *Install .ipa…* ile şifresi çözülmüş `.ipa` dosyaları. iOS 26 onları bir
  sonraki açılışta alır; o açılış Apple logosunda yaklaşık 11 dakika bekler (yavaş bilgisayarlarda daha
  uzun): kapatmayın.
- Henüz çalışmayanlar: ses, App Store ve Apple Kimliği, iOS 16'da ekran kartıyla çizim.

### Bir sorun çıkarsa

1. Kurucunun mesajını okuyun: neden durduğunu ve çoğu durumda ne yapılacağını söyler.
2. Bize logları gönderin: ASoftware'deki **Report a problem** bilgisayarınızın bilgileri dolu bir GitHub
   issue'su açar, **Pack logs (.zip)** logları Masaüstünüzde bir zip'e koyar (eklemeden önce içine bakın).
3. Önce bilinen sorunlara bakın:
   - Windows ya da Chrome zip'e virüs diyor ([#5](https://github.com/alpersamur3/asoft-ios/issues/5), [#7](https://github.com/alpersamur3/asoft-ios/issues/7)):
     imzasız `.exe` dosyalarımız yüzünden yanlış alarm. Zip'i `SHA256SUMS.txt` ile karşılaştırın ya da tek satırlık kurulumu kullanın.
   - Windows 10'da kurucu WSL'i kuramıyor ([#15](https://github.com/alpersamur3/asoft-ios/issues/15)):
     *WSL'siz kurulum*'u seçin (yalnız iOS 26).
   - iOS 26'nın ilk açılışından birkaç saniye sonra QEMU kapanıyor, "no console on port 4451"
     ([#16](https://github.com/alpersamur3/asoft-ios/issues/16)): bilgisayarda bottom-up ASLR kapalı.
     Yönetici PowerShell'de
     `Set-ProcessMitigation -Name qemu-system-aarch64.exe -Enable BottomUp,HighEntropy` komutunu ve aynısını
     `qemu-system-aarch64w.exe` için çalıştırın, sonra Windows'u yeniden başlatın. Sonraki sürüm bunu gerektirmeden düzeltiyor.
   - Intel UHD 630 kurulum sırasında ekran kartını kaybediyor ([#12](https://github.com/alpersamur3/asoft-ios/issues/12)): hâlâ açık.
   - AMD ([#1](https://github.com/alpersamur3/asoft-ios/issues/1)): 0.3.0'da düzeltildi ama o zamandan beri gerçek bir AMD kartta denenmedi: rapor gelirse seviniriz.
   - Henüz silme düğmesi yok ([#14](https://github.com/alpersamur3/asoft-ios/issues/14)). Her şeyi kaldırmak
     için kurulum klasörünü (`X:\ASoftware`), Masaüstündeki ve Başlat menüsündeki `ASoftware.lnk`'yi,
     `%LOCALAPPDATA%\ASoftware`'i silin ve WSL kullanıldıysa `wsl --unregister ios-emu` çalıştırın.

---

Aşağısı teknik ayrıntılar: her sistem ne, kurucu ne yapar, tuşlar, disk, nasıl çalışır ve lisanslar.

**İki iOS sürümü**

| | iOS 16 | iOS 26 (yeni) |
| --- | --- | --- |
| **Durum** | Hazır: tek satırlık kurulum | Araştırma önizlemesi: aynı kurucu bilgisayarınızda derler (iki üç saat, en çok yaklaşık 50 GB) |
| **Grafik** | İşlemci | **Bilgisayarın ekran kartı**: iOS'un kendi Metal'i, Vulkan üzerinden |
| **iOS** | iPhone X'in 16.7.16'sı | iPhone 16'nın 26.6.2'si, Apple'ın araştırma VM'inin çekirdeğinde |
| **Uygulamalar** | Gerçek web sayfalarıyla Safari, `.ipa` kurma | Gerçek web sayfalarıyla Safari, `.ipa` kurma (sonraki açılışta), sistem uygulamaları, Ayarlar, [OpenGL ES](ios26/README.md#turkce) (şimdilik test uygulamamız) |
| **Hızlı açılış** | Var: iOS saniyeler içinde kaldığı yerden devam eder | Var: iOS saniyeler içinde kaldığı yerden devam eder |
| **Başlangıç** | [Kurulum](#kurulum) | [Kurulum](#kurulum), sonra [`ios26/`](ios26/README.md#turkce) |

Gerçekten ekran kartı mı? [Ölçümler](ios26/README.md#is-it-really-the-gpu).

**watchOS 27.2** (araştırma önizlemesi): çizilmiş bir kasa içinde Apple Watch Series 9, aynı GPU yolunda.
iOS 26 gerekmez, yalnız onunla paylaştığı taban (cloudOS'un çekirdeği ve ürün yazılımı, GPU sürücüsü:
Apple'dan yaklaşık 1 GB); iOS 26 kuruluysa bu taban zaten vardır. Bkz. [`watchos/`](watchos/README.md).

**visionOS 27.2** (araştırma önizlemesi): başlık olarak çizilmiş bir pencerede Apple Vision Pro'nun Home'u,
Ayarlar'ı ve Safari'si; 3B birleştiricisi aynı GPU yolunda. Fare gözünüz ve parmak sıkıştırmanızdır; sağ
tuş basılıyken etrafa bakar ve yürürsünüz (W A S D). Saat gibi yalnız iOS 26 ile paylaştığı tabanı ve
WSL'i ister. Yavaştır (soğuk açılışta Home'a yaklaşık 5 dakika, hızlı kayıttan yaklaşık 15 saniye) ve
şimdilik sessizdir: ses, henüz yayımlanmamış bir eklenti ister. Kurucusu yenidir ve henüz uçtan uca
çalıştırılmadı. Bkz. [`visionos/`](visionos/README.md).

<!-- tvos:begin (Make-Release.ps1 -NoTvOS leaves this paragraph out of the package's README) -->
**tvOS 27.2** (araştırma önizlemesi, kullanılabilir bir Apple TV değil): TV olarak çizilmiş, yanında Siri Remote'u olan
bir pencerede Apple TV 4K'nın Home'u ve Ayarlar'ı, 1080p ya da 4K, aynı GPU yolunda; klavye kumandadır. Çalışmayanlar:
About'ta Activation: Failed yazar, Search ve Apple TV uygulaması kullanılamıyor der, bir tuşun görünmesi 3 ile 20 saniye
sürebilir ve kayıtlar denenmedi. Yalnız iOS 26 ile paylaştığı tabanı ve WSL'i ister: iOS 26'nın kurulu olması gerekmez.
Sürüm paketinde ve başlatıcıdadır (`Install-ASoftware.cmd -Version tvos`; taban yoksa onu da kurar). Kurucusu bizim
bilgisayarda Apple'ın dosyaları önceden indirilip şifresi çözülmüşken sonuna kadar çalıştı; indirme ve şifre çözme
adımları paketten çalıştırılmadı. Bkz. [`tvos/`](tvos/README.md).
<!-- tvos:end -->

**`ASoftware.exe`** başlatıcıdır: her sistemi kurar, açar ve kapatır, ayarlarını ve kayıtlarını tutar,
iOS'u Android telefona gönderir ([ASoftware iOS for Android](https://github.com/alpersamur3/asoft-ios-android))
ve sorun raporu hazırlar. Aşağıdaki `.cmd` betikleri onsuz da çalışır. Beş sistemi de tek bir QEMU
derlemesi çalıştırır ([QEMU](#qemu-1)).

Aşağısı iOS 16 hakkında.

ASoftware iOS, iPhone X'in gerçek ve değiştirilmemiş iOS 16.7.16'sını sıradan bir Windows
PC'de, QEMU'da açar: SpringBoard, Ayarlar, Safari ve kurduğunuz uygulamalar. Çekirdek, Apple'ın
açık kaynak XNU'su; üzerinde bu sistemi ilk kez bir Redmi Note 10 Pro'da açan
[ios-sweet](https://github.com/dipa-studio/ios-sweet) yamaları ve QEMU'nun sanal donanımı için
bizim yamalarımız var.

> [!NOTE]
> Deneysel. Her şey işlemcide öykünülüyor (GPU yok), bu yüzden telefondan yavaş; Apple'ın
> güvenlik modeli büyük ölçüde kapalı. Apple ile bir bağı yoktur. Bu repoda Apple yazılımı
> yoktur: kurulum programı iOS kalıbını Apple'dan indirir ve diski sizin bilgisayarınızda kurar.

### Özellikler

| | |
| --- | --- |
| **iOS** | Kilit ve ana ekran, duvar kağıtları ve widget'lar, Denetim Merkezi, Ayarlar, gerçek sayfaları açan Safari |
| **Uygulamalar** | iOS açıkken Windows'tan `.ipa` kurma: kenar çubuğundaki *Install .ipa…* ya da bir klasör |
| **Giriş** | Fare dokunmatik ekran, tekerlek kaydırma, PC klavyesi donanım klavyesi, PC'den metin yapıştırma |
| **Pencere** | Telefon biçiminde, iOS'un kendi koyu tarzında kenar çubuğu: Home, kilit, uygulama değiştirici, ses, ekran görüntüsü |
| **Hızlı açılış** | Pencereyi kapatmak iOS'u olduğu gibi kaydeder; sonraki açılış saniyeler içinde oradan devam eder. Kayıt geri dönüş olarak kalır: *Shut down* sonrası `ASoftware.exe`'deki *Go back*, sonraki kayıt yerini alana kadar ona döner |
| **Durumlar** | Duraklatma ve devam, tüm makineyi kaydedip sonra ona dönme; ikisinden sonra da saat kendini düzeltir |
| **Saat** | PC'nizin saat dilimi, bölge biçimi ve 12/24 saat ayarı |
| **Disk** | iOS'un yazdıkları açılışlar arasında saklanır; *Shut down* iOS'u düzgünce kapatır |
| **Ağ** | QEMU'nun kullanıcı ağıyla internet |

Henüz yok: ses, GPU hızlandırma, App Store ve Apple Kimliği hizmetleri.

### Gereksinimler

- Windows 10 (1903 ve sonrası) ya da 11, 64 bit; yönetici izni, WSL ya da Mac gerekmez. iOS 26
  Windows 10 2004 ya da sonrasını ister; watchOS, visionOS ve tvOS ayrıca WSL 2 ister
- 4 çekirdekli ya da daha iyi bir işlemci ve 16 GB RAM (iOS 7 GB kullanır)
- Kurulum sırasında yaklaşık **27 GB**, kurulumdan sonra **14 GB** boş alan ([Disk alanı](#disk-alanı))
- iOS 26 ayrıca Vulkan sürücüsü 1.2 sürümünde ve `VK_EXT_external_memory_host` destekli bir ekran kartı,
  8 ya da daha fazla mantıksal işlemci ve kurulum sırasında yaklaşık 50 GB boş alan ister; kurucu bunlara
  önce bakar. `ASoftware.exe`'de 3, 6 ya da 8 GB seçilmezse 4 GB RAM kullanır; açmadan önce bu kadarına
  ek yaklaşık 3,5 GB boş bellek arar

### Kurucu

Hepsi için tek kurucu: `Install-ASoftware.cmd`.
[Releases](https://github.com/alpersamur3/asoft-ios/releases) sayfasındaki `ASoftware-iOS-*-win64.zip`'ten,
`main`'in bir kopyasından (orada *WSL'siz kurulum* olmadan) ya da PowerShell'de çalıştırın:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
```

Önceden başlamış bir kurulum durduysa önce devam mı, baştan mı diye sorar. Sonra:

1. **Hangi sistem:** iOS 16, iOS 26, ikisi (ikisine tek QEMU, bir kez indirilir), ya da yalnız watchOS
   27.2, yalnız visionOS 27.2 veya yalnız tvOS 27.2 (iOS 26'nın kendisi değil, yalnız onunla
   paylaştıkları taban; WSL isterler). iOS 26 seçilince watchOS'un, visionOS'un ve tvOS'un da eklenip
   eklenmeyeceğini sorar.
2. **iOS 26 için, derleme Linux araçlarını nerede çalıştırsın:** *Hızlı kurulum (WSL)* ya da
   *WSL'siz kurulum* (QEMU'muzda küçük bir Linux VM; yönetici izni ve yeniden başlatma gerekmez).
   - WSL çalışıyorsa varsayılan WSL'dir.
   - WSL yoksa kurmayı önerir; bu yönetici izni ve yeniden başlatma ister, sonra kurucuyu yeniden
     çalıştırınca kaldığı yerden sürer. Ya da WSL'siz devam eder.
   - Sanallaştırma BIOS/UEFI'de kapalıysa WSL 2 çalışamaz; kurucu nedenini söyleyip WSL'siz kurar.
   - iOS 16 hiç WSL istemez.

Bir şey başlamadan önce her yolun bilgisayarınızda ne gerektirdiğini gösterir:
- indirme, kesin, kurucuların kendi dosya listelerinden;
- en çok ve sonra kalan disk alanı;
- süre, bizim ölçtüğümüz adımlardan, bilgisayarınızın çekirdek sayısına ve Apple'ın sunucularından
  10 MB'lık bir ölçüme göre.

Bizim bilgisayarda (i7-13700HX, 24 iş parçacığı, NVMe SSD; tahminler 40 Mbit/s varsayar, ölçülen
kurulumlar kendi hızlarını yazar):

| | İndirme | Disk: en çok / sonra | Süre |
| --- | --- | --- | --- |
| iOS 16 | 6,3 GB | 27 GB / 13,6 GB | yaklaşık 1 sa 5 dk (ölçülen: 43 dk artı indirme) |
| iOS 26, hızlı kurulum (WSL) | 11,4 GB | 49 GB / 25 GB | yaklaşık 1 sa 45 dk (ölçülen: 75 dk adım süresi, artı Apple'dan 11 GB, 52 Mbit/s'de ~30 dk) |
| iOS 26, WSL'siz | 11,4 GB | 49 GB / 25 GB | yaklaşık 2 sa 35 dk (uçtan uca ölçülen: 107 dk adım süresi, artı Apple'dan 11 GB, ~32 Mbit/s'de 47 dk) |
| İkisi (WSL) | 17,6 GB | 62 GB / 38 GB | yaklaşık 2 sa 50 dk |
| Yalnız watchOS (WSL) | 6,2 GB | 23 GB / 16 GB | yaklaşık 1 sa (uçtan uca ölçüldü: 56 dk; 32 dakikası Apple'dan 6,2 GB, yaklaşık 30 Mbit/s ile, 16 dakikası saatin ilk açılışı) |
| Yalnız visionOS (WSL) | 18,8 GB | 22 GB / 22 GB | yaklaşık 2 sa 30 dk (elle yaptığımız kurulumun adımlarından tahmin: kurucu henüz uçtan uca çalıştırılmadı) |
| Yalnız tvOS (WSL) | yaklaşık 6 GB | 25 GB / 14 GB | yaklaşık 1 sa 40 dk (tahmin: indirme ve şifre çözme adımları paketten çalıştırılmadı) |

iOS 26 süreleri 0.3.0 ile ölçüldü; 0.3.1'de duvar kağıdı adımı yaklaşık 20 dakika daha kısa.
iOS 26 için yeni bir WSL dağıtımı indirmeye 0,9 GB, süreye yaklaşık 15 dakika (hfsplus modülü WSL
çekirdeğinize göre derlenir) ve WSL'in dağıtımları tuttuğu sürücüde yaklaşık 7 GB ekler.

Çalışırken pencere başlığı adımı, geçen ve kalan süreyi gösterir. Sonunda ne kadar sürdüğünü ve her
şeyin nerede olduğunu yazar (`install-summary.txt`'ye de). Her şey tek klasöre gider: `-Dir`, ya da en
çok boş yeri olan sürücüde `X:\ASoftware` (iOS 26 için boşluksuz). Durdu mu, ya da WSL için yeniden
başlatıldı mı? Yeniden çalıştırın: kaldığı yerden sürer.

| Seçenek | Ne yapar |
| --- | --- |
| `-Version ios16\|ios26\|both\|watchos\|ios16-watchos\|visionos\|ios16-visionos\|tvos\|ios16-tvos`, `-Watch yes\|no`, `-Vision yes\|no`, `-Tv yes\|no`, `-Linux wsl\|helper`, `-IfNoWsl install\|nowsl` | Soruları yanıtlar (`watchos`, `visionos`, `tvos`: iOS 26'sız) |
| `-WatchQemu`, `-VisionQemu`, `-TvQemu <klasör>` | Depo kopyasından watchOS, visionOS, tvOS: seçeneklerini içeren QEMU derlememiz (0.3.0'dan itibaren sürüm paketlerinde `qemu\bin` içinde vardır, kurucu kendisi bulur) |
| `-Dir D:\ASoftware` | Kurulum klasörü |
| `-Lang en\|tr` | Kurucunun dili (varsayılan Windows'unki) |
| `-Yes` | Hiçbir şey sormaz |
| `-Estimate` | Ne gerektirdiğini gösterip durur |
| `-DryRun`, `-List`, `-Check` | Ne çalıştıracağı, adımlar, ne yapıldığı; hiçbir şeyi değiştirmez |

iOS 16'nın kısmı `installer\Install-ASoftware.ps1`; tek başına da çalışır (iOS 26'nınki
[`ios26\Install-iOS26.ps1`](ios26/README.md#turkce)):

1. uygulama, QEMU derlememiz ve Python
2. iPhone X için iOS 16.7.16, Apple'dan 6,2 GB (ya da elinizdekiyle `-Ipsw`) ve içinden
   telefonun cihaz ağacı
3. iOS diski, QEMU'daki küçük bir Linux VM'i tarafından kurulur (21 dk)
4. iOS'un ilk açılışı; uygulama veritabanını bir kez kurar (22 dk)
5. kısayol (`Install-ASoftware.cmd` ile: Masaüstünde ve Başlat menüsünde `ASoftware`)

4 çekirdekli işlemcide daha uzun sürer. Sonrasında iOS hızlı açılışla saniyeler içinde açılır.

### Kullanım

| Pencerede | Ne yapar |
| --- | --- |
| Fare | Dokunma: tıklama dokunur, sürükleme kaydırır |
| **F1** / *Home* | Ana ekran (kilidi açar, uygulamadan çıkar) |
| **F2** / *Lock* | Yan tuş: kilitler, ekran kapalıyken uyandırır |
| **F3** / **F4** | Ses kıs / aç |
| Tekerlek | Kaydırır: imlecin olduğu yerde bir kaydırma hareketi |
| *App switcher* | Uygulama değiştirici (yukarı kaydırıp bekleme gibi) |
| Diğer tuşlar | Donanım klavyesi |
| **Ctrl+V** / *Paste text* | PC panosundaki metni yazar (ABD klavyesinin harf, rakam ve simgeleri) |
| **Ctrl+S** / *Screenshot* | `Resimler\iOS Screenshots` içine PNG |
| **F11** / *Full screen* | Tam ekran ve geri |
| *Install .ipa…* | Uygulama kurar; ya da `.ipa` dosyalarını `ipa` klasörüne bırakın |
| *Pause* / *Resume* | iOS'u olduğu yerde durdurur ya da devam ettirir |
| *Save state* / *Saved states…* | Tüm makineyi kaydeder (yaklaşık 3,5 GB, yaklaşık 10 sn), ya da birine döner veya siler |
| Pencereyi kapatmak | iOS'u olduğu gibi kaydedip çıkar; sonraki açılış oradan devam eder |
| *Shut down* | iOS'u düzgünce kapatır (yaklaşık 10 sn); ikinci kez basınca hemen çıkar |

### Disk alanı

| | Kurulum sırasında | Kurulumdan sonra |
| --- | --- | --- |
| Apple'dan iOS kalıbı (IPSW) | 6,2 GB | silinir (`-KeepIpsw` ile kalır) |
| iOS diski | 12,4 GB | ilk açılıştan sonra 12,9 GB |
| Kurmak için gereken alan | 7,6 GB | silinir |
| Uygulama, QEMU, Python, çekirdek | 0,7 GB | 0,7 GB |
| Kayıtlı durum (hızlı açılış, *Save state*) | | her biri yaklaşık 3,5 GB |
| **Toplam** | **yaklaşık 27 GB** | **yaklaşık 13,6 GB**, artı kullandıkça iOS'un sakladıkları |

### QEMU

Beş sistemi de tek bir QEMU derlemesi çalıştırır: [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/asoft-release)
deposunun `asoft-release` dalı (0.3.0'dan önce `asoft`, 2026-11-01'e kadar `ios26`; jprx'in araştırma
VM'i çalışması ve bizim iOS 26 makinemizle QEMU 11.1), [`ios26/scripts/win-build.sh`](ios26/scripts/win-build.sh) ile derlenir.
`-M virt` iOS 16'yı eskisi gibi, `-M vresearch` iOS 26'yı, watchOS'u, visionOS'u ve tvOS'u açar. Sürüm
zip'i derlemeyi `qemu\bin` içinde taşır (0.3.1'de [`asoft-tv`](https://github.com/alpersamur3/qemu-sptm/tree/asoft-tv)
dalından derlendi: `asoft-release` artı TV'nin penceresi), kurucuların hepsi onu oradan alır.
Depo kopyasından çalışınca iOS 16 ve iOS 26 kurulumları onun sürüm paketini indirir
([`asoft-7364c4e`](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)); o pakette
saatin, başlığın ve TV'nin seçenekleri henüz yoktur (saatin ekranı ve tacı; başlığın penceresi, yürüme
modu ve `-cpu x-tlbi-filter`; TV'nin penceresi): orada watchOS, visionOS ve tvOS'a `-WatchQemu` /
`-VisionQemu` / `-TvQemu` ile bir derleme verin.
Başlatıcılar onu `work\qemu` içinden çalıştırır; saatin kurucusu kendi kopyasını `work\qemu-watch`
içinde tutar, visionOS'unki onu `work\qemu`'nun yerine koyar. iOS 16 penceresinin QEMU 11.1.2 üzerindeki sekiz yaması (`qemu/patches/`, 0002-0009)
artık bu dalda değiştirilmeden birer commit'tir (liste yukarıda, İngilizce bölümün *QEMU* başlığında).
`qemu/patches/`, `qemu/build-windows.sh` ve `qemu-win` iş akışı kaldırıldı: o derlemeyi artık hiçbir şey
dağıtmıyor, aynı yamaların ikinci bir kopyasını dalla eşit tutmak kimsenin çalıştırmadığı bir QEMU için
emek olurdu. Son hâlleri geçmişte duruyor (`git show 4dd2fce:qemu/patches`).

### Emeği geçenler ve lisanslar

- dipa-studio ve katkıda bulunanların [ios-sweet](https://github.com/dipa-studio/ios-sweet) projesi
  (MIT): bu projenin üzerine kurulduğu XNU uyarlaması.
- Bu repo: MIT, bkz. [LICENSE](LICENSE) (dipa-studio ve ASoftware).
- `xnu/patches/` Apple'ın XNU'sunu değiştirir (Apple Public Source License 2.0); bunlardan derlenen
  çekirdek de APSL'dir. QEMU'muz, [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm)
  ([jprx/qemu-sptm](https://github.com/jprx/qemu-sptm) çatalı), QEMU'nun GPL v2 lisansındadır.
- iOS Apple'ındır ve burada dağıtılmaz. Apple, iPhone ve iOS, Apple Inc.'in ticari markalarıdır.

</details>
