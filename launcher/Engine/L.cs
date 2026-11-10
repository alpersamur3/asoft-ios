using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;

namespace ASoftware.Engine
{
    /// <summary>English and Turkish. XAML binds {Binding [Key], Source={x:Static e:L.I}}; code calls L.T(en, tr).</summary>
    public sealed class L : INotifyPropertyChanged
    {
        public static readonly L I = new L();
        public event PropertyChangedEventHandler PropertyChanged;
        public static event Action Changed;

        static string lang = "";       // set by Set() at the start
        public static string Lang => lang == "tr" ? "tr" : "en";
        public static bool Tr => lang == "tr";

        /// <summary>auto (the PC's), en or tr.</summary>
        public static void Set(string choice)
        {
            string l = choice;
            if (l != "en" && l != "tr")
                l = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr" || CultureInfo.CurrentCulture.TwoLetterISOLanguageName == "tr" ? "tr" : "en";
            if (l == lang) return;
            lang = l;
            // numbers and dates as the language writes them (1.5 GB / 1,5 GB)
            var ci = new CultureInfo(l == "tr" ? "tr-TR" : "en-US");
            System.Threading.Thread.CurrentThread.CurrentCulture = ci;
            CultureInfo.DefaultThreadCurrentCulture = ci;
            I.PropertyChanged?.Invoke(I, new PropertyChangedEventArgs("Item[]"));
            Changed?.Invoke();
        }

        public static string T(string en, string tr) => lang == "tr" ? tr : en;

        public string this[string key]
        {
            get
            {
                if (S.TryGetValue(key, out var v)) return lang == "tr" ? v[1] : v[0];
                return key;
            }
        }

        public static string K(string key) => I[key];

