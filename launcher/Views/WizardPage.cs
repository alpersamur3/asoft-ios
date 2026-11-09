using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>The install: what (iOS 16, iOS 26, watchOS), how and where, a check of this PC (GPU, Setup's own
    /// estimates), then the run with its steps, pause and log. Setup-ASoftware.ps1 does the work.</summary>
    public class WizardPage : UserControl, IRetext
    {
        readonly MainWindow main;
        int page;   // 0 what, 1 how, 2 check, 3 run
        readonly InstallChoice choice = new InstallChoice();
        // (new at each Build: an element has one parent, and the old layout keeps these as its children)
        ContentControl body = new ContentControl();
        StackPanel rail = new StackPanel();
        Estimate estimate;
        string gpuResult = "";          // ok, fail, none, error, ""
        List<string[]> gpuLines = new List<string[]>();
        string wslState = "";           // ok, missing, novirt
        bool estimating, checking;
        TextBox logBox;
        bool showLog;

        public WizardPage(MainWindow main)
        {
            this.main = main;
            var conf = LauncherConfig.Current;
            choice.Dir = !string.IsNullOrEmpty(conf.Install.Dir) ? conf.Install.Dir : DefaultDir();
            choice.Linux = conf.Install.Linux == "helper" ? "helper" : "wsl";
            choice.GpuMode = string.IsNullOrEmpty(conf.Ios26.GpuMode) ? "cloudos" : conf.Ios26.GpuMode;
            choice.GpuDriver = conf.Ios26.GpuDriver;
            choice.Ios16 = !Guests.Installed("ios16");
            choice.Ios26 = false;
            choice.Watch = false;
            if (InstallJob.Current != null && (InstallJob.Current.Running || InstallJob.Current.Result != "")) page = 3;
            Build();
            Task.Run(() => DetectWsl());
        }

        public void Retext() => Build();

        public void Prefer(string os)
        {
            if (page == 3 && InstallJob.Current != null && InstallJob.Current.Running) { Build(); return; }
            if (os != null)
            {
                page = 0;
                choice.Ios16 = os == "ios16";
                choice.Ios26 = os == "ios26";
                choice.Watch = os == "watch";
                if (os == "watch" && Guests.Installed("ios26")) FromIos26Install();
            }
            Build();
        }

        /// <summary>A stopped install: its choice, straight to the check (Setup knows what is done).</summary>
        public void Resume(InstallChoice c)
        {
            choice.Ios16 = c.Ios16; choice.Ios26 = c.Ios26; choice.Watch = c.Watch; choice.Linux = c.Linux ?? "wsl"; choice.Dir = c.Dir;
            if (!string.IsNullOrEmpty(c.GpuMode)) { choice.GpuMode = c.GpuMode; choice.GpuDriver = c.GpuDriver; }
            page = 2;
            Build();
            Check();
        }

        /// <summary>watchOS on an iOS 26 this launcher knows: its install folder.</summary>
        void FromIos26Install()
        {
            var w = Guests.Work("ios26").TrimEnd('\\');
            if (Path.GetFileName(w).Equals("work", StringComparison.OrdinalIgnoreCase)) choice.Dir = Path.GetDirectoryName(w);
            var c26 = Json.ReadObject(AppPaths.Ios26Config);
            if (Json.Str(c26, "LinuxMode") == "helper") choice.Linux = "helper";
        }

        static string DefaultDir()
        {
            var best = DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Fixed && d.IsReady).OrderByDescending(d => d.AvailableFreeSpace).FirstOrDefault();
            return Path.Combine(best?.Name ?? "C:\\", "ASoftware");
        }

        void DetectWsl()
        {
            string st = "missing";
            try
            {
                var r = Guests.Run("wsl.exe", "--status", 15000);
                if (r.Item1 == 0) st = "ok";
                else
                {
                    var l = Guests.Run("wsl.exe", "-l -v", 15000);
                    if (l.Item1 == 0) st = "ok";
                }
                using (var s = new System.Management.ManagementObjectSearcher("SELECT HypervisorPresent FROM Win32_ComputerSystem"))
                foreach (var o in s.Get()) if (!(bool)o["HypervisorPresent"] && st != "ok")
                {
                    using (var p = new System.Management.ManagementObjectSearcher("SELECT VirtualizationFirmwareEnabled FROM Win32_Processor"))
                    foreach (var q in p.Get()) if (q["VirtualizationFirmwareEnabled"] is bool b && !b) st = "novirt";
                }
            }
            catch { }
            wslState = st;
            Dispatcher.BeginInvoke(new Action(() => { if (page == 1) Build(); }));
        }

        bool HelperThere => File.Exists(Path.Combine(AppPaths.Root, "installer", "helper", "out", "Image.gz")) && File.Exists(Path.Combine(AppPaths.Root, "installer", "helper", "out", "initrd.gz"));

        // --- the frame: a rail of steps and the page --------------------------------------------------
        void Build()
        {
            body = new ContentControl();
            rail = new StackPanel();
            logBox = null;
            var root = new Grid { Margin = new Thickness(30, 4, 30, 0) };
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
            root.ColumnDefinitions.Add(new ColumnDefinition());
            var left = new StackPanel { Margin = new Thickness(0, 0, 26, 0) };
            var back = Ui.Btn(L.K("Back"), () => main.GoHome(), "BtnGhost", "\uE72B");
            back.HorizontalAlignment = HorizontalAlignment.Left;
            back.Margin = new Thickness(-8, 0, 0, 14);
            left.Children.Add(back);
            left.Children.Add(new TextBlock { Text = L.K("Installing"), Style = Ui.S("H1"), Margin = new Thickness(0, 0, 0, 18) });
            var names = new[] { L.K("WhatToInstall"), L.K("HowToBuild"), L.K("CheckPc"), L.K("Installing") };
            for (int i = 0; i < names.Length; i++) rail.Children.Add(RailItem(i, names[i]));
            left.Children.Add(rail);
            root.Children.Add(left);
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = body, Padding = new Thickness(0, 0, 8, 26) };
            Grid.SetColumn(sv, 1);
            root.Children.Add(sv);
            Content = root;
            switch (page)
            {
                case 0: What(); break;
                case 1: How(); break;
                case 2: CheckPage(); break;
                default: Run(); break;
            }
        }

        UIElement RailItem(int i, string name)
        {
            bool now = i == page, done = i < page;
            var g = new Grid { Margin = new Thickness(0, 0, 0, 6) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            var dot = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(2) };
            dot.SetResourceReference(Border.BorderBrushProperty, now || done ? "Accent" : "LineStrong");
            dot.SetResourceReference(Border.BackgroundProperty, done ? "Accent" : now ? "AccentSoft" : "Surface");
            var t = new TextBlock { Text = done ? "\uE73E" : (i + 1).ToString(), FontFamily = done ? Ui.F("Icons") : Ui.F("UiFont"), FontSize = done ? 12 : 13, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            t.SetResourceReference(TextBlock.ForegroundProperty, done ? "AccentText" : now ? "Accent" : "Text3");
            dot.Child = t;
            g.Children.Add(dot);
            var n = new TextBlock { Text = name, FontSize = 14, FontWeight = now ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
            n.SetResourceReference(TextBlock.ForegroundProperty, now ? "Text" : "Text2");
            Grid.SetColumn(n, 1);
            g.Children.Add(n);
            var b = new Border { Child = g, Padding = new Thickness(10, 8, 10, 8), CornerRadius = new CornerRadius(12) };
            if (now) b.SetResourceReference(Border.BackgroundProperty, "Surface");
            return b;
        }

        StackPanel Page(string title, string sub)
        {
            var p = new StackPanel { MaxWidth = 900, HorizontalAlignment = HorizontalAlignment.Left };
            p.Children.Add(new TextBlock { Text = title, Style = Ui.S("H2"), FontSize = 22, Margin = new Thickness(0, 46, 0, 4) });
            if (sub != null) p.Children.Add(Ui.Text(sub, "Sub", 0));
            body.Content = p;
            return p;
        }

        StackPanel Nav(params UIElement[] buttons)
        {
            var sp = Ui.Hstack(buttons);
            sp.Margin = new Thickness(0, 22, 0, 0);
            return sp;
        }

        // --- 1. what ------------------------------------------------------------------------------------
        void What()
        {
            var p = Page(L.K("WhatToInstall"), L.T("Each comes from Apple's servers and is built on this PC. You can add the others later.", "Her biri Apple'ın sunucularından gelir ve bu PC'de kurulur. Diğerlerini sonra ekleyebilirsiniz."));
            var cards = new WrapPanel { Margin = new Thickness(0, 18, 0, 0) };
            CheckBox c16 = null, c26 = null, cw = null;
            c16 = OsChoice("ios16", choice.Ios16, L.T("Ready to use: Safari and .ipa apps. No WSL, no administrator.", "Kullanıma hazır: Safari ve .ipa uygulamaları. WSL ve yönetici izni gerekmez."),
                L.T("about 40 min · 6.4 GB download", "yaklaşık 40 dk · 6,4 GB indirme"), v => choice.Ios16 = v);
            c26 = OsChoice("ios26", choice.Ios26, L.T("A research preview drawn by your PC's GPU (Vulkan), Liquid Glass included.", "PC'nizin GPU'suyla (Vulkan) çizilen bir araştırma önizlemesi, Liquid Glass dahil."),
                L.T("1.5–2.5 h · 11 GB download · ~50 GB at its peak", "1,5–2,5 sa · 11 GB indirme · en çok ~50 GB"), v => choice.Ios26 = v);
            cw = OsChoice("watch", choice.Watch, L.T("Apple Watch Series 9 in a drawn case; the crown, the side button. Needs only the base it shares with iOS 26.", "Çizilmiş kasada Apple Watch Series 9; kuron, yan düğme. iOS 26'nın yalnız ortak tabanını ister."),
                L.T("about 35 min · 6.5 GB download · WSL", "yaklaşık 35 dk · 6,5 GB indirme · WSL"), v =>
                {
                    choice.Watch = v;
                    if (v && Guests.Installed("ios26")) FromIos26Install();
                });
            cards.Children.Add(c16); cards.Children.Add(c26); cards.Children.Add(cw);
            p.Children.Add(cards);
            if (Guests.Installed("ios26"))
                p.Children.Add(Ui.Text(L.T("iOS 26 is installed: choosing it again checks it and goes on with what is not done.", "iOS 26 kurulu: yeniden seçmek onu denetler ve bitmeyenlerle devam eder."), "Faint", 12));
            var next = Ui.Btn(L.K("Next"), () => { if (choice.Ios16 || choice.Ios26 || choice.Watch) { page = 1; Build(); } }, "BtnPrimary", "\uE72A");
            p.Children.Add(Nav(next));
        }

        CheckBox OsChoice(string os, bool on, string text, string cost, Action<bool> changed)
        {
            var g = new StackPanel { Width = 250 };
            var head = new Border { Height = 92, CornerRadius = new CornerRadius(12), Background = Theme.OsGradient(os), Margin = new Thickness(0, 0, 0, 12), ClipToBounds = true };
            var hg = new Grid();
            hg.Children.Add(new DeviceGlyph { Os = os, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 6, 8, 0), RenderTransform = new ScaleTransform(0.52, 0.52) });
            hg.Children.Add(new TextBlock { Text = Guests.Name(os), Foreground = Brushes.White, FontSize = 22, FontWeight = FontWeights.SemiBold, FontFamily = Ui.F("DisplayFont"), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(14, 0, 0, 10) });
            head.Child = hg;
            g.Children.Add(head);
            g.Children.Add(new TextBlock { Text = Guests.Detail(os), Style = Ui.S("H3") });
            g.Children.Add(Ui.Text(text, "Sub", 4));
            g.Children.Add(Ui.Text(cost, "Faint", 6));
            if (Guests.Installed(os)) { var t = Ui.Text(L.T("Installed", "Kurulu"), "Faint", 6); t.SetResourceReference(TextBlock.ForegroundProperty, "Good"); g.Children.Add(t); }
            var c = new CheckBox { Style = Ui.S("CheckCard"), Content = g, IsChecked = on, Margin = new Thickness(0, 0, 14, 14) };
            c.Checked += (s, e) => changed(true);
            c.Unchecked += (s, e) => changed(false);
            return c;
        }

        // --- 2. how and where ---------------------------------------------------------------------------
        void How()
        {
            var p = Page(L.K("HowToBuild"), null);
            if (choice.Ios26 || choice.Watch)
            {
                p.Children.Add(new TextBlock { Text = L.K("LinuxTools"), Style = Ui.S("H3"), Margin = new Thickness(0, 18, 0, 8) });
                var wslNote = wslState == "" ? L.T("looking at WSL…", "WSL'e bakılıyor…")
                    : wslState == "ok" ? L.T("WSL 2 is ready on this PC.", "WSL 2 bu PC'de hazır.")
                    : wslState == "novirt" ? L.T("WSL 2 cannot start: virtualization is off in the firmware (BIOS/UEFI).", "WSL 2 çalışamaz: sanallaştırma BIOS/UEFI'de kapalı.")
                    : L.T("WSL is not installed: Windows asks for administrator approval, then a restart; the install goes on after it.", "WSL kurulu değil: Windows yönetici onayı ister, sonra yeniden başlatma; kurulum ardından sürer.");
                var r1 = Radio("linux", L.T("Fast install with WSL", "Hızlı kurulum (WSL)"), wslNote, choice.Linux == "wsl", () => choice.Linux = "wsl", wslState != "novirt");
                var r2 = Radio("linux", L.T("Without WSL", "WSL'siz"), HelperThere ? L.T("A small Linux VM in our QEMU: no administrator, no restart; about an hour slower.", "QEMU'da küçük bir Linux VM: yönetici ve yeniden başlatma gerekmez; yaklaşık bir saat daha yavaş.")
                                                                         : L.T("Not in this copy (installer\\helper\\out: the release package has it).", "Bu kopyada yok (installer\\helper\\out: sürüm paketinde var)."),
                    choice.Linux == "helper", () => choice.Linux = "helper", HelperThere && !choice.Watch);
                if (choice.Watch) p.Children.Add(Ui.Text(L.T("watchOS's installer needs WSL.", "watchOS kurucusu WSL ister."), "Faint", 0));
                p.Children.Add(r1); p.Children.Add(r2);

                p.Children.Add(new TextBlock { Text = L.K("GpuDriver"), Style = Ui.S("H3"), Margin = new Thickness(0, 20, 0, 8) });
                p.Children.Add(Radio("gpu", L.T("Apple's, out of the cloudOS image (recommended)", "Apple'ınki, cloudOS kalıbından (önerilir)"),
                    L.T("The installer takes it out of the files it downloads anyway, with its compiler plugin. No Mac needed.", "Kurucu onu zaten indirdiği dosyalardan, derleyici eklentisiyle birlikte çıkarır. Mac gerekmez."), choice.GpuMode == "cloudos", () => choice.GpuMode = "cloudos"));
                p.Children.Add(Radio("gpu", L.T("A driver bundle I have", "Elimdeki bir sürücü paketi"), string.IsNullOrEmpty(choice.GpuDriver) ? L.T("AppleParavirtGPUMetalIOGPUFamily.bundle, copied as it is.", "AppleParavirtGPUMetalIOGPUFamily.bundle, olduğu gibi kopyalanır.") : choice.GpuDriver,
                    choice.GpuMode == "gpu", () =>
                    {
                        var f = Ui.Pick(L.T("Select AppleParavirtGPUMetalIOGPUFamily.bundle", "AppleParavirtGPUMetalIOGPUFamily.bundle klasörünü seçin"), choice.GpuDriver);
                        if (f != null) { choice.GpuDriver = f; choice.GpuMode = "gpu"; }
                        Build();
                    }));
                p.Children.Add(Radio("gpu", L.T("None (GPU-less)", "Yok (GPU'suz)"), L.T("iOS draws on the CPU: it works, slower; watchOS needs a driver.", "iOS CPU'da çizer: çalışır, daha yavaş; watchOS sürücü ister."),
                    choice.GpuMode == "gpuless", () => choice.GpuMode = "gpuless", !choice.Watch));
            }

            p.Children.Add(new TextBlock { Text = L.K("Location"), Style = Ui.S("H3"), Margin = new Thickness(0, 20, 0, 8) });
            var dir = Ui.Field(choice.Dir, 420);
            var free = Ui.Text("", "Faint", 6);
            void Free()
            {
                var ok = Regex.IsMatch(choice.Dir ?? "", @"^[A-Za-z]:\\[^\s'""`$;&|<>()]+$");
                free.Text = (ok || !(choice.Ios26 || choice.Watch) ? "" : L.T("iOS 26 needs a folder on a drive letter without spaces or shell characters. ", "iOS 26 sürücü harfli, boşluk ve kabuk karakteri içermeyen bir klasör ister. "))
                    + L.Size(Native.FreeBytes(choice.Dir)) + " " + L.T("free on ", "boş: ") + Path.GetPathRoot(choice.Dir);
            }
            dir.TextChanged += (s, e) => { choice.Dir = dir.Text.Trim(); Free(); };
            Free();
            p.Children.Add(Ui.Hstack(dir, Ui.Btn(L.K("Browse"), () =>
            {
                var f = Ui.Pick(L.T("The install folder (the app, and work\\ with the disks)", "Kurulum klasörü (uygulama ve diskleri içeren work\\)"), Directory.Exists(choice.Dir) ? choice.Dir : null);
                if (f != null) { dir.Text = f; }
            })));
            p.Children.Add(free);
            if (choice.Watch && Guests.Installed("ios26"))
                p.Children.Add(Ui.Text(L.T("watchOS is built in iOS 26's install folder.", "watchOS, iOS 26'nın kurulum klasörüne kurulur."), "Faint", 4));

            var back = Ui.Btn(L.K("Back"), () => { page = 0; Build(); });
            var next = Ui.Btn(L.K("Next"), () =>
            {
                if ((choice.Ios26 || choice.Watch) && !Regex.IsMatch(choice.Dir ?? "", @"^[A-Za-z]:\\[^\s'""`$;&|<>()]+$")) { main.Snack(L.T("Choose a folder without spaces for iOS 26.", "iOS 26 için boşluksuz bir klasör seçin."), "warn"); return; }
                if (choice.Watch) choice.Linux = "wsl";
                page = 2; Build(); Check();
            }, "BtnPrimary", "\uE72A");
            p.Children.Add(Nav(back, next));
        }

        RadioButton Radio(string group, string title, string text, bool on, Action pick, bool enabled = true)
        {
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock { Text = title, Style = Ui.S("H3") });
            sp.Children.Add(Ui.Text(text, "Sub", 3));
            var r = new RadioButton { Style = Ui.S("RadioCard"), Content = sp, IsChecked = on, IsEnabled = enabled, Margin = new Thickness(0, 0, 0, 8), GroupName = group, MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Left };
            r.Checked += (s, e) => pick();
            return r;
        }

        // --- 3. this PC: the GPU check and Setup's estimates -----------------------------------------
        async void Check()
        {
            if (checking) return;
            checking = true;
            estimate = null; gpuResult = ""; gpuLines.Clear();
            Build();
            try
            {
                var gpu = (choice.Ios26 || choice.Watch) ? GpuCheck() : Task.FromResult(0);
                estimating = true;
                var est = InstallJob.Estimate(choice);
                await gpu;
                estimate = await est;
            }
            catch (Exception e) { Log.Write("check: " + e); }
            finally { estimating = false; checking = false; }
            if (page == 2) Build();
        }

        /// <summary>gpu-check.cs in a process of its own (this exe, -gpu-check): a driver that crashes takes only that one.</summary>
        async Task<int> GpuCheck()
        {
            var log = Path.Combine(AppPaths.LocalData, "logs", "gpu-check.log");
            var r = await Task.Run(() => Guests.Run(Process.GetCurrentProcess().MainModule.FileName, "-gpu-check", 60000));
            Directory.CreateDirectory(Path.GetDirectoryName(log));
            File.WriteAllText(log, $"# {DateTime.Now:s} exit {r.Item1}\r\n" + r.Item2, Encoding.UTF8);
            gpuLines = r.Item2.Replace("\r", "").Split('\n').Where(l => l.Contains("|")).Select(l => l.Split('|')).ToList();
            var res = gpuLines.LastOrDefault(l => l[0] == "result");
            gpuResult = res != null ? res[1] : "error";
            if (page == 2) Build();
            return r.Item1;
        }

        void CheckPage()
        {
            var p = Page(L.K("CheckPc"), L.T("What this PC has, and what the install takes here (Setup's own estimate, its times scaled to this PC).", "Bu PC'de ne var ve kurulum burada ne gerektirir (Setup'ın kendi tahmini, süreleri bu PC'ye göre ölçeklenir)."));
            if (choice.Ios26 || choice.Watch) p.Children.Add(GpuBox());
            p.Children.Add(EstimateBox());
            bool blocked = estimate == null || estimate.Stops.Count > 0 || gpuResult == "none" || gpuResult == "fail" && choice.GpuMode != "gpuless";
            var back = Ui.Btn(L.K("Back"), () => { page = 1; Build(); });
            var again = Ui.Btn(L.T("Check again", "Yeniden denetle"), Check, "Btn", "\uE72C");
            var go = Ui.Btn(L.K("StartInstall"), StartInstall, "BtnPrimary", "\uE768");
            go.IsEnabled = !checking && !blocked && !(InstallJob.Current?.Running ?? false);
            p.Children.Add(Nav(back, again, go));
        }

        UIElement GpuBox()
        {
            var sp = new StackPanel();
            string tone, head, text;
            switch (gpuResult)
            {
                case "": tone = "Info"; head = L.T("Checking the GPU…", "GPU denetleniyor…"); text = L.T("About a second: a Vulkan device, and whether its driver takes the guest's memory as iOS 26 needs.", "Yaklaşık bir saniye: bir Vulkan aygıtı ve sürücüsünün konuğun belleğini iOS 26'nın istediği gibi alıp almadığı."); break;
                case "ok": tone = "Good"; head = L.T("The GPU can draw iOS 26", "GPU iOS 26'yı çizebilir"); text = L.T("Its Vulkan driver imports the guest's memory and its writes reach it.", "Vulkan sürücüsü konuğun belleğini alıyor ve yazdıkları ona ulaşıyor."); break;
                case "fail": tone = "Bad"; head = L.T("This GPU's driver cannot draw iOS 26 yet", "Bu GPU'nun sürücüsü iOS 26'yı henüz çizemiyor");
                    text = L.T("Its Vulkan driver refuses the guest's memory the way iOS 26 hands it over (an external host allocation of a mapped section). Updating the GPU driver may help; else install iOS 16, or iOS 26 with no GPU driver (slower). The log below says which test failed: it helps us if you send it.",
                               "Vulkan sürücüsü konuğun belleğini iOS 26'nın verdiği biçimde (eşlenmiş bir bölümün dış ana bellek olarak alınması) kabul etmiyor. GPU sürücüsünü güncellemek işe yarayabilir; yoksa iOS 16'yı ya da GPU sürücüsüz iOS 26'yı (daha yavaş) kurun. Aşağıdaki log hangi denemenin başarısız olduğunu söyler: bize gönderirseniz yardımı olur."); break;
                case "none": tone = "Bad"; head = L.T("No Vulkan here", "Burada Vulkan yok");
                    text = L.T("iOS 26 draws through Vulkan and this PC has no Vulkan driver or device: install your GPU maker's driver (NVIDIA, AMD, Intel), then check again. iOS 16 needs none.",
                               "iOS 26 Vulkan ile çizer ve bu PC'de Vulkan sürücüsü ya da aygıtı yok: GPU üreticinizin sürücüsünü (NVIDIA, AMD, Intel) kurup yeniden denetleyin. iOS 16 istemez."); break;
                default: tone = "Warn"; head = L.T("The GPU check did not finish", "GPU denetimi bitmedi"); text = L.T("It may have crashed in the driver. The log says how far it got.", "Sürücüde çökmüş olabilir. Log ne kadar ilerlediğini söyler."); break;
            }
            sp.Children.Add(StatusHead(tone, gpuResult == "ok" ? "\uE73E" : gpuResult == "" ? "\uE9D9" : "\uE7BA", head));
            sp.Children.Add(Ui.Text(text, "Sub", 6));
            foreach (var l in gpuLines.Where(l => l[0] == "gpu" && l.Length >= 9))
            {
                bool used = l[1] == "used", ok = l[8] == "ok";
                var row = Ui.Text((used ? "● " : "○ ") + $"{l[2]} · {l[3]} · {l[4]} · Vulkan {l[5]} · " + (ok ? L.T("ok", "uygun") : l[8]), "Faint", 4);
                sp.Children.Add(row);
            }
            if (gpuResult != "" && gpuResult != "ok")
            {
                var b = Ui.Btn(L.T("Open the log", "Logu aç"), () => MainWindow.Open(Path.Combine(AppPaths.LocalData, "logs", "gpu-check.log")), "Btn", "\uE8A5");
                b.HorizontalAlignment = HorizontalAlignment.Left; b.Margin = new Thickness(0, 10, 0, 0);
                sp.Children.Add(b);
            }
            return Box(tone, sp);
        }

        UIElement EstimateBox()
        {
            var sp = new StackPanel();
            if (estimate == null)
            {
                sp.Children.Add(StatusHead("Info", "\uE9D9", L.T("Working out what it takes… (it measures Apple's CDN with 10 MB)", "Ne gerektirdiği hesaplanıyor… (Apple'ın CDN'ini 10 MB ile ölçer)")));
                return Box("Info", sp);
            }
            if (estimate.Plan.Count == 0)
            {
                sp.Children.Add(StatusHead("Bad", "\uEA39", L.T("Setup gave no estimate", "Setup tahmin vermedi")));
                sp.Children.Add(Ui.Text(string.Join("\n", estimate.Output.Where(l => l.Trim() != "").Reverse().Take(8).Reverse()), "Faint", 6));
                return Box("Bad", sp);
            }
            sp.Children.Add(new TextBlock { Text = L.K("Estimate"), Style = Ui.S("H3") });
            var grid = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            for (int i = 0; i < 5; i++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = i == 0 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
            int row = 0;
            void Cell(string t, int col, bool head = false, bool bold = false)
            {
                var tb = new TextBlock { Text = t, Margin = new Thickness(col == 0 ? 0 : 22, 4, 0, 4), FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, HorizontalAlignment = col == 0 ? HorizontalAlignment.Left : HorizontalAlignment.Right };
                tb.SetResourceReference(TextBlock.ForegroundProperty, head ? "Text3" : "Text");
                tb.FontSize = head ? 12 : 13;
                Grid.SetRow(tb, row); Grid.SetColumn(tb, col);
                grid.Children.Add(tb);
            }
            grid.RowDefinitions.Add(new RowDefinition());
            Cell("", 0, true); Cell(L.K("Download"), 1, true); Cell(L.K("DiskPeak"), 2, true); Cell(L.K("DiskAfter"), 3, true); Cell(L.K("Time"), 4, true);
            foreach (var os in new[] { "ios16", "ios26", "watch" })
            {
                var steps = estimate.Plan.Where(s => s.Os == os).ToList();
                if (steps.Count == 0) continue;
                row++; grid.RowDefinitions.Add(new RowDefinition());
                var key = os == "ios26" ? "ios26-" + choice.Linux : os;
                estimate.Options.TryGetValue(key, out var o);
                int done = steps.Count(s => s.State == "skip");
                Cell(Head(os) + (done > 0 ? L.T($"  ({done} of {steps.Count} steps done)", $"  ({steps.Count} adımın {done}'i bitti)") : ""), 0);
                Cell(L.Size(steps.Where(s => s.State != "skip").Sum(s => s.Download)), 1);
                Cell(o != null ? L.Size(o[2]) : "", 2);
                Cell(o != null ? L.Size(o[3]) : "", 3);
                Cell("~" + L.Duration(steps.Where(s => s.State != "skip").Sum(s => s.Seconds)), 4);
            }
            row++; grid.RowDefinitions.Add(new RowDefinition());
            Cell(L.T("All", "Hepsi"), 0, false, true); Cell(L.Size(estimate.Download), 1, false, true); Cell(L.Size(estimate.Peak), 2, false, true); Cell(L.Size(estimate.After), 3, false, true); Cell("~" + L.Duration(estimate.Seconds), 4, false, true);
            sp.Children.Add(grid);
            sp.Children.Add(Ui.Text(L.T($"{L.Size(estimate.Free)} free on {Path.GetPathRoot(choice.Dir)}; {estimate.Bandwidth}.", $"{Path.GetPathRoot(choice.Dir)} üzerinde {L.Size(estimate.Free)} boş; {estimate.Bandwidth}."), "Faint", 8));
            foreach (var w in estimate.Warnings) sp.Children.Add(Line("Warn", "\uE7BA", w));
            foreach (var s in estimate.Stops) sp.Children.Add(Line("Bad", "\uEA39", s));
            return Box(estimate.Stops.Count > 0 ? "Bad" : estimate.Warnings.Count > 0 ? "Warn" : "Line", sp);
        }

        // watchOS without iOS 26: its "ios26" steps are the base they share
        string Head(string os) => os == "ios26" && !choice.Ios26 ? L.T("The base watchOS shares with iOS 26", "watchOS'un iOS 26 ile paylaştığı taban") : Guests.Name(os);

        static UIElement Line(string tone, string icon, string text)
        {
            var g = new Grid { Margin = new Thickness(0, 8, 0, 0) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            var ic = Ui.Icon(icon, 13, tone); ic.VerticalAlignment = VerticalAlignment.Top; ic.Margin = new Thickness(0, 2, 10, 0);
            g.Children.Add(ic);
            var t = Ui.Text(text, "Sub"); Grid.SetColumn(t, 1);
            g.Children.Add(t);
            return g;
        }

        static UIElement StatusHead(string tone, string icon, string text)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Ui.Icon(icon, 16, tone));
            sp.Children.Add(new TextBlock { Text = text, Style = Ui.S("H3"), Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            return sp;
        }

        static Border Box(string tone, UIElement child)
        {
            var b = new Border { CornerRadius = new CornerRadius(14), Padding = new Thickness(18, 16, 18, 16), Margin = new Thickness(0, 16, 0, 0), BorderThickness = new Thickness(1), Child = child };
            b.SetResourceReference(Border.BackgroundProperty, "Surface");
            b.SetResourceReference(Border.BorderBrushProperty, tone);
            return b;
        }

        void StartInstall()
        {
            try
            {
                InstallJob.Start(new InstallChoice { Ios16 = choice.Ios16, Ios26 = choice.Ios26, Watch = choice.Watch, Linux = choice.Linux, Dir = choice.Dir, GpuMode = choice.GpuMode, GpuDriver = choice.GpuDriver },
                    estimate?.Plan.Select(s => new PlanStep { Os = s.Os, Id = s.Id, Title = s.Title, Seconds = s.Seconds, Download = s.Download, State = s.State }).ToList());
                page = 3;
                Build();
            }
            catch (Exception e) { Dialog.Show(main, L.T("Not started", "Başlamadı"), e.Message, L.K("OK")); }
        }

        // --- 4. the run ---------------------------------------------------------------------------------
        TextBlock runHead, runSub, runNow;
        ProgressBar runBar;
        StackPanel runSteps;

        void Run()
        {
            var j = InstallJob.Current;
            var p = Page(L.K("Installing"), null);
            if (j == null) { p.Children.Add(Ui.Text(L.T("No install runs.", "Çalışan kurulum yok."), "Sub")); return; }
            runHead = new TextBlock { Style = Ui.S("H3"), FontSize = 15, Margin = new Thickness(0, 14, 0, 0) };
            runSub = Ui.Text("", "Sub", 2);
            runBar = new ProgressBar { Style = Ui.S("Bar"), Height = 8, Maximum = 1000, Margin = new Thickness(0, 12, 0, 0) };
            runNow = Ui.Text("", "Faint", 8);
            p.Children.Add(runHead); p.Children.Add(runSub); p.Children.Add(runBar); p.Children.Add(runNow);
            var buttons = new List<UIElement>();
            if (j.Running)
            {
                var pause = Ui.Btn(L.K("PauseAfterStep"), () => { j.Pause(); Tick(); }, "Btn", "\uE769");
                pause.IsEnabled = !j.PauseAsked;
                buttons.Add(pause);
                buttons.Add(Ui.Btn(L.K("StopNow"), () =>
                {
                    if (Dialog.Show(main, L.T("Stop the install now?", "Kurulum şimdi durdurulsun mu?"),
                            L.T("The step it is in stops half way and starts over when you resume. Pause after this step is gentler.", "İçinde olduğu adım yarıda kalır ve sürdürünce baştan başlar. Bu adımdan sonra duraklatmak daha nazik."),
                            L.K("StopNow"), L.K("Cancel")) == 0) j.StopNow();
                }, "BtnDanger", "\uE71A"));
            }
            else
            {
                if (j.Result == "paused" || j.Result == "failed")
                    buttons.Add(Ui.Btn(L.K("Resume"), () => { Resume(j.Choice); }, "BtnPrimary", "\uE768"));
                buttons.Add(Ui.Btn(L.T("Back to home", "Ana sayfaya dön"), () => main.GoHome(), j.Result == "done" ? "BtnPrimary" : "Btn", "\uE80F"));
                if (j.Result == "failed")
                    buttons.Add(Ui.Btn(L.T("Report this", "Bunu bildir"), () => main.OpenReport("install", L.T("The install stopped", "Kurulum durdu"), j.Message), "BtnGhost", "\uEBE8"));
            }
            buttons.Add(Ui.Btn(L.K("ShowLog"), () => { showLog = !showLog; Build(); }, "BtnGhost", "\uE9F9"));
            p.Children.Add(Nav(buttons.ToArray()));
            runSteps = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
            p.Children.Add(runSteps);
            if (showLog)
            {
                logBox = new TextBox { Style = Ui.S("Field"), IsReadOnly = true, FontFamily = Ui.F("Mono"), FontSize = 11.5, Height = 320, AcceptsReturn = true, TextWrapping = TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalContentAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 14, 0, 0) };
                p.Children.Insert(p.Children.IndexOf(runSteps), logBox);
                var open = Ui.Btn(L.T("Open the log file", "Log dosyasını aç"), () => MainWindow.Open(j.Runner.LogFile), "BtnGhost", "\uE8A5");
                open.HorizontalAlignment = HorizontalAlignment.Left;
                p.Children.Insert(p.Children.IndexOf(runSteps), open);
            }
            Tick();
        }

        int lastStepsHash;
        public void Tick()
        {
            if (page != 3 || runHead == null) return;
            var j = InstallJob.Current;
            if (j == null) return;
            var left = j.SecondsLeft();
            var el = DateTime.Now - j.Started;
            switch (j.Result)
            {
                case "done": runHead.Text = L.T("Installed", "Kuruldu"); runSub.Text = L.T($"In {L.Duration(el.TotalSeconds)}. Start it from its card.", $"{L.Duration(el.TotalSeconds)} sürdü. Kartından başlatın."); break;
                case "paused": runHead.Text = L.T("Paused", "Duraklatıldı"); runSub.Text = L.T("Resume goes on from the next step.", "Sürdür bir sonraki adımdan devam eder."); break;
                case "restart": runHead.Text = L.T("Restart Windows", "Windows'u yeniden başlatın"); runSub.Text = L.T("WSL is installed; after the restart open ASoftware: the install goes on.", "WSL kuruldu; yeniden başlattıktan sonra ASoftware'i açın: kurulum sürer."); break;
                case "failed": runHead.Text = L.T("The install stopped", "Kurulum durdu"); runSub.Text = j.Message + "  " + L.T("Fix the cause and resume: it goes on from this step.", "Nedenini giderip sürdürün: bu adımdan devam eder."); break;
                default:
                    runHead.Text = L.T("Installing ", "Kuruluyor: ") + string.Join(" + ", new[] { j.Choice.Ios16 ? "iOS 16" : null, j.Choice.Ios26 ? "iOS 26" : null, j.Choice.Watch ? "watchOS" : null }.Where(x => x != null));
                    runSub.Text = L.T($"{L.Duration(el.TotalSeconds)} so far · about {L.Duration(left)} left", $"{L.Duration(el.TotalSeconds)} geçti · yaklaşık {L.Duration(left)} kaldı") + (j.PauseAsked ? L.T(" · pausing after this step", " · bu adımdan sonra duraklayacak") : "");
                    break;
            }
            runHead.SetResourceReference(TextBlock.ForegroundProperty, j.Result == "failed" ? "Bad" : j.Result == "done" ? "Good" : "Text");
            runBar.Value = 1000 * (j.Result == "done" ? 1 : j.Fraction());
            var now = j.Now;
            runNow.Text = now == null ? "" : $"{Guests.Name(now.Os)} · {now.Id}: " + (now.Text != "" ? now.Text : now.Title);
            // the steps, rebuilt when they change
            int h = string.Join(",", j.Plan.Select(s => s.State + s.Id + s.Pct + (s.State == "running" ? ((int)(DateTime.Now - s.Started).TotalMinutes).ToString() : ""))).GetHashCode();
            if (h != lastStepsHash || runSteps.Children.Count == 0)
            {
                lastStepsHash = h;
                runSteps.Children.Clear();
                foreach (var os in new[] { "ios16", "ios26", "watch" })
                {
                    var steps = j.Plan.Where(s => s.Os == os).ToList();
                    if (steps.Count == 0) continue;
                    var rows = steps.Select(s => StepRow(s)).ToArray();
                    runSteps.Children.Add(Ui.Group(Head(os), rows));
                }
            }
            if (logBox != null && j.Runner != null)
            {
                var lines = j.Runner.Lines;
                logBox.Text = string.Join("\r\n", lines.Skip(Math.Max(0, lines.Count - 400)));
                logBox.ScrollToEnd();
            }
        }

        UIElement StepRow(PlanStep s)
        {
            string icon = s.State == "done" ? "\uE73E" : s.State == "skip" ? "\uE73E" : s.State == "running" ? "\uE768" : s.State == "fail" ? "\uEA39" : "\uE739";
            string tone = s.State == "done" ? "Good" : s.State == "skip" ? "Text3" : s.State == "running" ? "Accent" : s.State == "fail" ? "Bad" : "Text3";
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(Ui.Icon(icon, 13, tone));
            var t = new TextBlock { Text = s.Title, Margin = new Thickness(12, 0, 0, 0), FontWeight = s.State == "running" ? FontWeights.SemiBold : FontWeights.Normal, TextTrimming = TextTrimming.CharacterEllipsis };
            t.SetResourceReference(TextBlock.ForegroundProperty, s.State == "skip" || s.State == "pending" ? "Text2" : "Text");
            Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var right = s.State == "skip" ? L.T("done before", "önceden bitti") : s.State == "done" ? L.T("done", "bitti") : s.State == "running" ? (s.Pct >= 0 ? s.Pct + " %" : "~" + L.Duration(Math.Max(0, s.Seconds - (DateTime.Now - s.Started).TotalSeconds))) : s.State == "fail" ? L.T("failed", "başarısız") : "~" + L.Duration(s.Seconds);
            var rt = Ui.Text(right, "Faint"); rt.Margin = new Thickness(16, 0, 0, 0);
            Grid.SetColumn(rt, 2);
            g.Children.Add(rt);
            var b = Ui.Row(null, null, g);
            b.Padding = new Thickness(16, 8, 16, 8);
            return b;
        }
    }
}
