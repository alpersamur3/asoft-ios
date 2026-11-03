<div align="center">

<img src="assets/logo-256.png" width="132" alt="ASoftware iOS">

# ASoftware iOS

**Apple's iOS in a window on your Windows PC.**<br>
iOS 16, ready to install · **new:** iOS 26, drawn by your PC's GPU

![Windows 10/11 x64](https://img.shields.io/badge/Windows-10%20%7C%2011%20x64-0a84ff?style=flat-square)
![iOS 16.7.16](https://img.shields.io/badge/iOS-16.7.16%20(iPhone%20X)-1c1c1e?style=flat-square)
![iOS 26.6.2 on the GPU](https://img.shields.io/badge/iOS%2026.6.2-GPU%20via%20Vulkan-30d158?style=flat-square)
![QEMU 11.1](https://img.shields.io/badge/QEMU-11.1-ff9f0a?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-30d158?style=flat-square)
[![Release](https://img.shields.io/github/v/release/alpersamur3/asoft-ios?style=flat-square&color=0a84ff)](https://github.com/alpersamur3/asoft-ios/releases/latest)

<br>

<img src="ios26/screenshots/ios26-gpu.gif" width="420" alt="iOS 26 in the ASoftware window: Settings, scrolling, General, the home screen">

<sub>iOS 26.6.2 in the ASoftware window on Windows 11, in real time with the pauses between gestures cut: iOS's own Metal draws the interface, on an NVIDIA RTX 4080 through Vulkan.</sub>

English · [Türkçe](#turkce)

</div>

## Two iOS versions

| | iOS 16 | iOS 26 (new) |
| --- | --- | --- |
| **State** | Ready: a one-line installer | Research preview: the same installer builds it on your PC (hours, 57 GB at the peak) |
| **Graphics** | The CPU | **The PC's GPU**: iOS's own Metal, through Vulkan |
| **iOS** | 16.7.16 of the iPhone X | 26.6.2 of the iPhone 16, on the kernel of Apple's research VM |
| **Apps** | Safari with real web pages, `.ipa` installs | The system apps, Settings |
| **Quick boot** | Yes: iOS goes on in seconds | Yes: iOS goes on in seconds |
| **Start** | [Install](#install) | [Install](#install), then [`ios26/`](ios26/README.md) |

Is it really the GPU? See [the measurements](ios26/README.md#is-it-really-the-gpu).

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
| **Quick boot** | Closing the window saves iOS as it is; the next start goes on from there in seconds |
| **States** | Pause and resume, save the whole machine and go back to it later; the clock catches up after either |
| **Clock** | Your PC's time zone, region format and 12/24-hour clock |
| **Disk** | What iOS writes is kept between starts; *Shut down* turns iOS off cleanly |
| **Network** | Internet through QEMU's user network |

Not yet: audio, GPU acceleration, the App Store and Apple ID services.

## Requirements

- Windows 10 (1903 or later) or 11, 64-bit; no admin rights, WSL or Mac needed
- A 4-core CPU or better and 16 GB of RAM (iOS gets 7 GB)
- About **27 GB** free while installing and **14 GB** once installed (see [Disk space](#disk-space))
- iOS 26 also wants a GPU with a Vulkan driver, 8 or more logical processors and about 57 GB free
  while installing; the installer checks these first

## Install

One installer for both versions: `Install-ASoftware.cmd`. Run it from a checkout of `main`, or
from `ASoftware-iOS-*-win64.zip` ([Releases](https://github.com/alpersamur3/asoft-ios/releases)), or
in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
```

It asks two things:

1. **Which iOS:** iOS 16, iOS 26, or both (one QEMU for both, downloaded once).
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

On our PC (i7-13700HX, 24 threads, NVMe SSD, 40 Mbit/s):

| | Download | Disk: peak / after | Time |
| --- | --- | --- | --- |
| iOS 16 | 6.3 GB | 27 GB / 13.6 GB | about 1 h 5 min (measured: 43 min plus the download) |
| iOS 26, fast install (WSL) | 11.4 GB | 49 GB / 24 GB | about 1 h (measured: 48 min of steps, the 10.2 GB from Apple at 52 Mbit/s) |
| iOS 26, without WSL | 11.4 GB | 49 GB / 24 GB | about 1 h 40 min (its steps timed one by one) |
| Both (WSL) | 17.6 GB | 62 GB / 37 GB | about 2 h 5 min |

A new WSL distro for iOS 26 adds 0.9 GB to the download, about 15 minutes (the hfsplus module is
built for your WSL kernel) and about 7 GB on the drive WSL keeps its distros on.

While it runs, the window title shows the step, the time so far and the time left. At the end it
prints what it took and where everything is (also `install-summary.txt`). Everything goes into one
folder: `-Dir`, or `X:\ASoftware` on the drive with the most room (no spaces, for iOS 26).
Stopped, or restarted for WSL? Run it again: it goes on where it stopped.

| Option | Does |
| --- | --- |
| `-Version ios16\|ios26\|both`, `-Linux wsl\|helper` | Answers the two questions |
| `-Dir D:\ASoftware` | The install folder |
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
5. a desktop shortcut

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
| *Save state* / *Saved states…* | Saves the whole machine (about 3 GB, a few seconds), or goes back to one or deletes it |
| Close the window | Saves iOS as it is and quits; the next start resumes it |
| *Shut down* | Turns iOS off cleanly (about 10 s); pressed again, quits at once |

## Disk space

| | While installing | Installed |
| --- | --- | --- |
| iOS image from Apple (IPSW) | 6.2 GB | removed (kept with `-KeepIpsw`) |
| iOS disk | 12.4 GB | 12.9 GB after the first start |
| Room to build it | 7.6 GB | removed |
| App, QEMU, Python, kernel | 0.7 GB | 0.7 GB |
| A saved state (quick boot, *Save state*) | | about 3 GB each |
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
| `scripts/` | Windows launcher, .ipa server, WSL disk build; `dev/` for benchmarks and debugging |
| `assets/` | The logo |

Builds: the kernel and the iOS apps on macOS (`.github/workflows/xnu.yml`, `ios-apps.yml`),
QEMU on Windows ([below](#qemu)), the helper VM on Linux (`installer/helper/build-*.sh`).

### QEMU

iOS 16 and iOS 26 run on one QEMU build: [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/asoft),
branch `asoft` (`ios26` until 2026-11-01; QEMU 11.1 with jprx's research-VM work and our iOS 26
machine), built by [`ios26/scripts/win-build.sh`](ios26/scripts/win-build.sh). `-M virt` boots
iOS 16 as before, `-M vresearch` boots iOS 26. Both installers take its release package
([`asoft-7364c4e`](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)), and both
launchers run it from `work\qemu`.

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

**İki iOS sürümü**

| | iOS 16 | iOS 26 (yeni) |
| --- | --- | --- |
| **Durum** | Hazır: tek satırlık kurulum | Araştırma önizlemesi: aynı kurucu bilgisayarınızda derler (saatler, en çok 57 GB) |
| **Grafik** | İşlemci | **Bilgisayarın ekran kartı**: iOS'un kendi Metal'i, Vulkan üzerinden |
| **iOS** | iPhone X'in 16.7.16'sı | iPhone 16'nın 26.6.2'si, Apple'ın araştırma VM'inin çekirdeğinde |
| **Uygulamalar** | Gerçek web sayfalarıyla Safari, `.ipa` kurma | Sistem uygulamaları, Ayarlar |
| **Hızlı açılış** | Var: iOS saniyeler içinde kaldığı yerden devam eder | Var: iOS saniyeler içinde kaldığı yerden devam eder |
| **Başlangıç** | [Kurulum](#kurulum) | [Kurulum](#kurulum), sonra [`ios26/`](ios26/README.md#turkce) |

Gerçekten ekran kartı mı? [Ölçümler](ios26/README.md#is-it-really-the-gpu). Aşağısı iOS 16 hakkında.

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
| **Hızlı açılış** | Pencereyi kapatmak iOS'u olduğu gibi kaydeder; sonraki açılış saniyeler içinde oradan devam eder |
| **Durumlar** | Duraklatma ve devam, tüm makineyi kaydedip sonra ona dönme; ikisinden sonra da saat kendini düzeltir |
| **Saat** | PC'nizin saat dilimi, bölge biçimi ve 12/24 saat ayarı |
| **Disk** | iOS'un yazdıkları açılışlar arasında saklanır; *Shut down* iOS'u düzgünce kapatır |
| **Ağ** | QEMU'nun kullanıcı ağıyla internet |

Henüz yok: ses, GPU hızlandırma, App Store ve Apple Kimliği hizmetleri.

### Gereksinimler

- Windows 10 (1903 ve sonrası) ya da 11, 64 bit; yönetici izni, WSL ya da Mac gerekmez
- 4 çekirdekli ya da daha iyi bir işlemci ve 16 GB RAM (iOS 7 GB kullanır)
- Kurulum sırasında yaklaşık **27 GB**, kurulumdan sonra **14 GB** boş alan ([Disk alanı](#disk-alanı))
- iOS 26 ayrıca Vulkan sürücülü bir ekran kartı, 8 ya da daha fazla mantıksal işlemci ve kurulum
  sırasında yaklaşık 57 GB boş alan ister; kurucu bunlara önce bakar

### Kurulum

İki sürüm için tek kurucu: `Install-ASoftware.cmd`. `main`'in bir kopyasından, ya da
[Releases](https://github.com/alpersamur3/asoft-ios/releases) sayfasındaki `ASoftware-iOS-*-win64.zip`'ten
çalıştırın; ya da PowerShell'de:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
```

İki şey sorar:

1. **Hangi iOS:** iOS 16, iOS 26 ya da ikisi (ikisine tek QEMU, bir kez indirilir).
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

Bizim bilgisayarda (i7-13700HX, 24 iş parçacığı, NVMe SSD, 40 Mbit/s):

| | İndirme | Disk: en çok / sonra | Süre |
| --- | --- | --- | --- |
| iOS 16 | 6,3 GB | 27 GB / 13,6 GB | yaklaşık 1 sa 5 dk (ölçülen: 43 dk artı indirme) |
| iOS 26, hızlı kurulum (WSL) | 11,4 GB | 49 GB / 24 GB | yaklaşık 1 sa (ölçülen: 48 dk adım süresi; Apple'dan 10,2 GB, 52 Mbit/s) |
| iOS 26, WSL'siz | 11,4 GB | 49 GB / 24 GB | yaklaşık 1 sa 40 dk (adımları tek tek ölçüldü) |
| İkisi (WSL) | 17,6 GB | 62 GB / 37 GB | yaklaşık 2 sa 5 dk |

iOS 26 için yeni bir WSL dağıtımı indirmeye 0,9 GB, süreye yaklaşık 15 dakika (hfsplus modülü WSL
çekirdeğinize göre derlenir) ve WSL'in dağıtımları tuttuğu sürücüde yaklaşık 7 GB ekler.

Çalışırken pencere başlığı adımı, geçen ve kalan süreyi gösterir. Sonunda ne kadar sürdüğünü ve her
şeyin nerede olduğunu yazar (`install-summary.txt`'ye de). Her şey tek klasöre gider: `-Dir`, ya da en
çok boş yeri olan sürücüde `X:\ASoftware` (iOS 26 için boşluksuz). Durdu mu, ya da WSL için yeniden
başlatıldı mı? Yeniden çalıştırın: kaldığı yerden sürer.

| Seçenek | Ne yapar |
| --- | --- |
| `-Version ios16\|ios26\|both`, `-Linux wsl\|helper` | İki soruyu yanıtlar |
| `-Dir D:\ASoftware` | Kurulum klasörü |
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
5. masaüstü kısayolu

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
| *Save state* / *Saved states…* | Tüm makineyi kaydeder (yaklaşık 3 GB, birkaç saniye), ya da birine döner veya siler |
| Pencereyi kapatmak | iOS'u olduğu gibi kaydedip çıkar; sonraki açılış oradan devam eder |
| *Shut down* | iOS'u düzgünce kapatır (yaklaşık 10 sn); ikinci kez basınca hemen çıkar |

### Disk alanı

| | Kurulum sırasında | Kurulumdan sonra |
| --- | --- | --- |
| Apple'dan iOS kalıbı (IPSW) | 6,2 GB | silinir (`-KeepIpsw` ile kalır) |
| iOS diski | 12,4 GB | ilk açılıştan sonra 12,9 GB |
| Kurmak için gereken alan | 7,6 GB | silinir |
| Uygulama, QEMU, Python, çekirdek | 0,7 GB | 0,7 GB |
| Kayıtlı durum (hızlı açılış, *Save state*) | | her biri yaklaşık 3 GB |
| **Toplam** | **yaklaşık 27 GB** | **yaklaşık 13,6 GB**, artı kullandıkça iOS'un sakladıkları |

### QEMU

iOS 16 ve iOS 26 aynı QEMU derlemesinde çalışır: [alpersamur3/qemu-sptm](https://github.com/alpersamur3/qemu-sptm/tree/asoft)
deposunun `asoft` dalı (2026-11-01'e kadar `ios26`; jprx'in araştırma VM'i çalışması ve bizim iOS 26
makinemizle QEMU 11.1), [`ios26/scripts/win-build.sh`](ios26/scripts/win-build.sh) ile derlenir.
`-M virt` iOS 16'yı eskisi gibi, `-M vresearch` iOS 26'yı açar. İki kurulum da onun sürüm paketini alır
([`asoft-7364c4e`](https://github.com/alpersamur3/qemu-sptm/releases/tag/asoft-7364c4e)), iki başlatıcı da
onu `work\qemu` içinden çalıştırır. iOS 16 penceresinin QEMU 11.1.2 üzerindeki sekiz yaması (`qemu/patches/`, 0002-0009)
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