        // XAML's fixed texts
        static readonly Dictionary<string, string[]> S = new Dictionary<string, string[]>
        {
            ["Tagline"] = new[] { "iOS, watchOS and visionOS on your PC, drawn by its GPU", "iOS, watchOS ve visionOS bilgisayarınızda, GPU'suyla çizilir" },
            ["Install"] = new[] { "Install", "Kur" },
            ["InstallDots"] = new[] { "Add a system", "Sistem ekle" },
            ["Start"] = new[] { "Start", "Başlat" },
            ["Resume"] = new[] { "Resume", "Devam et" },
            ["SaveClose"] = new[] { "Save and close", "Kaydet ve kapat" },
            ["TurnOff"] = new[] { "Turn off", "Kapat" },
            ["More"] = new[] { "More", "Diğer" },
            ["Back"] = new[] { "Back", "Geri" },
            ["Settings"] = new[] { "Settings", "Ayarlar" },
            ["Saves"] = new[] { "Saves", "Kayıtlar" },
            ["Apps"] = new[] { "Apps", "Uygulamalar" },
            ["Logs"] = new[] { "Logs", "Kayıt dosyaları" },
            ["Cancel"] = new[] { "Cancel", "Vazgeç" },
            ["OK"] = new[] { "OK", "Tamam" },
            ["Close"] = new[] { "Close", "Kapat" },
            ["Next"] = new[] { "Next", "İleri" },
            ["Browse"] = new[] { "Browse…", "Gözat…" },
            ["Refresh"] = new[] { "Refresh", "Yenile" },
            ["Load"] = new[] { "Load", "Yükle" },
            ["GoBack"] = new[] { "Go back", "Geri dön" },
            ["Delete"] = new[] { "Delete", "Sil" },
            ["Rename"] = new[] { "Rename", "Yeniden adlandır" },
            ["SaveNow"] = new[] { "Save now", "Şimdi kaydet" },
            ["Vcpus"] = new[] { "Processors (vCPUs)", "İşlemci (vCPU)" },
            ["Ram"] = new[] { "Memory (RAM)", "Bellek (RAM)" },
            ["Network"] = new[] { "Network", "Ağ" },
            ["Wallpaper"] = new[] { "Wallpaper", "Duvar kâğıdı" },
            ["Aod"] = new[] { "Always On Display", "Her Zaman Açık Ekran" },
            ["Sharpness"] = new[] { "Sharper scaling", "Keskin ölçekleme" },
            ["TimeRegion"] = new[] { "Time zone, region and clock", "Saat dilimi, bölge ve saat" },
            ["DiskMode"] = new[] { "Disk", "Disk" },
            ["QuickBoot"] = new[] { "Quick boot", "Hızlı açılış" },
            ["GpuDriver"] = new[] { "GPU driver", "GPU sürücüsü" },
            ["Folders"] = new[] { "Folders", "Klasörler" },
            ["WorkFolder"] = new[] { "Work folder", "Çalışma klasörü" },
            ["AppFolder"] = new[] { "App folder", "Uygulama klasörü" },
            ["InstallIpa"] = new[] { "Install an .ipa…", "Bir .ipa kur…" },
            ["OpenIpaFolder"] = new[] { "Open the .ipa folder", ".ipa klasörünü aç" },
            ["OpenRunFolder"] = new[] { "Open the run folder", "Çalışma klasörünü aç" },
            ["OpenInstallLogs"] = new[] { "Open the install logs", "Kurulum loglarını aç" },
            ["PackLogs"] = new[] { "Pack logs (.zip)", "Logları paketle (.zip)" },
            ["Language"] = new[] { "Language", "Dil" },
            ["Theme"] = new[] { "Theme", "Tema" },
            ["System"] = new[] { "Same as Windows", "Windows ile aynı" },
            ["Dark"] = new[] { "Dark", "Koyu" },
            ["Light"] = new[] { "Light", "Açık" },
            ["CloseToTray"] = new[] { "Keep running in the tray when closed", "Kapatınca bildirim alanında çalışmaya devam et" },
            ["CheckUpdates"] = new[] { "Look for new versions on GitHub", "GitHub'da yeni sürüm ara" },
            ["About"] = new[] { "About", "Hakkında" },
            ["Open"] = new[] { "Open", "Aç" },
            ["Quit"] = new[] { "Quit", "Çık" },
            ["WhatToInstall"] = new[] { "What to install", "Ne kurulsun" },
            ["HowToBuild"] = new[] { "How and where", "Nasıl ve nereye" },
            ["CheckPc"] = new[] { "This PC", "Bu PC" },
            ["Installing"] = new[] { "Install", "Kurulum" },
            ["PauseAfterStep"] = new[] { "Pause after this step", "Bu adımdan sonra duraklat" },
            ["StopNow"] = new[] { "Stop now", "Şimdi durdur" },
            ["ShowLog"] = new[] { "Log", "Log" },
            ["Done"] = new[] { "Done", "Bitti" },
            ["Location"] = new[] { "Install folder", "Kurulum klasörü" },
            ["LinuxTools"] = new[] { "iOS 26's Linux tools", "iOS 26'nın Linux araçları" },
            ["GpuCheck"] = new[] { "GPU check", "GPU denetimi" },
            ["Estimate"] = new[] { "What it takes", "Ne gerektirir" },
            ["Download"] = new[] { "Download", "İndirme" },
            ["DiskPeak"] = new[] { "Disk at the peak", "En çok disk" },
            ["DiskAfter"] = new[] { "Disk after", "Sonra disk" },
            ["Time"] = new[] { "Time", "Süre" },
            ["StartInstall"] = new[] { "Start the install", "Kurulumu başlat" },
            ["Locate"] = new[] { "Use an existing install…", "Var olan bir kurulumu kullan…" },
            ["UpdateAvailable"] = new[] { "A new version is out", "Yeni bir sürüm çıktı" },
            ["ReleasePage"] = new[] { "Release page", "Sürüm sayfası" },
            ["Dismiss"] = new[] { "Dismiss", "Gizle" },
            ["ApplyReinstall"] = new[] { "Rebuild with it", "Bununla yeniden kur" },
        };

        public static string Size(double bytes)
        {
            if (bytes < 1e6) return "< 1 MB";
            if (bytes < 1e9) return (bytes / 1e6).ToString("N0") + " MB";
            return (bytes / 1e9).ToString("N1") + " GB";
        }

        public static string Duration(double s)
        {
            if (s < 60) return T("< 1 min", "< 1 dk");
            long m = (long)Math.Round(s / 60);
            if (m < 60) return m + " " + T("min", "dk");
            long h = m / 60; m -= 60 * h;
            return m == 0 ? h + " " + T("h", "sa") : h + " " + T("h", "sa") + " " + m + " " + T("min", "dk");
        }
    }
}
