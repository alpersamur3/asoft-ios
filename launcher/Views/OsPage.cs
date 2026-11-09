using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>One OS's page (the card's More): its settings, saves, apps and logs.</summary>
    public class OsPage : UserControl, IRetext
    {
        readonly string os;
        readonly MainWindow main;
        string tab;
        // (new at each Build: an element has one parent, and the old layout keeps these as its children)
        ContentControl body;
        TextBlock state;
        StackPanel actions;
        OsConfig C => Guests.Cfg(os);

        public OsPage(string os, MainWindow main, string tab)
        {
            this.os = os; this.main = main; this.tab = tab ?? "settings";
            Build();
        }

        public void Retext() => Build();

        void Build()
        {
            body = new ContentControl();
            state = new TextBlock { Foreground = Brushes.White, FontSize = 13, Opacity = 0.9 };
            actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Bottom };
            var root = new Grid { Margin = new Thickness(30, 4, 30, 0) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition());

            // the header, in the card's colours
            var head = new Border { CornerRadius = new CornerRadius(20), Background = Theme.OsGradient(os), Height = 150, ClipToBounds = true };
            var hg = new Grid();
            hg.Children.Add(new System.Windows.Shapes.Ellipse { Width = 300, Height = 300, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -140, -60, 0), Fill = new SolidColorBrush(Color.FromArgb(0x18, 255, 255, 255)) });
            hg.Children.Add(new DeviceGlyph { Os = os, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 10, 40, 0), RenderTransform = new ScaleTransform(0.78, 0.78) });
            var back = new Button { Style = Ui.S("BtnIcon"), Content = "\uE72B", Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(12, 12, 0, 0), ToolTip = L.K("Back") };
            back.Click += (s, e) => main.GoHome();
            hg.Children.Add(back);
            var title = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(24, 0, 0, 18) };
            title.Children.Add(new TextBlock { Text = Guests.Name(os), FontFamily = Ui.F("DisplayFont"), FontSize = 30, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
            title.Children.Add(new TextBlock { Text = Guests.Detail(os), Foreground = Brushes.White, Opacity = 0.85, FontSize = 12.5 });
            title.Children.Add(state);
            state.Margin = new Thickness(0, 6, 0, 0);
            hg.Children.Add(title);
            actions.HorizontalAlignment = HorizontalAlignment.Right;
            actions.Margin = new Thickness(0, 0, 200, 18);
            hg.Children.Add(actions);
            head.Child = hg;
            // (the circle behind the device must not show past the header's round corners)
            hg.SizeChanged += (s, e) => hg.Clip = new RectangleGeometry(new Rect(0, 0, e.NewSize.Width, e.NewSize.Height), 20, 20);
            root.Children.Add(head);

            // the tabs
            var tabs = Ui.Seg(new[] { ("settings", L.K("Settings")), ("saves", L.K("Saves")), ("apps", L.K("Apps")), ("logs", L.K("Logs")) }, tab, t => { tab = t; Show(); });
            tabs.Margin = new Thickness(0, 18, 0, 14);
            Grid.SetRow(tabs, 1);
            root.Children.Add(tabs);

            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = body, Padding = new Thickness(0, 0, 6, 24) };
            Grid.SetRow(sv, 2);
            root.Children.Add(sv);
            Content = root;
            Refresh();
            Show();
        }

        /// <summary>The header's state and actions (also from the main window's poll).</summary>
        public void Refresh()
        {
            actions.Children.Clear();
            Machines.Runs.TryGetValue(os, out var run);
            bool on = run != null && run.QemuPid != 0 && Native.Alive(run.QemuPid);
            if (on)
            {
                state.Text = (run.Busy == "saving" ? L.T("Saving…", "Kaydediliyor…") : run.Busy == "stopping" ? L.T("Turning off…", "Kapatılıyor…") : L.T("Running", "Çalışıyor")) + $" · {run.Smp} vCPU · {run.RamMiB / 1024.0:0.#} GB";
                if (run.Disk != "" && run.QuickBoot) actions.Children.Add(Glass(Ui.Btn(L.K("SaveClose"), () => main.SaveClose(os), "Btn", "\uE74E"), "page-saveclose"));
                var off = Glass(Ui.Btn(L.K("TurnOff"), () => main.TurnOff(os), "Btn", "\uE7E8"), "page-turnoff"); off.Margin = new Thickness(8, 0, 0, 0);
                actions.Children.Add(off);
            }
            else if (Guests.Installed(os))
            {
                state.Text = L.T("Ready", "Hazır");
                actions.Children.Add(Glass(Ui.Btn(L.K("Start"), () => main.StartOs(os), "Btn", "\uE768"), "page-start"));
            }
            else state.Text = L.T("Not installed", "Kurulu değil");
            if (tab == "saves" && savesShownRunning != on) ShowSaves();
        }

        public void Tick() { }

        /// <summary>A button on the coloured header: white glass.</summary>
        static Button Glass(Button b, string id)
        {
            b.Background = new SolidColorBrush(Color.FromArgb(0x38, 255, 255, 255));
            b.BorderBrush = new SolidColorBrush(Color.FromArgb(0x60, 255, 255, 255));
            b.Foreground = Brushes.White;
            if (b.Content is StackPanel sp) foreach (var t in sp.Children.OfType<TextBlock>()) t.Foreground = Brushes.White;
            System.Windows.Automation.AutomationProperties.SetAutomationId(b, id);
            return b;
        }

        void Show()
        {
            switch (tab)
            {
                case "saves": ShowSaves(); break;
                case "apps": ShowApps(); break;
                case "logs": ShowLogs(); break;
                default: ShowSettings(); break;
            }
        }

        void Changed(bool ios26cfg = false)
        {
            LauncherConfig.Current.Save();
            if (os == "ios26" || ios26cfg) LauncherConfig.Current.WriteIos26Config();
            if (Machines.Runs.ContainsKey(os)) main.Snack(L.T("Saved: it applies at the next start.", "Kaydedildi: sonraki açılışta geçerli olur."), "info");
        }

        // --- settings -------------------------------------------------------------------------------
        void ShowSettings()
        {
            var p = new StackPanel { MaxWidth = 980, HorizontalAlignment = HorizontalAlignment.Left };
            var c = C;
            if (!Guests.Installed(os))
                p.Children.Add(Note("Warn", L.T("Not installed here yet: install it, or point the folders below at an existing install.", "Burada henüz kurulu değil: kurun ya da aşağıdaki klasörleri var olan bir kuruluma yöneltin.")));

            // the guest
            var cpus = Ui.Seg(new[] { (4, "4"), (8, "8") }, c.Smp, v => { c.Smp = v; Changed(); });
            var cpuDesc = os == "ios16" ? L.T("4 boots faster: every broadcast TLB flush stops all vCPUs.", "4 daha hızlı açılır: her TLB temizliği tüm vCPU'ları durdurur.")
                        : L.T("8 gives apps more room; the boot is not faster.", "8 uygulamalara daha çok yer açar; açılış hızlanmaz.");
            UIElement ram;
            string ramDesc;
            if (Guests.HasRamSetting(os))
            {
                var def = Guests.DefaultRam(os);
                var choices = Guests.RamChoices(os).Union(new[] { def }).OrderBy(x => x).ToList();
                int cur = c.RamMiB > 0 ? c.RamMiB : def;
                if (!choices.Contains(cur)) choices.Add(cur);
                ram = Ui.Seg(choices.Select(m => (m, (m / 1024.0).ToString("0.#") + " GB")), cur, v => { c.RamMiB = v == def ? 0 : v; Changed(); });
                ramDesc = L.T($"Its device tree's own: {def / 1024.0:0.#} GB. A save loads with the size it was made with; a new size applies at the next full start.",
                              $"Aygıt ağacının kendi değeri: {def / 1024.0:0.#} GB. Bir kayıt alındığı boyutla açılır; yeni boyut bir sonraki tam açılışta geçerli olur.");
            }
            else
            {
                ram = Ui.Text("7 GB", "H3");
                ramDesc = L.T("Fixed by iOS 16's device tree.", "iOS 16'nın aygıt ağacıyla sabit.");
            }
            var mem = Native.Memory();
            p.Children.Add(Ui.Group(L.T("The guest", "Konuk"),
                Ui.Row(L.K("Vcpus"), cpuDesc + " " + L.T($"This PC: {Environment.ProcessorCount} logical processors.", $"Bu PC: {Environment.ProcessorCount} mantıksal işlemci."), cpus),
                Ui.Row(L.K("Ram"), ramDesc + " " + L.T($"This PC: {mem.total / 1073741824.0:0} GB.", $"Bu PC: {mem.total / 1073741824.0:0} GB."), ram)));

            // the disk
            var quick = Ui.Switch(c.QuickBoot, v => { c.QuickBoot = v; Changed(); }, null, c.DiskMode != "throwaway");
            var disk = Ui.Seg(new[] { ("keep", L.T("Keep changes", "Değişiklikleri sakla")), ("throwaway", L.T("Throwaway", "Atılan")) }, c.DiskMode == "throwaway" ? "throwaway" : "keep",
                v => { c.DiskMode = v; quick.IsEnabled = v != "throwaway"; Changed(); });
            var diskDesc = os == "watch"
                ? L.T("Keep: what the watch writes stays in watchos\\watch.qcow2. Throwaway: a temporary disk.", "Sakla: saatin yazdıkları watchos\\watch.qcow2'de kalır. Atılan: geçici bir disk.")
                : L.T("Keep: settings and apps stay in a user disk over the installed one. Throwaway: dropped when it closes.", "Sakla: ayarlar ve uygulamalar kurulu diskin üstündeki kullanıcı diskinde kalır. Atılan: kapanınca silinir.");
            p.Children.Add(Ui.Group(L.T("Disk", "Disk"),
                Ui.Row(L.K("DiskMode"), diskDesc, disk),
                Ui.Row(L.K("QuickBoot"), L.T($"Closing the window saves {Guests.Name(os)} as it is (about {Guests.Ram(os) / 1024.0:0.#} GB on the disk) and the next start resumes it in seconds.",
                                             $"Pencereyi kapatmak {Guests.Name(os)}'u olduğu gibi kaydeder (diskte yaklaşık {Guests.Ram(os) / 1024.0:0.#} GB) ve sonraki açılış saniyeler içinde oradan sürer."), quick)));

            // the window and the system
            var rows = new List<UIElement>
            {
                Ui.Row(L.K("Network"), os == "ios26" ? L.T("QEMU's user network (NAT): Safari, the App Store's pages.", "QEMU'nun kullanıcı ağı (NAT): Safari, App Store sayfaları.")
                                                     : L.T("QEMU's user network (NAT).", "QEMU'nun kullanıcı ağı (NAT)."), Ui.Switch(c.Net, v => { c.Net = v; Changed(); })),
                Ui.Row(L.K("Sharpness"), L.T("The window scales the screen with the sharper filter (the side bar's Sharpness).", "Pencere ekranı daha keskin süzgeçle ölçekler (yan çubuktaki Keskinlik)."), Ui.Switch(c.Sharp, v => { c.Sharp = v; Changed(); }))
            };
            if (os == "ios26")
            {
                bool hasColl = File.Exists(Path.Combine(Guests.Work(os), "root-collections.qcow2"));
                rows.Add(Ui.Row(L.K("Wallpaper"), hasColl ? L.T("iOS 26's own (drawn by the GPU) or iOS 17's lighter Collections.", "iOS 26'nın kendisi (GPU çizer) ya da iOS 17'nin daha hafif Collections'ı.")
                                                          : L.T("Collections needs its disk: the installer makes it with -Collections.", "Collections kendi diskini ister: kurucu -Collections ile yapar."),
                    Ui.Seg(new[] { ("ios26", "iOS 26"), ("collections", "Collections") }, c.Wallpaper, v => { c.Wallpaper = v; Changed(); }, hasColl)));
                bool hasAod = File.Exists(Path.Combine(Guests.Work(os), "dtree-smp4-aod"));
                rows.Add(Ui.Row(L.K("Aod"), hasAod ? L.T("The side button (F2) dims iOS to its Always On Display; a click wakes it.", "Yan düğme (F2) iOS'u Her Zaman Açık Ekran'a alır; bir tıklama uyandırır.")
                                                   : L.T("This install has no Always On Display trees (an older install).", "Bu kurulumda Her Zaman Açık Ekran ağaçları yok (eski bir kurulum)."),
                    Ui.Switch(c.Aod && hasAod, v => { c.Aod = v; Changed(); }, null, hasAod)));
            }
            p.Children.Add(Ui.Group(L.T("Window and system", "Pencere ve sistem"), rows.ToArray()));

            if (os != "watch") p.Children.Add(TimeGroup(c));
            if (os == "ios26") p.Children.Add(GpuGroup(c));
            p.Children.Add(FolderGroup(c));
            body.Content = p;
        }

        UIElement TimeGroup(OsConfig c)
        {
            bool pc = c.TimeZone == "" && c.Region == "" && c.Clock == "";
            var zone = Ui.Field(c.TimeZone == "" ? IanaZone() : c.TimeZone, 200);
            var region = Ui.Field(c.Region == "" ? System.Globalization.CultureInfo.CurrentCulture.Name.Split('-').Last() : c.Region, 60);
            string clock = c.Clock == "" ? (System.Globalization.CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern.Contains("H") ? "24" : "12") : c.Clock;
            var clk = Ui.Seg(new[] { ("24", "24 h"), ("12", "12 h") }, clock, v => { clock = v; });
            var apply = Ui.Btn(L.T("Apply", "Uygula"), () =>
            {
                c.TimeZone = zone.Text.Trim(); c.Region = region.Text.Trim().ToUpperInvariant(); c.Clock = clock;
                Changed();
            });
            var custom = Ui.Hstack(zone, region, clk, apply);
            custom.IsEnabled = !pc;
            var sw = Ui.Switch(pc, v =>
            {
                custom.IsEnabled = !v;
                if (v) { c.TimeZone = ""; c.Region = ""; c.Clock = ""; Changed(); }
            }, L.T("Same as this PC", "Bu PC ile aynı"));
            var col = new StackPanel();
            col.Children.Add(sw);
            custom.Margin = new Thickness(0, 10, 0, 0);
            col.Children.Add(custom);
            return Ui.Group(L.K("TimeRegion"), Ui.Row(L.K("TimeRegion"),
                L.T("iOS takes them at a start that is not a resume. An IANA zone (Europe/Istanbul), a region (TR) and the clock.", "iOS bunları kaldığı yerden sürmeyen bir açılışta alır. IANA bölgesi (Europe/Istanbul), bölge kodu (TR) ve saat biçimi."), col));
        }

        static string IanaZone()
        {
            var id = TimeZoneInfo.Local.Id;
            return id == "Turkey Standard Time" ? "Europe/Istanbul" : id;
        }

        UIElement GpuGroup(OsConfig c)
        {
            string mode = c.GpuMode == "" ? "cloudos" : c.GpuMode;
            var built = BuiltGpu();
            var rebuild = Ui.Btn(L.K("ApplyReinstall"), () => RebuildGpu(), "BtnPrimary", "\uE72C");
            void Upd() => rebuild.Visibility = built != null && built != Sig(c) ? Visibility.Visible : Visibility.Collapsed;
            var seg = Ui.Seg(new[] { ("cloudos", L.T("Apple's (cloudOS)", "Apple'ınki (cloudOS)")), ("gpu", L.T("A bundle I have", "Elimdeki paket")), ("gpuless", L.T("None", "Yok")) }, mode, v =>
            {
                if (v == "gpu")
                {
                    var f = Ui.Pick(L.T("Select AppleParavirtGPUMetalIOGPUFamily.bundle", "AppleParavirtGPUMetalIOGPUFamily.bundle klasörünü seçin"), c.GpuDriver);
                    if (f == null) return;
                    c.GpuDriver = f;
                }
                c.GpuMode = v;
                Changed(true);
                Upd();
            });
            Upd();
            var col = new StackPanel();
            col.Children.Add(seg);
            rebuild.Margin = new Thickness(0, 10, 0, 0);
            rebuild.HorizontalAlignment = HorizontalAlignment.Left;
            col.Children.Add(rebuild);
            return Ui.Group(L.K("GpuDriver"), Ui.Row(L.K("GpuDriver"),
                L.T("Baked into the disk when it is built: a change rebuilds the GPU layer and the wallpaper (the installer's gpu and wallpaper steps, about an hour). Without one iOS draws on the CPU, slower."
                   + (built != null ? " Built with: " + built + "." : ""),
                    "Disk kurulurken içine konur: değişiklik GPU katmanını ve duvar kâğıdını yeniden kurar (kurucunun gpu ve wallpaper adımları, yaklaşık bir saat). Sürücüsüz iOS CPU'da çizer, daha yavaş."
                   + (built != null ? " Kurulu: " + built + "." : "")), col));
        }

        static string Sig(OsConfig c) => c.GpuMode == "gpuless" ? "gpuless" : c.GpuMode == "gpu" ? "gpu" : "cloudos";

        /// <summary>The route the install's gpu step used (install\gpu.done), or null for a hand-built folder.</summary>
        string BuiltGpu()
        {
            var f = Path.Combine(Guests.Work(os), "install", "gpu.done");
            if (!File.Exists(f)) return null;
            var t = File.ReadAllText(f).Trim();
            return t.StartsWith("cloudos") ? "cloudos" : t.StartsWith("gpu") ? "gpu" : t.StartsWith("gpuless") ? "gpuless" : t;
        }

        void RebuildGpu()
        {
            var work = Guests.Work(os);
            var dir = Path.GetDirectoryName(work.TrimEnd('\\'));
            if (!Path.GetFileName(work.TrimEnd('\\')).Equals("work", StringComparison.OrdinalIgnoreCase) || !AppPaths.IsAppFolder(dir))
            {
                Dialog.Show(main, L.T("Not here", "Burada olmaz"), L.T("This iOS 26 was not installed by Install-ASoftware (its work folder is not <install>\\work): run ios26\\Install-iOS26.cmd in it.", "Bu iOS 26 Install-ASoftware ile kurulmamış (çalışma klasörü <kurulum>\\work değil): içinde ios26\\Install-iOS26.cmd'yi çalıştırın."), L.K("OK"));
                return;
            }
            if (Machines.Runs.ContainsKey(os)) { Dialog.Show(main, L.T("iOS 26 is running", "iOS 26 çalışıyor"), L.T("Turn it off first: the rebuild replaces its disk's layers.", "Önce kapatın: yeniden kurulum diskinin katmanlarını değiştirir."), L.K("OK")); return; }
            if (Dialog.Show(main, L.T("Rebuild the GPU layer?", "GPU katmanı yeniden kurulsun mu?"),
                    L.T("The installer redoes its gpu and wallpaper steps (about an hour). Your user disk (settings, apps) rests on the old layers: it is kept beside them as it is, and a new one starts.",
                        "Kurucu gpu ve wallpaper adımlarını yeniden yapar (yaklaşık bir saat). Kullanıcı diskiniz (ayarlar, uygulamalar) eski katmanların üstünde: olduğu gibi yanında tutulur ve yenisi başlar."),
                    L.T("Rebuild", "Yeniden kur"), L.K("Cancel")) != 0) return;
            var ch = new InstallChoice { Ios26 = true, Dir = dir, Linux = LauncherConfig.Current.Install.Linux ?? "wsl", GpuMode = C.GpuMode == "" ? "cloudos" : C.GpuMode, GpuDriver = C.GpuDriver };
            InstallJob.Start(ch, null);
            main.OpenWizard(null);
        }

        UIElement FolderGroup(OsConfig c)
        {
            var work = Ui.Field(c.Work, 380); work.IsReadOnly = true;
            var app = Ui.Field(Guests.App(os), 380); app.IsReadOnly = true;
            return Ui.Group(L.K("Folders"),
                Ui.Row(L.K("WorkFolder"), L.T("Its disks, firmware and runs.", "Diskleri, aygıt yazılımı ve çalışmaları."), Ui.Hstack(work, Ui.Btn(L.K("Browse"), () =>
                {
                    var f = Ui.Pick(L.T("The work folder of an install", "Bir kurulumun çalışma klasörü"), c.Work);
                    if (f == null) return;
                    var was = c.Work;
                    c.Work = f;
                    if (!Guests.Installed(os) && Dialog.Show(main, L.T("No install there", "Orada kurulum yok"), L.T($"{f} has no finished {Guests.Name(os)} install. Use it anyway?", $"{f} içinde bitmiş bir {Guests.Name(os)} kurulumu yok. Yine de kullanılsın mı?"), L.T("Use it", "Kullan"), L.K("Cancel")) != 0)
                    { c.Work = was; return; }
                    if (os == "ios26" && LauncherConfig.Current.Watch.Work == "") LauncherConfig.Current.Watch.Work = f;
                    Changed(); ShowSettings();
                }))),
                Ui.Row(L.K("AppFolder"), L.T("Where its start script is (an install's folder); the launcher's own when empty.", "Başlatma betiğinin olduğu yer (bir kurulumun klasörü); boşsa başlatıcınınki."), Ui.Hstack(app, Ui.Btn(L.K("Browse"), () =>
                {
                    var f = Ui.Pick(L.T("An ASoftware install folder (with installer\\Setup-ASoftware.ps1)", "Bir ASoftware kurulum klasörü (installer\\Setup-ASoftware.ps1 içeren)"), c.App);
                    if (f == null) return;
                    if (!AppPaths.IsAppFolder(f)) { Dialog.Show(main, L.T("Not an install folder", "Kurulum klasörü değil"), f, L.K("OK")); return; }
                    c.App = f; Changed(); ShowSettings();
                }))));
        }

        static Border Note(string tone, string text)
        {
            var b = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 0, 16), BorderThickness = new Thickness(1) };
            b.SetResourceReference(Border.BackgroundProperty, tone + "Soft");
            b.SetResourceReference(Border.BorderBrushProperty, tone);
            b.Child = Ui.Text(text, "Sub");
            return b;
        }

        // --- saves ------------------------------------------------------------------------------------
        bool savesShownRunning;
        async void ShowSaves()
        {
            var p = new StackPanel { MaxWidth = 980, HorizontalAlignment = HorizontalAlignment.Left };
            body.Content = p;
            var disk = Guests.SaveDisk(os);
            Machines.Runs.TryGetValue(os, out var run);
            bool on = run != null && run.QemuPid != 0 && Native.Alive(run.QemuPid);
            savesShownRunning = on;
            if (on && run.Disk != "") disk = run.Disk;
            if (disk == "" || (!on && C.DiskMode == "throwaway"))
            {
                p.Children.Add(Note("Info", L.T("Saves live in a disk that keeps its changes: set Disk to Keep changes.", "Kayıtlar değişiklikleri saklayan bir diskte durur: Disk'i Değişiklikleri sakla yapın.")));
                return;
            }
            var top = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            top.Children.Add(Ui.Text(L.T("States of ", "Durumlar: ") + disk + L.T(". A save holds the whole machine (memory and disk) and loads only with the vCPUs and RAM it was made with.", ". Bir kayıt tüm makineyi (bellek ve disk) tutar ve yalnız alındığı vCPU ve RAM ile açılır."), "Faint"));
            var tb = Ui.Hstack(on ? Ui.Btn(L.K("SaveNow"), async () => { try { var n = await Machines.SaveNow(os); main.Snack(L.T("Saved: ", "Kaydedildi: ") + n, "good"); ShowSaves(); } catch (Exception e) { Dialog.Show(main, L.T("Not saved", "Kaydedilmedi"), e.Message, L.K("OK")); } }, "BtnPrimary", "\uE74E") : null,
                                Ui.Btn(L.K("Refresh"), ShowSaves, "Btn", "\uE72C"));
            tb.HorizontalAlignment = HorizontalAlignment.Right;
            tb.Margin = new Thickness(24, 0, 0, 0);
            top.ColumnDefinitions.Add(new ColumnDefinition());
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(tb, 1);
            top.Children.Add(tb);
            p.Children.Add(top);
            var list = await Task.Run(() => Guests.Snapshots(os, disk));
            if (list.Count == 0)
            {
                p.Children.Add(Note("Info", on ? L.T("No saves yet: Save now makes one, Save and close makes the quick one.", "Henüz kayıt yok: Şimdi kaydet bir tane yapar, Kaydet ve kapat hızlı olanı.")
                                               : L.T("No saves yet. While it runs: Save now, or Save and close.", "Henüz kayıt yok. Çalışırken: Şimdi kaydet ya da Kaydet ve kapat.")));
                return;
            }
            var rows = new List<UIElement>();
            foreach (var s in list.OrderByDescending(x => x.Quick).ThenByDescending(x => x.When))
                rows.Add(SaveRow(disk, s, on, run));
            p.Children.Add(Ui.Group(null, rows.ToArray()));
        }

        UIElement SaveRow(string disk, Guests.Snap s, bool on, GuestRun run)
        {
            var meta = LauncherConfig.Current.FindSave(disk, s.Name);
            var g = Machines.SaveGuest(os, disk, s.Name);
            string label = !string.IsNullOrEmpty(meta?.Label) ? meta.Label : s.Quick ? L.T("Quick save: where you left it", "Hızlı kayıt: bıraktığınız yer") : s.Name;
            var when = s.When.ToString(L.Tr ? "d MMMM yyyy, HH:mm" : "MMMM d, yyyy, HH:mm", L.Tr ? new System.Globalization.CultureInfo("tr-TR") : System.Globalization.CultureInfo.InvariantCulture);
            string guest = g.known ? $"{g.smp} vCPU · {g.ram / 1024.0:0.#} GB" : L.T($"made before the launcher: {g.smp} vCPU · {g.ram / 1024.0:0.#} GB assumed", $"başlatıcıdan önce alındı: {g.smp} vCPU · {g.ram / 1024.0:0.#} GB varsayıldı");
            var left = new StackPanel();
            var t = new StackPanel { Orientation = Orientation.Horizontal };
            t.Children.Add(Ui.Icon(s.Quick ? "\uE945" : "\uE74E", 15, s.Quick ? "Accent" : "Text2"));
            t.Children.Add(new TextBlock { Text = label, Style = Ui.S("H3"), Margin = new Thickness(10, 0, 0, 0) });
            left.Children.Add(t);
            left.Children.Add(Ui.Text($"{when} · {s.VmSize} · {guest}", "Faint", 3));
            var load = Ui.Btn(L.K("Load"), async () =>
            {
                try
                {
                    if (on) { await Machines.LoadRunning(os, s.Name); main.Snack(L.T("Loaded.", "Yüklendi."), "good"); }
                    else
                    {
                        if (!s.Quick && Guests.Snapshots(os, disk).Any(x => x.Quick) &&
                            Dialog.Show(main, L.T("Load this save?", "Bu kayıt yüklensin mi?"), L.T("The quick save (where you left it) goes once it runs: the disk goes on from this one.", "Hızlı kayıt (bıraktığınız yer) çalışınca silinir: disk bundan devam eder."), L.K("Load"), L.K("Cancel")) != 0) return;
                        main.StartOs(os, s.Quick ? null : s.Name);
                    }
                }
                catch (Exception e) { Dialog.Show(main, L.T("Not loaded", "Yüklenmedi"), e.Message, L.K("OK")); }
            }, "BtnPrimary", "\uE768");
            var ren = Ui.Btn(L.K("Rename"), () =>
            {
                var n = Dialog.Ask(main, L.K("Rename"), L.T("A name for this save (the launcher keeps it; the disk keeps its own id).", "Bu kayıt için bir ad (başlatıcı saklar; disk kendi kimliğini tutar)."), label);
                if (n == null) return;
                var m = LauncherConfig.Current.FindSave(disk, s.Name);
                if (m == null) { LauncherConfig.Current.Saves.Add(m = new SaveMeta { Disk = disk, Name = s.Name, RamMiB = g.known ? g.ram : 0, Smp = g.known ? g.smp : 0 }); }
                m.Label = n.Trim();
                LauncherConfig.Current.Save();
                ShowSaves();
            });
            var del = Ui.Btn(L.K("Delete"), async () =>
            {
                if (Dialog.Show(main, L.T("Delete this save?", "Bu kayıt silinsin mi?"), label + " · " + when + "\n" + L.T("It cannot be undone. (A qcow2 file does not shrink on Windows: the room is reused by the next save.)", "Geri alınamaz. (Windows'ta qcow2 dosyası küçülmez: yer bir sonraki kayıtta yeniden kullanılır.)"), L.K("Delete"), L.K("Cancel")) != 0) return;
                try { await Machines.DeleteSave(os, disk, s.Name); ShowSaves(); }
                catch (Exception e) { Dialog.Show(main, L.T("Not deleted", "Silinmedi"), e.Message, L.K("OK")); }
            }, "BtnDanger");
            bool busy = run != null && run.Busy != "";
            load.IsEnabled = !busy && (!on || !s.Quick);
            del.IsEnabled = !busy && !(on && s.Quick);
            var r = Ui.Hstack(load, ren, del);
            return Ui.Row(null, null, Wrap(left, r));
        }

        static Grid Wrap(UIElement left, UIElement right)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(left);
            Grid.SetColumn(right, 1);
            g.Children.Add(right);
            g.HorizontalAlignment = HorizontalAlignment.Stretch;
            return g;
        }

        // --- apps (.ipa) ------------------------------------------------------------------------------
        void ShowApps()
        {
            var p = new StackPanel { MaxWidth = 980, HorizontalAlignment = HorizontalAlignment.Left };
            body.Content = p;
            if (os == "watch") { p.Children.Add(Note("Info", L.T(".ipa installs are for iOS; watchOS's come later.", ".ipa kurulumu iOS içindir; watchOS'unki sonra gelecek."))); return; }
            var dir = Guests.IpaFolder(os);
            if (dir == "") { p.Children.Add(Note("Warn", L.T("Not installed here.", "Burada kurulu değil."))); return; }
            p.Children.Add(Note("Info", os == "ios16"
                ? L.T("iOS 16 installs an .ipa while it runs (asoftinstalld fetches it from the .ipa folder); results land in Installed and Failed.", "iOS 16 bir .ipa'yı çalışırken kurar (asoftinstalld onu .ipa klasöründen alır); sonuçlar Installed ve Failed klasörlerine düşer.")
                : L.T("iOS 26 installs an .ipa at its next start (direct placement into its disk): add it, then turn iOS 26 off (or Save and close) and start it.", "iOS 26 bir .ipa'yı bir sonraki açılışta kurar (diske doğrudan yerleştirir): ekleyin, sonra iOS 26'yı kapatıp (ya da Kaydet ve kapat) başlatın.")));
            p.Children.Add(Ui.Hstack(Ui.Btn(L.K("InstallIpa"), () => AddIpa(dir), "BtnPrimary", "\uE710"), Ui.Btn(L.K("OpenIpaFolder"), () => { Directory.CreateDirectory(dir); MainWindow.Open(dir); }, "Btn", "\uE838")));
            var rows = new List<UIElement>();
            void Add(string sub, string tone, string what)
            {
                var d = sub == "" ? dir : Path.Combine(dir, sub);
                if (!Directory.Exists(d)) return;
                foreach (var f in new DirectoryInfo(d).GetFiles("*.ipa").OrderByDescending(f => f.LastWriteTime).Take(30))
                {
                    var left = new StackPanel { Orientation = Orientation.Horizontal };
                    left.Children.Add(Ui.Icon(sub == "Installed" ? "\uE73E" : sub == "Failed" ? "\uEA39" : "\uE823", 14, tone));
                    var tx = new StackPanel { Margin = new Thickness(10, 0, 0, 0) };
                    tx.Children.Add(new TextBlock { Text = f.Name, Style = Ui.S("H3") });
                    tx.Children.Add(Ui.Text(what + " · " + f.LastWriteTime.ToString("g") + " · " + L.Size(f.Length), "Faint", 2));
                    left.Children.Add(tx);
                    var log = Path.Combine(d, Path.GetFileNameWithoutExtension(f.Name) + ".log");
                    rows.Add(Ui.Row(null, null, Wrap(left, File.Exists(log) ? Ui.Btn(L.T("Log", "Log"), () => MainWindow.Open(log)) : (UIElement)new TextBlock())));
                }
            }
            Add("", "Info", L.T("waiting", "bekliyor"));
            Add("Installed", "Good", L.T("installed", "kuruldu"));
            Add("Failed", "Bad", L.T("failed", "başarısız"));
            if (rows.Count > 0) { var gr = Ui.Group(L.T("The .ipa folder", ".ipa klasörü"), rows.ToArray()); gr.Margin = new Thickness(0, 18, 0, 0); p.Children.Add(gr); }
        }

        void AddIpa(string dir)
        {
            var d = new Microsoft.Win32.OpenFileDialog { Filter = L.T("iOS apps", "iOS uygulamaları") + " (*.ipa)|*.ipa", Multiselect = true };
            if (d.ShowDialog() != true) return;
            Directory.CreateDirectory(dir);
            long need = d.FileNames.Sum(f => new FileInfo(f).Length);
            if (Native.FreeBytes(dir) < need + 200_000_000) { Dialog.Show(main, L.T("No room", "Yer yok"), L.T($"{L.Size(Native.FreeBytes(dir))} free on {Path.GetPathRoot(dir)}.", $"{Path.GetPathRoot(dir)} üzerinde {L.Size(Native.FreeBytes(dir))} boş."), L.K("OK")); return; }
            foreach (var f in d.FileNames)
            {
                // copied under another name and renamed: the installer never sees half a file
                var to = Path.Combine(dir, Path.GetFileName(f));
                File.Copy(f, to + ".part", true);
                if (File.Exists(to)) File.Delete(to);
                File.Move(to + ".part", to);
            }
            main.Snack(os == "ios26" && Machines.Runs.ContainsKey(os)
                ? L.T("Added: it is installed at iOS 26's next start.", "Eklendi: iOS 26'nın bir sonraki açılışında kurulur.")
                : L.T("Added.", "Eklendi."), "good");
            ShowApps();
        }

        // --- logs ---------------------------------------------------------------------------------------
        void ShowLogs()
        {
            var p = new StackPanel { MaxWidth = 1100, HorizontalAlignment = HorizontalAlignment.Left };
            body.Content = p;
            var run = Guests.LastRunFolder(os);
            var inst = Path.Combine(Guests.Work(os), "install", "logs");
            p.Children.Add(Ui.Hstack(
                Ui.Btn(L.K("OpenRunFolder"), () => MainWindow.Open(run), "Btn", "\uE838"),
                Ui.Btn(L.K("OpenInstallLogs"), () => MainWindow.Open(Directory.Exists(inst) ? inst : Guests.Work(os)), "Btn", "\uE838"),
                Ui.Btn(L.K("PackLogs"), Pack, "BtnPrimary", "\uE7B8")));
            p.Children.Add(Ui.Text(run == "" ? L.T("No run yet.", "Henüz çalışma yok.") : L.T("The last run: ", "Son çalışma: ") + run, "Faint", 12));
            var logView = new TextBox { Style = Ui.S("Field"), FontFamily = Ui.F("Mono"), IsReadOnly = true, TextWrapping = TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Height = 360, FontSize = 11.5, AcceptsReturn = true, Margin = new Thickness(0, 10, 0, 0), VerticalContentAlignment = VerticalAlignment.Top };
            var serial = run == "" ? "" : new[] { "serial.log", Path.Combine("run", "serial.txt"), "stderr.log" }.Select(x => Path.Combine(run, x)).FirstOrDefault(File.Exists) ?? "";
            logView.Text = serial == "" ? "" : Tail(serial, 400);
            p.Children.Add(logView);
            logView.ScrollToEnd();
        }

        static string Tail(string file, int lines)
        {
            try
            {
                using (var s = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    long from = Math.Max(0, s.Length - 256 * 1024);
                    s.Seek(from, SeekOrigin.Begin);
                    var t = new StreamReader(s).ReadToEnd();
                    var all = t.Replace("\r", "").Split('\n');
                    return string.Join("\r\n", all.Skip(Math.Max(0, all.Length - lines)));
                }
            }
            catch (Exception e) { return e.Message; }
        }

        /// <summary>The logs a report needs, in one zip on the desktop: the last run's (text files up to 20 MB each,
        /// the tail of bigger ones), the install's step logs, the launcher's own and its config.</summary>
        void Pack()
        {
            var zip = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), $"ASoftware-logs-{os}-{DateTime.Now:yyyyMMdd-HHmmss}.zip");
            try
            {
                using (var z = ZipFile.Open(zip, ZipArchiveMode.Create))
                {
                    void Put(string file, string name)
                    {
                        try
                        {
                            var fi = new FileInfo(file);
                            if (!fi.Exists) return;
                            var e = z.CreateEntry(name, CompressionLevel.Optimal);
                            using (var to = e.Open())
                            using (var from = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                            {
                                if (fi.Length > 20 << 20) from.Seek(-(20 << 20), SeekOrigin.End);
                                from.CopyTo(to);
                            }
                        }
                        catch { }
                    }
                    var run = Guests.LastRunFolder(os);
                    if (run != "")
                        foreach (var f in Directory.EnumerateFiles(run, "*", SearchOption.AllDirectories).Where(f => new[] { ".log", ".txt", ".json" }.Contains(Path.GetExtension(f).ToLowerInvariant())))
                            Put(f, "run/" + f.Substring(run.Length).TrimStart('\\').Replace('\\', '/'));
                    var inst = Path.Combine(Guests.Work(os), "install", "logs");
                    if (Directory.Exists(inst))
                        foreach (var f in Directory.EnumerateFiles(inst, "*.log")) Put(f, "install/" + Path.GetFileName(f));
                    var marks = Path.Combine(Guests.Work(os), "install");
                    if (Directory.Exists(marks)) foreach (var f in Directory.EnumerateFiles(marks, "*.done").Take(60)) Put(f, "install/markers/" + Path.GetFileName(f));
                    var ll = Path.Combine(AppPaths.LocalData, "logs");
                    if (Directory.Exists(ll)) foreach (var f in Directory.EnumerateFiles(ll, "*.log").OrderByDescending(File.GetLastWriteTime).Take(8)) Put(f, "launcher/" + Path.GetFileName(f));
                    Put(Log.File, "launcher/launcher.log");
                    Put(AppPaths.ConfigFile, "config/launcher.json");
                    Put(AppPaths.SetupState, "config/setup.json");
                    Put(AppPaths.Ios26Config, "config/ios26.config.json");
                    Put(Path.Combine(Guests.Work(os), "qemu", "BUILD.txt"), "qemu/BUILD.txt");
                    var dir = Path.GetDirectoryName(Guests.Work(os).TrimEnd('\\'));
                    if (dir != null) Put(Path.Combine(dir, "install-summary.txt"), "install-summary.txt");
                    var e2 = z.CreateEntry("pc.txt");
                    using (var w = new StreamWriter(e2.Open()))
                    {
                        var m = Native.Memory();
                        w.WriteLine($"ASoftware {Updates.AppVersion}; Windows {Environment.OSVersion.Version}; {Environment.ProcessorCount} logical processors; RAM {m.total / 1e9:0.0} GB, free {m.free / 1e9:0.0} GB");
                        w.WriteLine($"work {Guests.Work(os)}; free {L.Size(Native.FreeBytes(Guests.Work(os)))}");
                    }
                }
                Process.Start("explorer.exe", "/select,\"" + zip + "\"");
                main.Snack(L.T("Logs packed: ", "Loglar paketlendi: ") + zip, "good");
            }
            catch (Exception e) { Dialog.Show(main, L.T("Not packed", "Paketlenmedi"), e.Message, L.K("OK")); }
        }
    }
}
