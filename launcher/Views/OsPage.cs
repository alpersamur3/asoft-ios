using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>One OS's page (the card's More): its settings, saves, apps and logs.</summary>
    public class OsPage : UserControl, IRetext
    {
        readonly string os;
        /// <summary>The system this page shows.</summary>
        public string Os => os;
        readonly MainWindow main;
        string tab;
        // (new at each Build: an element has one parent, and the old layout keeps these as its children)
        ContentControl body;
        DeviceArt device;
        System.Windows.Shapes.Ellipse stateDot;
        TextBlock stateText;
        WrapPanel actions;
        OsConfig C => Guests.Cfg(os);

        public OsPage(string os, MainWindow main, string tab)
        {
            this.os = os; this.main = main;
            this.tab = Tabs().Any(t => t.id == tab) ? tab : "settings";
            Build();
        }

        public void Retext() => Build();

        /// <summary>The page's tabs: Saves only for a system with saves (Guests.HasQuickSave), Apps not for visionOS
        /// (no .ipa install there, and nothing planned to say about one).</summary>
        IEnumerable<(string id, string label)> Tabs()
        {
            yield return ("settings", L.K("Settings"));
            if (Guests.HasQuickSave(os)) yield return ("saves", L.K("Saves"));
            if (os != "vision") yield return ("apps", L.K("Apps"));
            yield return ("logs", L.K("Logs"));
        }

        void Build()
        {
            body = new ContentControl();
            // (the headset is wide: at a phone's height it would push the title away)
            device = new DeviceArt { Os = os, Height = os == "vision" ? 96 : 150, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 24, 0) };
            stateDot = Ui.Dot("Idle");
            stateDot.Margin = new Thickness(0, 1, 8, 0);
            stateText = new TextBlock { FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap };
            stateText.SetResourceReference(TextBlock.ForegroundProperty, "Text2");
            actions = new WrapPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            var root = new Grid { Margin = new Thickness(30, 2, 30, 0) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition());

            // the header: a hairline surface with the device, its name and state, and what to do
            var head = new Border { CornerRadius = new CornerRadius(22), BorderThickness = new Thickness(1), Padding = new Thickness(14, 16, 22, 16) };
            head.SetResourceReference(Border.BackgroundProperty, "Surface");
            head.SetResourceReference(Border.BorderBrushProperty, "Line");
            var hg = new Grid();
            hg.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            hg.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            hg.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 140 });
            hg.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var back = new Button { Style = Ui.S("BtnIcon"), Content = "", VerticalAlignment = VerticalAlignment.Top, ToolTip = L.K("Back") };
            AutomationProperties.SetName(back, L.K("Back"));
            back.Click += (s, e) => main.GoHome();
            hg.Children.Add(back);
            Grid.SetColumn(device, 1);
            hg.Children.Add(device);
            var title = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            title.Children.Add(new TextBlock { Text = Guests.Name(os), Style = Ui.S("H1"), FontSize = 28 });
            title.Children.Add(Ui.Dyn(new TextBlock { Text = Guests.Detail(os), FontSize = 12.5, Margin = new Thickness(1, 1, 0, 0) }, TextBlock.ForegroundProperty, "Text3"));
            var st = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(1, 12, 0, 0) };
            st.Children.Add(stateDot);
            st.Children.Add(stateText);
            title.Children.Add(st);
            Grid.SetColumn(title, 2);
            hg.Children.Add(title);
            actions.Margin = new Thickness(16, 0, 0, 0);
            Grid.SetColumn(actions, 3);
            hg.Children.Add(actions);
            head.Child = hg;
            // (as wide as the settings under it, at most: its buttons stand over their right edge)
            var headRow = new Grid();
            headRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = 980 });
            headRow.Children.Add(head);
            root.Children.Add(headRow);

            // the tabs
            var tabs = Ui.Seg(Tabs(), tab, t => { tab = t; Show(); });
            tabs.Margin = new Thickness(0, 18, 0, 16);
            Grid.SetRow(tabs, 1);
            root.Children.Add(tabs);

            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = body, Padding = new Thickness(0, 0, 6, 24) };
            Grid.SetRow(sv, 2);
            root.Children.Add(sv);
            Content = root;
            Refresh();
            Show();
        }

        /// <summary>The header's device, state and actions (also from the main window's poll).</summary>
        public void Refresh()
        {
            actions.Children.Clear();
            Machines.Runs.TryGetValue(os, out var run);
            bool on = run != null && run.QemuPid != 0 && Native.Alive(run.QemuPid);
            device.Present = Guests.Installed(os) || on;
            device.Awake = on;
            device.Shot = Thumbs.Get(os);
            string tone;
            if (on)
            {
                bool busy = run.Busy == "saving" || run.Busy == "stopping";
                stateText.Text = (run.Busy == "saving" ? L.T("Saving…", "Kaydediliyor…") : run.Busy == "stopping" ? L.T("Turning off…", "Kapatılıyor…") : L.T("Running", "Çalışıyor")) + $" · {run.Smp} vCPU · {run.RamMiB / 1024.0:0.#} GB";
                tone = busy ? "Warn" : "Good";
                if (Guests.HasQuickSave(os) && run.Disk != "" && run.QuickBoot) AddAction(Ui.Btn(L.K("SaveClose"), () => main.SaveClose(os), "BtnPrimary"), "page-saveclose");
                AddAction(Ui.Btn(L.K("TurnOff"), () => main.TurnOff(os), actions.Children.Count == 0 ? "BtnPrimary" : "Btn"), "page-turnoff");
            }
            else if (Guests.Installed(os))
            {
                stateText.Text = L.T("Ready", "Hazır");
                tone = "Idle";
                AddAction(Ui.Btn(L.K("Start"), () => main.StartOs(os), "BtnPrimary"), "page-start");
                // the quick save a start resumed already: going back to it is asked for (MainWindow.GoBack)
                var way = main.QuickOf(os);
                if (Guests.HasQuickSave(os) && main.IsWayBack(os, way))
                {
                    var back = AddAction(Ui.Btn(L.K("GoBack") + " · " + Guests.When(way.When), () => main.GoBack(os), "Btn"), "page-goback");
                    back.ToolTip = Guests.Hardware(os, Guests.SaveShape(os, LauncherConfig.Current.FindSave(Guests.SaveDisk(os), Guests.QuickName)));
                }
            }
            else { stateText.Text = L.T("Not installed", "Kurulu değil"); tone = "Idle"; }
            stateDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, tone);
            if (tab == "saves" && savesShownRunning != on) ShowSaves();
        }

        public void Tick() { }

        /// <summary>A capsule in the header, after the ones before it.</summary>
        Button AddAction(Button b, string id)
        {
            AutomationProperties.SetAutomationId(b, id);
            b.Margin = new Thickness(actions.Children.Count == 0 ? 0 : 10, 4, 0, 4);
            actions.Children.Add(b);
            return b;
        }

        /// <summary>A tab's column: as wide as the header over it (both stop at 980), whatever its rows ask for.</summary>
        StackPanel Column()
        {
            var p = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left };
            AtMost.Bind(p, body, 980);
            return p;
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

        // the settings a save depends on (Guests.Shape) as they were before the last change
        string shapeSeen;

        void Changed(bool ios26cfg = false)
        {
            LauncherConfig.Current.Save();
            if (os == "ios26" || ios26cfg) LauncherConfig.Current.WriteIos26Config();
            var before = shapeSeen;
            shapeSeen = Guests.Shape(os);
            if (Machines.Runs.ContainsKey(os)) main.Snack(L.T("Saved: it applies at the next start.", "Kaydedildi: sonraki açılışta geçerli olur."), "info");
            else if (before != null && before != shapeSeen && Guests.HasQuickSave(os)) NoteShape(before);
        }

        /// <summary>A change of a setting the quick save depends on: the next start boots afresh with it, and the save stays as
        /// the way back with what it was made with (nothing is deleted).</summary>
        async void NoteShape(string before)
        {
            var disk = Guests.SaveDisk(os);
            if (disk == "") return;
            var q = (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(s => s.Quick);
            var note = Machines.ShapeChangeNote(os, q, before);
            if (note != null) Dialog.Show(main, L.T("Saved", "Kaydedildi"), note, L.K("OK"));
        }

        /// <summary>visionOS's sound switched: the next start opens the other disk, which has its own saves. What that start
        /// does (goes on from that disk's save, or boots it), and that the disk left keeps its own save.</summary>
        async void NoteSound(string left)
        {
            var now = Guests.SaveDisk(os);
            if (Machines.Runs.ContainsKey(os) || now == "" || string.Equals(now, left, StringComparison.OrdinalIgnoreCase)) return;
            var q = (await Task.Run(() => Guests.Snapshots(os, now))).FirstOrDefault(s => s.Quick);
            var old = left == "" ? null : (await Task.Run(() => Guests.Snapshots(os, left))).FirstOrDefault(s => s.Quick);
            bool sound = C.Sound;
            bool goesOn = q != null && C.QuickBoot && !q.WayBack && Guests.Fits(os, LauncherConfig.Current.FindSave(now, Guests.QuickName), Guests.Shape(os));
            string text = goesOn
                ? (sound ? L.T($"The next start opens the sound disk and goes on from its save of {Guests.When(q.When, true)}.", $"Sonraki açılış ses diskini açar ve onun {Guests.When(q.When, true)} kaydından sürer.")
                         : L.T($"The next start opens the silent disk and goes on from its save of {Guests.When(q.When, true)}.", $"Sonraki açılış sessiz diski açar ve onun {Guests.When(q.When, true)} kaydından sürer."))
                : (sound ? L.T("The next start boots the sound disk, a cold boot (about 5 to 7 minutes to Home).", "Sonraki açılış ses diskini soğuk başlatır (Home'a yaklaşık 5–7 dakika).")
                         : L.T("The next start boots the silent disk, a cold boot (about 5 to 7 minutes to Home).", "Sonraki açılış sessiz diski soğuk başlatır (Home'a yaklaşık 5–7 dakika)."));
            if (old != null)
                text += " " + (sound ? L.T($"The silent disk keeps its save of {Guests.When(old.When, true)}.", $"Sessiz disk {Guests.When(old.When, true)} kaydını saklar.")
                                     : L.T($"The sound disk keeps its save of {Guests.When(old.When, true)}.", $"Ses diski {Guests.When(old.When, true)} kaydını saklar."));
            Dialog.Show(main, L.T("Saved", "Kaydedildi"), text, L.K("OK"));
        }

        // --- settings -------------------------------------------------------------------------------
        void ShowSettings()
        {
            var p = Column();
            var c = C;
            shapeSeen = Guests.Shape(os);
            if (!Guests.Installed(os))
                p.Children.Add(Ui.Note("Warn", L.T("Not installed here yet: install it, or point the folders below at an existing install.", "Burada henüz kurulu değil: kurun ya da aşağıdaki klasörleri var olan bir kuruluma yöneltin.")));
            // visionOS's minutes of a dark window, said plainly so that nobody takes it for a hang
            if (os == "vision")
                p.Children.Add(Ui.Note("Info", L.T("A research preview on an emulated CPU, so it is slow. A start from cold takes about 5 to 7 minutes to Home on 8 vCPUs, and its window stays dark for about 4.5 of them: it has not hung. A start after the window was closed goes on from there in about 15 seconds.",
                                                   "Öykünülen bir işlemcide çalışan bir araştırma önizlemesi, bu yüzden yavaş. Soğuk açılış 8 vCPU ile Home'a yaklaşık 5–7 dakika sürer ve pencere bunun yaklaşık 4,5 dakikasında karanlık kalır: donmuş değildir. Pencere kapatıldıktan sonraki açılış yaklaşık 15 saniyede kaldığı yerden sürer.")));

            // the guest
            var cpus = Ui.Seg(Guests.CpuChoices(os).Select(n => (n, n.ToString())), c.Smp, v => { c.Smp = v; Changed(); });
            var cpuDesc = os == "ios16" ? L.T("4 boots faster: every broadcast TLB flush stops all vCPUs.", "4 daha hızlı açılır: her TLB temizliği tüm vCPU'ları durdurur.")
                        : os == "vision" ? L.T("8 is the start script's default; the boot times on this page are for 8. A save goes on only with the vCPUs it was made with.", "Başlatma betiğinin varsayılanı 8; bu sayfadaki açılış süreleri 8 içindir. Bir kayıt yalnız alındığı vCPU sayısıyla sürer.")
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
                ram = Ui.Text($"{Guests.DefaultRam(os) / 1024.0:0.#} GB", "H3");
                ramDesc = os == "vision" ? L.T("Fixed by visionOS's device tree.", "visionOS'un aygıt ağacıyla sabit.")
                                         : L.T("Fixed by iOS 16's device tree.", "iOS 16'nın aygıt ağacıyla sabit.");
            }
            var mem = Native.Memory();
            var guest = new List<UIElement>
            {
                Ui.Row(L.K("Vcpus"), cpuDesc + " " + L.T($"This PC: {Environment.ProcessorCount} logical processors.", $"Bu PC: {Environment.ProcessorCount} mantıksal işlemci."), cpus),
                Ui.Row(L.K("Ram"), ramDesc + " " + L.T($"This PC: {mem.total / 1073741824.0:0} GB.", $"Bu PC: {mem.total / 1073741824.0:0} GB."), ram)
            };
            // (only an install made with the audio plug-in has the sound disk)
            if (os == "vision" && Guests.HasSoundDisk())
                guest.Add(Ui.Row(L.T("Sound", "Ses"),
                    L.T("A speaker on Windows' default output. It starts the sound disk (visionos\\vision.qcow2), a disk of its own with its own saves: what visionOS wrote on the silent one is not on it. Sound costs about one vCPU.",
                        "Windows'un varsayılan çıkışında bir hoparlör. Ses diskiyle (visionos\\vision.qcow2) açılır; bu, kendi kayıtları olan ayrı bir disktir: visionOS'un sessiz diske yazdıkları onda yoktur. Ses yaklaşık bir vCPU harcar."),
                    Ui.Switch(c.Sound, v => { var left = Guests.SaveDisk(os); c.Sound = v; Changed(); NoteSound(left); })));
            p.Children.Add(Ui.Group(L.T("The guest", "Konuk"), guest.ToArray()));

            // the disk
            var quick = Ui.Switch(c.QuickBoot, v => { c.QuickBoot = v; Changed(); }, null, c.DiskMode != "throwaway");
            var disk = Ui.Seg(new[] { ("keep", L.T("Keep changes", "Değişiklikleri sakla")), ("throwaway", L.T("Throwaway", "Atılan")) }, c.DiskMode == "throwaway" ? "throwaway" : "keep",
                v => { c.DiskMode = v; quick.IsEnabled = v != "throwaway"; Changed(); });
            var diskDesc = os == "watch"
                ? L.T("Keep: what the watch writes stays in watchos\\watch.qcow2. Throwaway: a temporary disk.", "Sakla: saatin yazdıkları watchos\\watch.qcow2'de kalır. Atılan: geçici bir disk.")
                : os == "vision" && Guests.HasSoundDisk()
                ? L.T("Keep: what visionOS writes stays in visionos\\vision-silent.qcow2 (with sound, visionos\\vision.qcow2). Throwaway: a temporary disk.", "Sakla: visionOS'un yazdıkları visionos\\vision-silent.qcow2'de kalır (sesle visionos\\vision.qcow2). Atılan: geçici bir disk.")
                : os == "vision"
                ? L.T("Keep: what visionOS writes stays in visionos\\vision-silent.qcow2. Throwaway: a temporary disk.", "Sakla: visionOS'un yazdıkları visionos\\vision-silent.qcow2'de kalır. Atılan: geçici bir disk.")
                : L.T("Keep: settings and apps stay in a user disk over the installed one. Throwaway: dropped when it closes.", "Sakla: ayarlar ve uygulamalar kurulu diskin üstündeki kullanıcı diskinde kalır. Atılan: kapanınca silinir.");
            var diskRows = new List<UIElement> { Ui.Row(L.K("DiskMode"), diskDesc, disk) };
            if (Guests.HasQuickSave(os))
                diskRows.Add(Ui.Row(L.K("QuickBoot"), L.T($"Closing the window saves {Guests.Name(os)} as it is (about {Guests.Ram(os) / 1024.0:0.#} GB on the disk) and the next start resumes it in seconds.",
                                                          $"Pencereyi kapatmak {Guests.Name(os)}'u olduğu gibi kaydeder (diskte yaklaşık {Guests.Ram(os) / 1024.0:0.#} GB) ve sonraki açılış saniyeler içinde oradan sürer."), quick));
            p.Children.Add(Ui.Group(L.T("Disk", "Disk"), diskRows.ToArray()));

            // the window and the system
            var rows = new List<UIElement>
            {
                Ui.Row(L.K("Network"), os == "ios26" ? L.T("QEMU's user network (NAT): Safari, the App Store's pages.", "QEMU'nun kullanıcı ağı (NAT): Safari, App Store sayfaları.")
                                                     : L.T("QEMU's user network (NAT).", "QEMU'nun kullanıcı ağı (NAT)."), Ui.Switch(c.Net, v => { c.Net = v; Changed(); }))
            };
            if (os == "vision")
            {
                rows.Add(Ui.Row(L.T("The drawn headset", "Çizilmiş Vision Pro"),
                    L.T("The window draws an Apple Vision Pro around the picture; off, the picture alone, as large as the window lets it be. F9 switches it in the window.",
                        "Pencere resmin çevresine bir Apple Vision Pro çizer; kapalıyken yalnız resim, pencerenin izin verdiği kadar büyük. Pencerede F9 ile değişir."),
                    Ui.Switch(c.Frame, v => { c.Frame = v; Changed(); })));
                // one choice of the PC's GPU for the guests reims-vgpu draws: iOS 26's (Start-visionOS.ps1 -HostGpu)
                var hg = LauncherConfig.Current.Ios26.HostGpu;
                rows.Add(Ui.Row(L.T("The PC's GPU", "PC'nin GPU'su"), L.T("visionOS draws on the one chosen in iOS 26's settings.", "visionOS, iOS 26 ayarlarında seçilende çizer."),
                    Ui.Text(hg == "integrated" ? L.T("Integrated", "Tümleşik") : hg == "discrete" ? L.T("Graphics card", "Ekran kartı") : L.T("Auto", "Otomatik"), "H3")));
            }
            else
                rows.Add(Ui.Row(L.K("Sharpness"), L.T("The window scales the screen with the sharper filter (the side bar's Sharpness).", "Pencere ekranı daha keskin süzgeçle ölçekler (yan çubuktaki Keskinlik)."), Ui.Switch(c.Sharp, v => { c.Sharp = v; Changed(); })));
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

            if (os == "vision") p.Children.Add(VisionKeys());
            if (os != "watch" && os != "vision") p.Children.Add(TimeGroup(c));
            if (os == "ios26") p.Children.Add(GpuGroup(c));
            p.Children.Add(FolderGroup(c));
            body.Content = p;
        }

        /// <summary>visionOS's window, in short: what the mouse and the keys do there (its QEMU's usb-touchscreen walk mode
        /// and the GTK window's keys, as Start-visionOS.ps1 lists them).</summary>
        static UIElement VisionKeys() => Ui.Group(L.T("In its window", "Penceresinde"),
            Ui.Row(L.T("Look and tap", "Bakmak ve dokunmak"),
                L.T("The pointer is where your eyes look; a click is a pinch.", "İşaretçi gözlerinizin baktığı yerdir; tıklama parmak kıstırmadır (pinch)."), null),
            Ui.Row(L.T("Look around and walk", "Etrafa bakmak ve yürümek"),
                L.T("Hold the right button and move the mouse to look around; while it is held W A S D walk, R and F go up and down, and with Shift they turn. The middle button turns walk mode on and off.",
                    "Etrafa bakmak için sağ tuşu basılı tutup fareyi oynatın; basılıyken W A S D yürütür, R ve F yukarı ve aşağı götürür, Shift ile döndürür. Orta tuş yürüme kipini açıp kapatır."), null),
            Ui.Row(L.T("Buttons", "Düğmeler"),
                L.T("F1 Digital Crown (hold: recentre), F2 top button, F3 / F4 volume down / up.", "F1 Digital Crown (basılı tutunca görüşü ortalar), F2 üst düğme, F3 / F4 sesi kısar / açar."), null),
            Ui.Row(L.T("The window", "Pencere"),
                L.T("F9 the drawn headset on or off, F11 full screen, F12 shows the keys you press.", "F9 çizilmiş Vision Pro'yu açar / kapatır, F11 tam ekran, F12 bastığınız tuşları gösterir."), null));

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
            var rebuild = Ui.Btn(L.K("ApplyReinstall"), () => RebuildGpu());
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
            var host = Ui.Seg(new[] { ("auto", L.T("Auto", "Otomatik")), ("integrated", L.T("Integrated", "Tümleşik")), ("discrete", L.T("Graphics card", "Ekran kartı")) },
                c.HostGpu == "integrated" || c.HostGpu == "discrete" ? c.HostGpu : "auto", v => { c.HostGpu = v; Changed(); });
            AutomationProperties.SetName(host, "host-gpu");
            var noGen = Ui.Switch(c.NoGeneratedCommands, v => { c.NoGeneratedCommands = v; Changed(); });
            return Ui.Group(L.K("GpuDriver"),
                Ui.Row(L.T("The PC's GPU", "PC'nin GPU'su"),
                    L.T("Which one iOS 26 draws on. Auto takes the graphics card, or the integrated GPU on a PC whose GPUs are all AMD. A save made on another GPU may not resume on this one; iOS then boots afresh.",
                        "iOS 26 hangisinde çizsin. Otomatik ekran kartını seçer; GPU'ların hepsi AMD olan bir PC'de tümleşik olanı. Başka bir GPU'da alınmış kayıt bunda sürmeyebilir; o zaman iOS baştan açılır."), host),
                Ui.Row(L.T("Advanced: no generated commands", "Gelişmiş: üretilmiş komutlar kapalı"),
                    L.T("Leaves VK_EXT_device_generated_commands unused, for a driver that lists it but misbehaves with it. iOS sees the same GPU.",
                        "VK_EXT_device_generated_commands kullanılmaz; bunu listeleyip düzgün çalıştıramayan sürücüler için. iOS aynı GPU'yu görür."), noGen),
                Ui.Row(L.K("GpuDriver"),
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
            // a new user disk starts: the old one's screen is not this one's
            Thumbs.Drop(os);
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
                    // (the watch follows iOS 26's folder when it had none: its picture was of another disk too)
                    if (os == "ios26" && LauncherConfig.Current.Watch.Work == "") { LauncherConfig.Current.Watch.Work = f; Thumbs.Drop("watch"); }
                    if (os == "ios26" && LauncherConfig.Current.Vision.Work == "") { LauncherConfig.Current.Vision.Work = f; Thumbs.Drop("vision"); }
                    // another install's disk: the screen of the one before does not stand for it
                    if (!string.Equals(was, f, StringComparison.OrdinalIgnoreCase)) Thumbs.Drop(os);
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

        // --- saves ------------------------------------------------------------------------------------
        bool savesShownRunning;
        async void ShowSaves()
        {
            var p = Column();
            body.Content = p;
            var disk = Guests.SaveDisk(os);
            Machines.Runs.TryGetValue(os, out var run);
            bool on = run != null && run.QemuPid != 0 && Native.Alive(run.QemuPid);
            savesShownRunning = on;
            if (on && run.Disk != "") disk = run.Disk;
            if (disk == "" || (!on && C.DiskMode == "throwaway"))
            {
                p.Children.Add(Ui.Note("Info", L.T("Saves live in a disk that keeps its changes: set Disk to Keep changes.", "Kayıtlar değişiklikleri saklayan bir diskte durur: Disk'i Değişiklikleri sakla yapın.")));
                return;
            }
            var top = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            top.Children.Add(Ui.Text(L.T("States of ", "Durumlar: ") + disk + L.T(". A save holds the whole machine (memory and disk) and loads only with the vCPUs and RAM it was made with.", ". Bir kayıt tüm makineyi (bellek ve disk) tutar ve yalnız alındığı vCPU ve RAM ile açılır."), "Faint"));
            var tb = Ui.Hstack(on ? Ui.Btn(L.K("SaveNow"), async () => { try { var n = await Machines.SaveNow(os); main.Snack(L.T("Saved: ", "Kaydedildi: ") + n, "good"); ShowSaves(); } catch (Exception e) { Dialog.Show(main, L.T("Not saved", "Kaydedilmedi"), e.Message, L.K("OK")); } }) : null,
                                Ui.Btn(L.K("Refresh"), ShowSaves));
            tb.HorizontalAlignment = HorizontalAlignment.Right;
            tb.Margin = new Thickness(24, 0, 0, 0);
            top.ColumnDefinitions.Add(new ColumnDefinition());
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(tb, 1);
            top.Children.Add(tb);
            p.Children.Add(top);
            // (-state saves=yes: made-up saves for the screenshots; the test bed's disks have none)
            var list = OsCardVm.TestState("saves") == "yes" ? TestSaves() : await Task.Run(() => Guests.Snapshots(os, disk));
            if (list.Count == 0)
            {
                p.Children.Add(Ui.Note("Info", on ? L.T("No saves yet: Save now makes one, Save and close makes the quick one.", "Henüz kayıt yok: Şimdi kaydet bir tane yapar, Kaydet ve kapat hızlı olanı.")
                                               : L.T("No saves yet. While it runs: Save now, or Save and close.", "Henüz kayıt yok. Çalışırken: Şimdi kaydet ya da Kaydet ve kapat.")));
                return;
            }
            var rows = new List<UIElement>();
            foreach (var s in list.OrderByDescending(x => x.Quick).ThenByDescending(x => x.When))
                rows.Add(SaveRow(disk, s, on, run));
            p.Children.Add(Ui.Group(null, rows.ToArray()));
        }

        static List<Guests.Snap> TestSaves() => new List<Guests.Snap>
        {
            new Guests.Snap { Id = "1", Name = Guests.QuickName, When = DateTime.Now.AddHours(-3), Bytes = 4_400_000_000 },
            new Guests.Snap { Id = "2", Name = "asoft-2026-11-08-2140", When = DateTime.Now.AddDays(-2), Bytes = 4_100_000_000 },
        };

        UIElement SaveRow(string disk, Guests.Snap s, bool on, GuestRun run)
        {
            var meta = LauncherConfig.Current.FindSave(disk, s.Name);
            var g = Machines.SaveGuest(os, disk, s.Name);
            // (while it runs, the quick save is the one it resumed or none: a way back)
            bool wayBack = s.Quick && (on || main.IsWayBack(os, s));
            string label = !string.IsNullOrEmpty(meta?.Label) ? meta.Label
                         : wayBack ? L.T("Way back: the last quick save", "Geri dönüş noktası: son hızlı kayıt")
                         : s.Quick ? L.T("Quick save: where you left it", "Hızlı kayıt: bıraktığınız yer") : s.Name;
            var when = Guests.When(s.When, true);
            // the hardware it opens with: what it was made with
            var hw = Guests.Hardware(os, Guests.SaveShape(os, meta));
            string guest = L.T("opens with ", "açılışı: ") + hw + (g.known ? "" : L.T(" (made before the launcher: assumed)", " (başlatıcıdan önce alındı: varsayıldı)"));
            var left = new StackPanel();
            var t = new StackPanel { Orientation = Orientation.Horizontal };
            // (the quick save is the one a start resumes: it alone gets a colour)
            t.Children.Add(Ui.Dot(s.Quick ? "Accent" : "Idle"));
            t.Children.Add(new TextBlock { Text = label, Style = Ui.S("H3"), Margin = new Thickness(10, 0, 0, 0) });
            left.Children.Add(t);
            left.Children.Add(Ui.Text($"{when} · {s.VmSize} · {guest}", "Faint", 3));
            var load = Ui.Btn(wayBack && !on ? L.K("GoBack") : L.K("Load"), async () =>
            {
                try
                {
                    if (on) { await Machines.LoadRunning(os, s.Name); main.Snack(L.T("Loaded.", "Yüklendi."), "good"); }
                    else if (wayBack) main.GoBack(os);
                    else if (s.Quick) main.StartOs(os);
                    else
                    {
                        // the disk goes back with the save; a quick save stays (as the way back)
                        var quick = (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(x => x.Quick);
                        var text = L.T($"{Guests.Name(os)} goes back to how it was at {when}: what you did after that (settings, apps, files) is undone. It opens with {hw}, as it was saved.",
                                       $"{Guests.Name(os)}, {when} anındaki hâline döner: ondan sonra yaptıklarınız (ayarlar, uygulamalar, dosyalar) geri alınır. Kaydedildiği gibi {hw} ile açılır.");
                        if (quick != null) text += " " + L.T($"The quick save of {Guests.When(quick.When)} stays as a way back.", $"{Guests.When(quick.When)} hızlı kaydı geri dönüş noktası olarak kalır.");
                        if (Dialog.Show(main, L.T("Load this save?", "Bu kayıt yüklensin mi?"), text, L.K("Load"), L.K("Cancel")) != 0) return;
                        main.StartOs(os, s.Name);
                    }
                }
                catch (Exception e) { Dialog.Show(main, L.T("Not loaded", "Yüklenmedi"), e.Message, L.K("OK")); }
            });
            var ren = Ui.Btn(L.K("Rename"), () =>
            {
                var n = Dialog.Ask(main, L.K("Rename"), L.T("A name for this save (the launcher keeps it; the disk keeps its own id).", "Bu kayıt için bir ad (başlatıcı saklar; disk kendi kimliğini tutar)."), label);
                if (n == null) return;
                var m = LauncherConfig.Current.FindSave(disk, s.Name);
                if (m == null) { LauncherConfig.Current.Saves.Add(m = new SaveMeta { Disk = disk, Name = s.Name, RamMiB = g.known ? g.ram : 0, Smp = g.known ? g.smp : 0 }); }
                m.Label = n.Trim();
                LauncherConfig.Current.Save();
                ShowSaves();
            }, "BtnLink");
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
            var p = Column();
            body.Content = p;
            if (os == "watch") { p.Children.Add(Ui.Note("Info", L.T(".ipa installs are for iOS; watchOS's come later.", ".ipa kurulumu iOS içindir; watchOS'unki sonra gelecek."))); return; }
            var dir = Guests.IpaFolder(os);
            if (dir == "") { p.Children.Add(Ui.Note("Warn", L.T("Not installed here.", "Burada kurulu değil."))); return; }
            p.Children.Add(Ui.Note("Info", os == "ios16"
                ? L.T("iOS 16 installs an .ipa while it runs (asoftinstalld fetches it from the .ipa folder); results land in Installed and Failed.", "iOS 16 bir .ipa'yı çalışırken kurar (asoftinstalld onu .ipa klasöründen alır); sonuçlar Installed ve Failed klasörlerine düşer.")
                : L.T("iOS 26 installs an .ipa at its next start (direct placement into its disk): add it, then turn iOS 26 off (or Save and close) and start it.", "iOS 26 bir .ipa'yı bir sonraki açılışta kurar (diske doğrudan yerleştirir): ekleyin, sonra iOS 26'yı kapatıp (ya da Kaydet ve kapat) başlatın.")));
            p.Children.Add(Ui.Hstack(Ui.Btn(L.K("InstallIpa"), () => AddIpa(dir)), Ui.Btn(L.K("OpenIpaFolder"), () => { Directory.CreateDirectory(dir); MainWindow.Open(dir); }, "BtnLink")));
            var rows = new List<UIElement>();
            void Add(string sub, string tone, string what)
            {
                var d = sub == "" ? dir : Path.Combine(dir, sub);
                if (!Directory.Exists(d)) return;
                foreach (var f in new DirectoryInfo(d).GetFiles("*.ipa").OrderByDescending(f => f.LastWriteTime).Take(30))
                {
                    var left = new StackPanel { Orientation = Orientation.Horizontal };
                    var dot = Ui.Dot(tone); dot.VerticalAlignment = VerticalAlignment.Top; dot.Margin = new Thickness(0, 7, 0, 0);
                    left.Children.Add(dot);
                    var tx = new StackPanel { Margin = new Thickness(10, 0, 0, 0) };
                    tx.Children.Add(new TextBlock { Text = f.Name, Style = Ui.S("H3") });
                    tx.Children.Add(Ui.Text(what + " · " + f.LastWriteTime.ToString("g") + " · " + L.Size(f.Length), "Faint", 2));
                    left.Children.Add(tx);
                    var log = Path.Combine(d, Path.GetFileNameWithoutExtension(f.Name) + ".log");
                    rows.Add(Ui.Row(null, null, Wrap(left, File.Exists(log) ? Ui.Btn(L.T("Log", "Log"), () => MainWindow.Open(log), "BtnLink") : (UIElement)new TextBlock())));
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
            var p = Column();
            body.Content = p;
            var run = Guests.LastRunFolder(os);
            var inst = Path.Combine(Guests.Work(os), "install", "logs");
            // (the header keeps the page's one filled capsule: here the pack is an outline one, the folders links)
            p.Children.Add(Ui.Hstack(
                Ui.Btn(L.K("PackLogs"), Pack),
                Ui.Btn(L.K("OpenRunFolder"), () => MainWindow.Open(run), "BtnLink"),
                Ui.Btn(L.K("OpenInstallLogs"), () => MainWindow.Open(Directory.Exists(inst) ? inst : Guests.Work(os)), "BtnLink"),
                Ui.Btn(L.T("Report a problem", "Sorun bildir"), () => main.OpenReport(os), "BtnLink")));
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

        void Pack()
        {
            try
            {
                var zip = LogPack.Make(os);
                Process.Start("explorer.exe", "/select,\"" + zip + "\"");
                main.Snack(L.T("Logs packed: ", "Loglar paketlendi: ") + zip, "good");
            }
            catch (Exception e) { Dialog.Show(main, L.T("Not packed", "Paketlenmedi"), e.Message, L.K("OK")); }
        }
    }
}
