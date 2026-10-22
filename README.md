<div align="center">

<img src="assets/logo-256.png" width="132" alt="ASoftware iOS">

# ASoftware iOS

**Apple's iOS 16 in a window on your Windows PC.**

![Windows 10/11 x64](https://img.shields.io/badge/Windows-10%20%7C%2011%20x64-0a84ff?style=flat-square)
![iOS 16.7.16](https://img.shields.io/badge/iOS-16.7.16%20(iPhone%20X)-1c1c1e?style=flat-square)
![QEMU 11.1.2](https://img.shields.io/badge/QEMU-11.1.2-ff9f0a?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-30d158?style=flat-square)

English · [Türkçe](#turkce)

</div>

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
| **Input** | Mouse as the touchscreen, the PC keyboard as a hardware keyboard, F1-F4 as Home, Lock and volume |
| **Window** | Phone-shaped, with a side bar in iOS's own dark style; a *Screen off* cover when iOS turns the display off |
| **Clock** | Your PC's time zone, region format and 12/24-hour clock |
| **Power** | Closing the window shuts iOS down cleanly; what iOS writes is kept between starts |
| **Network** | Internet through QEMU's user network |

Not yet: audio, GPU acceleration, the App Store and Apple ID services.

## Requirements

- Windows 10 (1903 or later) or 11, 64-bit; no admin rights, WSL or Mac needed
- A 4-core CPU or better and 16 GB of RAM (iOS gets 7 GB)
- About **27 GB** free while installing and **14 GB** once installed (see [Disk space](#disk-space))

## Install

```powershell
powershell -ExecutionPolicy Bypass -File installer\Install-ASoftware.ps1
```

The installer puts everything into one folder (`%LOCALAPPDATA%\ASoftware iOS` unless you give
`-Dir`) and resumes where it stopped when run again:

1. the app, our QEMU build and Python
2. iOS 16.7.16 for the iPhone X, 6.2 GB from Apple (or `-Ipsw` with one you have)
3. the iOS disk, built from it by a small Linux VM in QEMU (about 25 min)
4. iOS's first start, which sets up its app database once (20-30 min)
5. a desktop shortcut

> [!IMPORTANT]
> The installer is a preview: it does not download our QEMU build yet. Give it one with
> `-QemuDist` (built by `qemu/build-windows.sh` or the `qemu-win` workflow).

## Use

| In the window | Does |
| --- | --- |
| Mouse | Touch: click to tap, drag to swipe |
| **F1** / *Home* | Home (unlock, leave an app) |
| **F2** / *Lock* | Side button: lock, or wake when the screen is off |
| **F3** / **F4** | Volume down / up |
| Other keys | A hardware keyboard |
| *Screenshot* | A PNG in `Pictures\iOS Screenshots` |
| *Install .ipa…* | Installs apps; or drop `.ipa` files into the `ipa` folder |
| Close the window | Shuts iOS down (about 10 s); close again to quit at once |

## Disk space

| | While installing | Installed |
| --- | --- | --- |
| iOS image from Apple (IPSW) | 6.2 GB | removed (kept with `-KeepIpsw`) |
| iOS disk | 13 GB | 13.5 GB after the first start |
| Room to build it | 7.5 GB | removed |
| App, QEMU, Python, kernel | 0.3 GB | 0.3 GB |
| **Total** | **about 27 GB** | **about 14 GB**, plus what iOS stores as you use it |

## How it works

```
Windows ── QEMU (virt, TCG, our patches: side bar, phone-shaped window, power key)
             └─ XNU kernel (ios-sweet + ASoftware patches: virtio disk/net/input, ramfb, AMFI, ...)
                  └─ iOS 16.7.16 userland of the iPhone X, unmodified, on one HFS+ disk
                       └─ asoftinstalld (ours): .ipa installs, time zone, region, clock
```

| Path | What |
| --- | --- |
| `xnu/patches/` | Patches on Apple's XNU: 0001-0081 from ios-sweet, 0082 on for QEMU |
| `qemu/` | Patches on QEMU 11.1.2 and the Windows build script |
| `installer/` | The installer, and the helper VM (arm64 Linux) that builds the iOS disk |
| `tools/` | Device tree, boot payload, QEMU launcher, iOS root builder, disk tool |
| `apps/` | Our iOS programs: `asoftinstalld` and a test app |
| `scripts/` | Windows launcher, .ipa server, WSL disk build; `dev/` for benchmarks and debugging |
| `assets/` | The logo |

Builds: the kernel and the iOS apps on macOS (`.github/workflows/xnu.yml`, `ios-apps.yml`),
QEMU on Windows (`qemu/build-windows.sh` or `qemu-win.yml`), the helper VM on Linux
(`installer/helper/build-*.sh`).

## Credits and licenses

- [ios-sweet](https://github.com/dipa-studio/ios-sweet) by dipa-studio and contributors (MIT): the
  XNU port this project is built on.
- This repository: MIT, see [LICENSE](LICENSE) (dipa-studio and ASoftware).
- `xnu/patches/` modify Apple's XNU (Apple Public Source License 2.0); a kernel built from them is
  under the APSL too. `qemu/patches/` modify QEMU (GPL v2).
- iOS is Apple's and is not distributed here. Apple, iPhone and iOS are trademarks of Apple Inc.

---

<a name="turkce"></a>

<details>
<summary><b>Türkçe</b></summary>

<br>

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
| **Giriş** | Fare dokunmatik ekran, PC klavyesi donanım klavyesi, F1-F4 Home, kilit ve ses |
| **Pencere** | Telefon biçiminde, iOS'un kendi koyu tarzında kenar çubuğu; iOS ekranı kapatınca *Screen off* kapağı |
| **Saat** | PC'nizin saat dilimi, bölge biçimi ve 12/24 saat ayarı |
| **Güç** | Pencereyi kapatmak iOS'u düzgünce kapatır; iOS'un yazdıkları açılışlar arasında saklanır |
| **Ağ** | QEMU'nun kullanıcı ağıyla internet |

Henüz yok: ses, GPU hızlandırma, App Store ve Apple Kimliği hizmetleri.

### Gereksinimler

- Windows 10 (1903 ve sonrası) ya da 11, 64 bit; yönetici izni, WSL ya da Mac gerekmez
- 4 çekirdekli ya da daha iyi bir işlemci ve 16 GB RAM (iOS 7 GB kullanır)
- Kurulum sırasında yaklaşık **27 GB**, kurulumdan sonra **14 GB** boş alan ([Disk alanı](#disk-alanı))

### Kurulum

```powershell
powershell -ExecutionPolicy Bypass -File installer\Install-ASoftware.ps1
```

Kurulum programı her şeyi tek klasöre koyar (`-Dir` verilmezse `%LOCALAPPDATA%\ASoftware iOS`) ve
yeniden çalıştırılınca kaldığı yerden devam eder:

1. uygulama, QEMU derlememiz ve Python
2. iPhone X için iOS 16.7.16, Apple'dan 6,2 GB (ya da elinizdekiyle `-Ipsw`)
3. iOS diski, QEMU'daki küçük bir Linux VM'i tarafından kurulur (yaklaşık 25 dk)
4. iOS'un ilk açılışı; uygulama veritabanını bir kez kurar (20-30 dk)
5. masaüstü kısayolu

> [!IMPORTANT]
> Kurulum programı önizleme sürümünde: QEMU derlememizi henüz kendisi indirmiyor. `-QemuDist`
> ile bir derleme verin (`qemu/build-windows.sh` ya da `qemu-win` workflow'u üretir).

### Kullanım

| Pencerede | Ne yapar |
| --- | --- |
| Fare | Dokunma: tıklama dokunur, sürükleme kaydırır |
| **F1** / *Home* | Ana ekran (kilidi açar, uygulamadan çıkar) |
| **F2** / *Lock* | Yan tuş: kilitler, ekran kapalıyken uyandırır |
| **F3** / **F4** | Ses kıs / aç |
| Diğer tuşlar | Donanım klavyesi |
| *Screenshot* | `Resimler\iOS Screenshots` içine PNG |
| *Install .ipa…* | Uygulama kurar; ya da `.ipa` dosyalarını `ipa` klasörüne bırakın |
| Pencereyi kapatmak | iOS'u kapatır (yaklaşık 10 sn); ikinci kez kapatmak hemen çıkar |

### Disk alanı

| | Kurulum sırasında | Kurulumdan sonra |
| --- | --- | --- |
| Apple'dan iOS kalıbı (IPSW) | 6,2 GB | silinir (`-KeepIpsw` ile kalır) |
| iOS diski | 13 GB | ilk açılıştan sonra 13,5 GB |
| Kurmak için gereken alan | 7,5 GB | silinir |
| Uygulama, QEMU, Python, çekirdek | 0,3 GB | 0,3 GB |
| **Toplam** | **yaklaşık 27 GB** | **yaklaşık 14 GB**, artı kullandıkça iOS'un sakladıkları |

### Emeği geçenler ve lisanslar

- dipa-studio ve katkıda bulunanların [ios-sweet](https://github.com/dipa-studio/ios-sweet) projesi
  (MIT): bu projenin üzerine kurulduğu XNU uyarlaması.
- Bu repo: MIT, bkz. [LICENSE](LICENSE) (dipa-studio ve ASoftware).
- `xnu/patches/` Apple'ın XNU'sunu değiştirir (Apple Public Source License 2.0); bunlardan derlenen
  çekirdek de APSL'dir. `qemu/patches/` QEMU'yu değiştirir (GPL v2).
- iOS Apple'ındır ve burada dağıtılmaz. Apple, iPhone ve iOS, Apple Inc.'in ticari markalarıdır.

</details>
