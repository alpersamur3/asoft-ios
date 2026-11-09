using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ASoftware.Engine;
using WF = System.Windows.Forms;

namespace ASoftware.Views
{
    public partial class MainWindow : Window
    {
        readonly ObservableCollection<OsCardVm> cards = new ObservableCollection<OsCardVm>();
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        readonly DispatcherTimer snackTimer = new DispatcherTimer();
        WF.NotifyIcon tray;
        bool quitting, trayHinted, polling;
        Updates.Release update;

        public MainWindow()
        {
            InitializeComponent();
            // the line-up's order: the newest iPhone first
            foreach (var os in new[] { "ios26", "ios16", "watch", "vision" }) cards.Add(new OsCardVm(os, this));
            TestRuns();
            Cards.ItemsSource = cards;
            foreach (var c in cards) c.Refresh();
            RefreshTools();
            Machines.Changed += os => Dispatcher.BeginInvoke(new Action(() => { var c = cards.FirstOrDefault(x => x.Os == os); if (c != null) { c.QuickLooked = DateTime.MinValue; c.Refresh(); } (Page.Content as OsPage)?.Refresh(); RefreshTray(); }));
            Thumbs.Changed += os => Dispatcher.BeginInvoke(new Action(() => { cards.FirstOrDefault(x => x.Os == os)?.LoadShot(); (Page.Content as OsPage)?.Refresh(); }));
            Machines.Note += (os, text) => Dispatcher.BeginInvoke(new Action(() => Snack(text, "info")));
            InstallJob.Changed += () => Dispatcher.BeginInvoke(new Action(() => { foreach (var c in cards) c.Refresh(); RefreshBanners(); InstallEnded(); }));
            L.Changed += () => { foreach (var c in cards) { c.Retext(); c.Refresh(); } RefreshBanners(); RefreshTools(); (Page.Content as IRetext)?.Retext(); RefreshTray(); };
            PhoneJob.Changed += () => Dispatcher.BeginInvoke(new Action(RefreshTools));
            Theme.Changed += () => { foreach (var c in cards) c.Retext(); };
            snackTimer.Tick += (s, e) => { snackTimer.Stop(); Snack_Hide(); };
            timer.Tick += (s, e) => Poll();
            SourceInitialized += (s, e) => Theme.TitleBar(this);
            Loaded += OnLoaded;
            Closing += OnClosing;
        }

        async void OnLoaded(object sender, RoutedEventArgs e)
        {
            timer.Start();
            Poll();
            RefreshBanners();
            SetupTray();
            if (Program.Arg("-shot") != null) { if (Program.Flag("-with-update")) await CheckUpdate(); await Shot(); return; }
            if (Program.Arg("-page") != null) Go(Program.Arg("-page"), Program.Arg("-tab"));
            await CheckUpdate();
        }

        // --- the state of the guests -------------------------------------------------------------
        async void Poll()
        {
            if (polling) return;
            polling = true;
            try
            {
                var qemus = await Task.Run(() => Native.Processes("qemu-system%"));
                foreach (var os in Guests.Ids)
                {
                    if (Machines.Runs.TryGetValue(os, out var r) && (r.QemuPid == 0 || Native.Alive(r.QemuPid))) continue;
                    var q = Guests.FindRunning(os, qemus);
                    if (q != null) Machines.Adopt(os, q);
                }
                foreach (var c in cards.Where(c => !c.Later))
                {
                    if (c.Test == null && (DateTime.Now - c.QuickLooked).TotalSeconds > 45 && Guests.Installed(c.Os) && !Machines.Runs.ContainsKey(c.Os))
                    {
                        c.QuickLooked = DateTime.Now;
                        var os = c.Os;
                        var disk = Guests.SaveDisk(os);
                        c.Quick = disk == "" ? null : (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(s => s.Quick);
                    }
                    c.Refresh();
                }
                if ((DateTime.Now - pcLooked).TotalSeconds > 9) { pcLooked = DateTime.Now; await RefreshPc(qemus); }
                Screens();
                (Page.Content as OsPage)?.Tick();
                (Page.Content as WizardPage)?.Tick();
                (Page.Content as PhonePage)?.Tick();
            }
            catch (Exception ex) { Log.Write("poll: " + ex.Message); }
            finally { polling = false; }
        }

        // --- the shelf's columns: four in a row, else two rows of two (never three and one) --------------------
        const double Column = 270;
        int columns = 4;
        void Shelf_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            double room = Shelf.ActualWidth - Shelf.Padding.Left - Shelf.Padding.Right - 2;
            columns = room >= 4 * Column + 4 ? 4 : room >= 2 * Column + 4 ? 2 : 1;
            // (a little over the columns: layout rounding at 125 % must not push the last one to a new row)
            if (Cards.Width != columns * Column + 4) Cards.Width = columns * Column + 4;
            if (e.HeightChanged) FitSoon();
        }

        // --- the devices' size: what the window's height leaves them ------------------------------------------
        // The shelf, the two rows under it and the bottom line fit without scrolling when the devices can be 170 px or
        // more (counting the second row of links a running system has, so that a start does not shrink them); with two
        // rows of systems (a narrow window) the first row's buttons do.
        const double LinksRow = 31;
        bool fitting;

        void Home_SizeChanged(object sender, SizeChangedEventArgs e) { if (e.HeightChanged) FitSoon(); }
        // (the parts under the window's scroll viewer: the viewer stretches the whole to its own height)
        void Part_SizeChanged(object sender, SizeChangedEventArgs e) { if (e.HeightChanged) FitSoon(); }

        void FitSoon()
        {
            if (fitting) return;
            fitting = true;
            Dispatcher.BeginInvoke(new Action(() => { fitting = false; FitDevices(); }), DispatcherPriority.Loaded);
        }

        void FitDevices()
        {
            if (Home.Visibility != Visibility.Visible || !(Home.Content is FrameworkElement content) || Home.ActualHeight <= 0 || cards.Count == 0) return;
            var first = Cards.ItemContainerGenerator.ContainerFromIndex(0) as ContentPresenter;
            var button = first?.ContentTemplate?.FindName("PrimaryButton", first) as FrameworkElement;
            if (button == null || button.ActualHeight <= 0) return;
            double room = Home.ActualHeight - Home.Padding.Top - Home.Padding.Bottom;
            double row = Math.Round(cards[0].Phone) + 8;
            // what has to fit besides the devices' row (the content's own height: the scroll viewer stretches it to the
            // viewport, so its ActualHeight never says it would fit in less)
            double rest = columns >= cards.Count
                ? content.DesiredSize.Height + (cards.Any(c => c.Running) ? 0 : LinksRow) - row
                : button.TranslatePoint(new Point(0, button.ActualHeight), content).Y + LinksRow + 8 - row;
            double phone = Math.Max(OsCardVm.PhoneMin, Math.Min(OsCardVm.PhoneMax, Math.Floor(room - rest - 8)));
            foreach (var c in cards) c.Phone = phone;
        }

        // --- the rows under the shelf ------------------------------------------------------------------
        void RefreshTools()
        {
            Tools.Children.Clear();
            var j = PhoneJob.Current;
            var phoneNote = j != null && j.Running
                ? Guests.Name(j.Os) + " · " + j.StepText()
                : L.T("The app and what this PC has, onto an Android phone", "Uygulama ve bu PC'dekiler Android telefona");
            Tile("tile-phone", "", L.T("Install on a phone", "Telefona kur"), phoneNote, OpenPhone);
            Tile("tile-report", "", L.T("Report a problem", "Sorun bildir"), L.T("Opens a filled-in issue on GitHub", "GitHub'da doldurulmuş bir bildirim açar"), () => OpenReport());
            LayoutTools();
        }

        void Tile(string id, string icon, string title, string note, Action click)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var ic = Ui.Icon(icon, 18, "Text2");
            ic.Margin = new Thickness(0, 0, 16, 0);
            g.Children.Add(ic);
            var t = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) };
            t.Children.Add(new TextBlock { Text = title, Style = (Style)FindResource("H3") });
            t.Children.Add(new TextBlock { Text = note, Style = (Style)FindResource("Faint"), TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, Margin = new Thickness(0, 2, 0, 0) });
            Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var arrow = Ui.Icon("", 11, "Text3");
            Grid.SetColumn(arrow, 2);
            g.Children.Add(arrow);
            var b = new Button { Style = (Style)FindResource("BtnRow"), Content = g };
            System.Windows.Automation.AutomationProperties.SetAutomationId(b, id);
            System.Windows.Automation.AutomationProperties.SetName(b, title);
            b.Click += (s, e) => click();
            Tools.Children.Add(b);
        }

        void Tools_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            if (e.WidthChanged) LayoutTools();
            if (e.HeightChanged) FitSoon();
        }

        /// <summary>The two rows side by side when there is room, else one above the other.</summary>
        void LayoutTools()
        {
            bool wide = Tools.ActualWidth == 0 || Tools.ActualWidth >= 700;
            int cols = wide ? 2 : 1;
            if (Tools.ColumnDefinitions.Count != cols || Tools.RowDefinitions.Count != 3 - cols)
            {
                Tools.ColumnDefinitions.Clear(); Tools.RowDefinitions.Clear();
                for (int i = 0; i < cols; i++) Tools.ColumnDefinitions.Add(new ColumnDefinition());
                for (int i = 0; i < 3 - cols; i++) Tools.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }
            for (int i = 0; i < Tools.Children.Count; i++)
            {
                var b = (FrameworkElement)Tools.Children[i];
                Grid.SetColumn(b, wide ? i : 0);
                Grid.SetRow(b, wide ? 0 : i);
                b.Margin = wide ? new Thickness(i == 0 ? 0 : 7, 0, i == 0 ? 7 : 0, 0) : new Thickness(0, i == 0 ? 0 : 10, 0, 0);
            }
        }

        // --- this PC, under the shelf: one quiet line ------------------------------------------------------
        DateTime pcLooked;
        static string gpuName;
        async Task RefreshPc(List<Native.Proc> qemus)
        {
            if (gpuName == null)
                gpuName = await Task.Run(() =>
                {
                    try
                    {
                        using (var s = new System.Management.ManagementObjectSearcher("SELECT Name, AdapterRAM FROM Win32_VideoController"))
                            return string.Join(" + ", s.Get().Cast<System.Management.ManagementObject>().Select(o => Convert.ToString(o["Name"])).Where(n => n != "" && !n.Contains("Basic Display")));
                    }
                    catch { return ""; }
                });
            var m = Native.Memory();
            PcLine.Inlines.Clear();
            // (-state pc=low: the warning parts, for the screenshots)
            bool low = OsCardVm.TestState("pc") == "low";
            // (low memory: less free than the smallest guest, watchOS at 2 GB with its QEMU, takes)
            bool lowMem = low || m.free < 5.5e9;
            Part(L.T($"Memory {m.free / 1073741824.0:0.0} of {m.total / 1073741824.0:0} GB free", $"Bellek: {m.total / 1073741824.0:0} GB'ın {m.free / 1073741824.0:0.0} GB'ı boş"),
                 lowMem ? "Warn" : null, lowMem ? L.T("Little memory is free: a guest may not start, or runs slowly.", "Boş bellek az: bir konuk başlamayabilir ya da yavaş çalışır.") : null);
            foreach (var d in Guests.Ids.Select(Guests.Work).Where(w => w != "").Select(w => Path.GetPathRoot(w)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var free = Native.FreeBytes(d);
                bool lowDisk = low || free < 8e9;
                Part(L.T($"{d.TrimEnd('\\')} {L.Size(free)} free", $"{d.TrimEnd('\\')} {L.Size(free)} boş"), lowDisk ? "Warn" : null,
                     lowDisk ? L.T("Little room on this drive: a save of a guest may not fit.", "Bu sürücüde yer az: bir konuğun kaydı sığmayabilir.") : null);
            }
            if (!string.IsNullOrEmpty(gpuName)) Part(gpuName);
            if (qemus.Count > 0) Part(L.T($"QEMU running: {qemus.Count} ({L.Size(qemus.Sum(q => (double)q.WorkingSet))})", $"Çalışan QEMU: {qemus.Count} ({L.Size(qemus.Sum(q => (double)q.WorkingSet))})"));
        }

        void Part(string text, string tone = null, string tip = null)
        {
            if (PcLine.Inlines.Count > 0) PcLine.Inlines.Add(new System.Windows.Documents.Run("  ·  "));
            var r = new System.Windows.Documents.Run(Ui.KeepUnits(text));
            if (tone != null) r.SetResourceReference(System.Windows.Documents.TextElement.ForegroundProperty, tone);
            if (tip != null) r.ToolTip = tip;
            PcLine.Inlines.Add(r);
        }

        // --- the devices' screens: Engine\Thumbs ---------------------------------------------------------
        readonly Dictionary<string, (int pid, DateTime seen)> upSince = new Dictionary<string, (int, DateTime)>();
        readonly Dictionary<string, DateTime> shotAt = new Dictionary<string, DateTime>();

        /// <summary>A running guest's screen about 5 s after it first runs, then about every 10 s while this window shows.</summary>
        void Screens()
        {
            if (Program.Arg("-shot") != null) return;
            bool shown = IsVisible && WindowState != WindowState.Minimized;
            foreach (var os in Guests.Ids)
            {
                if (!Machines.Runs.TryGetValue(os, out var r) || r.QemuPid == 0) { upSince.Remove(os); shotAt.Remove(os); continue; }
                if (!upSince.TryGetValue(os, out var u) || u.pid != r.QemuPid) { upSince[os] = u = (r.QemuPid, DateTime.Now); shotAt.Remove(os); }
                if (r.Busy != "") continue;
                bool first = !shotAt.TryGetValue(os, out var last);
                if (first ? (DateTime.Now - u.seen).TotalSeconds >= 5 : shown && (DateTime.Now - last).TotalSeconds >= 10)
                {
                    shotAt[os] = DateTime.Now;
                    Thumbs.Capture(os);
                }
            }
        }

        /// <summary>The screenshots' made-up running guests (-shot with -state os=running|saving|stopping|starting): a run
        /// whose process is this one, so it counts as alive; nothing is started, and -shot never clicks.</summary>
        void TestRuns()
        {
            foreach (var c in cards)
            {
                var t = c.Test;
                if (t != "running" && t != "saving" && t != "stopping" && t != "starting") continue;
                int me = System.Diagnostics.Process.GetCurrentProcess().Id;
                Machines.Runs[c.Os] = new GuestRun
                {
                    Os = c.Os, QemuPid = t == "starting" ? 0 : me, Ours = true, Smp = Guests.Cfg(c.Os).Smp, RamMiB = Guests.Ram(c.Os),
                    Disk = Guests.SaveDisk(c.Os), QuickBoot = true, Started = DateTime.Now.AddMinutes(-14), Busy = t == "saving" ? "saving" : t == "stopping" ? "stopping" : ""
                };
            }
        }

        // --- the cards' buttons --------------------------------------------------------------------
        public void Primary(OsCardVm c)
        {
            switch (c.Action)
            {
                case "install": OpenWizard(c.Os); break;
                case "resume-install": ResumeInstall(); break;
                case "show-install": OpenWizard(null); break;
                case "start": StartOs(c.Os); break;
                case "show": if (Machines.Runs.TryGetValue(c.Os, out var r)) Native.Raise(r.QemuPid); break;
            }
        }

        public async void StartOs(string os, string loadState = null)
        {
            try
            {
                try { await Machines.Start(os, loadState); }
                catch (Machines.RamWarning w)
                {
                    if (Dialog.Show(this, L.T("Memory is short", "Bellek az"), w.Message, L.T("Start anyway", "Yine de başlat"), L.K("Cancel")) != 0) return;
                    await Machines.Start(os, loadState, true);
                }
                Snack(L.T($"{Guests.Name(os)} is starting in its own window.", $"{Guests.Name(os)} kendi penceresinde açılıyor."), "good");
            }
            catch (Exception ex)
            {
                Log.Write($"{os}: start: {ex.Message}");
                Dialog.Show(this, L.T($"{Guests.Name(os)} did not start", $"{Guests.Name(os)} başlamadı"), ex.Message, L.K("OK"));
            }
            foreach (var c in cards) c.Refresh();
        }

        // the systems whose Save and close or Turn off is under way: while the last screen is taken, before the command
        // marks the run busy, a second click must not send it again
        readonly HashSet<string> leaving = new HashSet<string>();

        public async void SaveClose(string os)
        {
            if (!leaving.Add(os)) return;
            try
            {
                // its screen as it is left, for its device (at most a few seconds; it never stops the save)
                await Thumbs.Before(os);
                await Machines.SaveAndClose(os);
                Snack(L.T($"{Guests.Name(os)} is saved: the next start resumes it.", $"{Guests.Name(os)} kaydedildi: sonraki açılış kaldığı yerden sürer."), "good");
            }
            catch (Exception ex) { Dialog.Show(this, L.T("Not saved", "Kaydedilmedi"), ex.Message, L.K("OK")); }
            finally { leaving.Remove(os); }
        }

        /// <summary>The quick save of this OS's disk, as the home card last looked it up (null when none).</summary>
        public Guests.Snap QuickOf(string os) => cards.FirstOrDefault(c => c.Os == os)?.Quick;

        /// <summary>Whether the next start does not resume this quick save by itself, so that it is a way back: a start has
        /// resumed it already, quick boot is off, or it was made with other settings (vCPUs, RAM, network, GPU).</summary>
        public bool IsWayBack(string os, Guests.Snap s) =>
            s != null && Guests.Cfg(os).DiskMode != "throwaway" &&
            (s.WayBack || !Guests.Cfg(os).QuickBoot || !Guests.Fits(os, LauncherConfig.Current.FindSave(Guests.SaveDisk(os), Guests.QuickName), Guests.Shape(os)));

        /// <summary>Starts the OS from its quick save that a start has resumed already (the way back), after asking: what was
        /// done since is undone. The save stays until the next Save and close.</summary>
        public async void GoBack(string os)
        {
            var disk = Guests.SaveDisk(os);
            var s = disk == "" ? null : (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(x => x.Quick);
            if (s == null) { Dialog.Show(this, L.T("No save to go back to", "Geri dönülecek kayıt yok"), L.T("Save and close makes one.", "Kaydet ve kapat bir tane yapar."), L.K("OK")); return; }
            var when = Guests.When(s.When, true);
            var hw = Guests.Hardware(os, Guests.SaveShape(os, LauncherConfig.Current.FindSave(disk, Guests.QuickName)));
            if (Dialog.Show(this, L.T($"Go back to the save of {when}?", $"{when} kaydına geri dönülsün mü?"),
                    L.T($"{Guests.Name(os)} goes back to how it was at {when}: what you did after that (settings, apps, files) is undone.\n\nIt opens with {hw}, as it was saved ({s.VmSize}). The save stays as the way back until the next Save and close.",
                        $"{Guests.Name(os)}, {when} anındaki hâline döner: ondan sonra yaptıklarınız (ayarlar, uygulamalar, dosyalar) geri alınır.\n\nKaydedildiği gibi {hw} ile açılır ({s.VmSize}). Kayıt bir sonraki Kaydet ve kapat'a kadar geri dönüş noktası olarak kalır."),
                    L.K("GoBack"), L.K("Cancel")) != 0) return;
            StartOs(os, Guests.QuickName);
        }

        public async void TurnOff(string os)
        {
            if (leaving.Contains(os) || !Machines.Runs.TryGetValue(os, out var run)) return;
            string why;
            if (run.Disk == "") why = L.T("What it wrote is dropped (a throwaway disk).", "Yazdıkları atılır (atılan disk).");
            else
            {
                why = L.T("The next start boots it afresh.", "Sonraki açılış baştan başlar.");
                var disk = run.Disk;
                var q = (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(s => s.Quick);
                if (q != null) why += " " + L.T($"The last save ({Guests.When(q.When)}) stays as a way back until the next Save and close.",
                                                $"Son kayıt ({Guests.When(q.When)}) bir sonraki Kaydet ve kapat'a kadar geri dönüş noktası olarak kalır.");
                if (run.QuickBoot) why += " " + L.T("Save and close instead keeps it where it is.", "Kaydet ve kapat ise olduğu yerde saklar.");
            }
            if (os != "ios16" && run.Disk != "") why += " " + L.T("Its disk is synced first.", "Önce diski eşitlenir.");
            if (Dialog.Show(this, L.T($"Turn off {Guests.Name(os)}?", $"{Guests.Name(os)} kapatılsın mı?"), why, L.K("TurnOff"), L.K("Cancel")) != 0) return;
            if (!leaving.Add(os)) return;
            try
            {
                await Thumbs.Before(os);
                await Machines.TurnOff(os);
            }
            finally { leaving.Remove(os); }
            if (Machines.Runs.TryGetValue(os, out run) && Native.Alive(run.QemuPid))
            {
                if (run.Ours && Dialog.Show(this, L.T("It is still running", "Hâlâ çalışıyor"),
                        L.T("QEMU did not end. Stop it now? What it has not written is lost.", "QEMU kapanmadı. Şimdi durdurulsun mu? Yazmadıkları kaybolur."),
                        L.T("Stop it", "Durdur"), L.K("Cancel")) == 0)
                    Machines.ForceStop(os);
            }
        }

        // --- pages ----------------------------------------------------------------------------------
        public void OpenOs(string os, string tab = null) => ShowPage(new OsPage(os, this, tab));

        public void OpenWizard(string os)
        {
            var w = Page.Content as WizardPage ?? new WizardPage(this);
            w.Prefer(os);
            ShowPage(w);
        }

        public void OpenPhone() => ShowPage(new PhonePage(this));
        public void OpenReport(string area = null, string title = null, string text = null) => ShowPage(new ReportPage(this, area, title, text));

        public void ResumeInstall()
        {
            var c = InstallJob.Unfinished() ?? LauncherConfig.Current.Install;
            if (c == null || string.IsNullOrEmpty(c.Dir)) { OpenWizard(null); return; }
            var w = new WizardPage(this);
            ShowPage(w);
            w.Resume(c);
        }

        void ShowPage(FrameworkElement p)
        {
            Page.Content = p;
            Page.Visibility = Visibility.Visible;
            Home.Visibility = Visibility.Collapsed;
        }

        public void GoHome()
        {
            Page.Content = null;
            Page.Visibility = Visibility.Collapsed;
            Home.Visibility = Visibility.Visible;
            foreach (var c in cards) { c.QuickLooked = DateTime.MinValue; c.Refresh(); }
            Poll();
        }

        void Go(string page, string tab)
        {
            switch (page)
            {
                case "wizard":
                    OpenWizard(null);
                    if (tab != null && Program.Arg("-shot") != null) (Page.Content as WizardPage)?.TestStep(tab);
                    break;
                case "settings": ShowPage(new SettingsPage(this)); break;
                case "phone": OpenPhone(); break;
                case "report": OpenReport(); break;
                case "ios16": case "ios26": case "watch": OpenOs(page, tab); break;
                case "devices": ShowPage(TestDevices()); break;
                default: GoHome(); break;     // (dialog: the home page under it)
            }
        }

        /// <summary>-page devices (screenshots only): every device in each state it draws, for a look at the drawings.</summary>
        FrameworkElement TestDevices()
        {
            var states = new (string name, bool present, bool awake, bool shot, double progress, bool later)[]
            {
                (L.T("picture, running", "resim, çalışıyor"), true, true, true, -1, false), (L.T("picture, off", "resim, kapalı"), true, false, true, -1, false),
                (L.T("no picture, running", "resim yok, çalışıyor"), true, true, false, -1, false), (L.T("installing 40 %", "kuruluyor %40"), false, false, false, 40, false),
                (L.T("not installed", "kurulu değil"), false, false, false, -1, false), (L.T("coming later", "yakında"), true, false, false, -1, true)
            };
            var rows = new StackPanel { Margin = new Thickness(30, 0, 30, 20) };
            foreach (var os in new[] { "vision" }.Concat(Guests.Ids))
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 14) };
                var pic = Thumbs.Get(os);
                foreach (var s in states)
                {
                    var cell = new StackPanel { Width = 190 };
                    var d = new DeviceArt
                    {
                        Os = os, Height = os == "watch" ? 136 : os == "vision" ? 89 : 160, Present = s.present, Awake = s.awake, Progress = s.progress, Later = s.later,
                        Shot = s.shot ? pic : null, HorizontalAlignment = HorizontalAlignment.Center
                    };
                    d.VerticalAlignment = VerticalAlignment.Bottom;
                    cell.Children.Add(new Border { Height = os == "vision" ? 100 : 168, Child = d });
                    var caption = Ui.Text(Guests.Name(os) + " · " + s.name, "Faint", 6);
                    caption.TextAlignment = TextAlignment.Center;
                    cell.Children.Add(caption);
                    row.Children.Add(cell);
                }
                rows.Children.Add(row);
            }
            return new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = rows };
        }

        void Install_Click(object sender, RoutedEventArgs e)
        {
            if (InstallJob.Current != null && InstallJob.Current.Running) OpenWizard(null);
            else if (InstallJob.Unfinished() != null) ResumeInstall();
            else OpenWizard(null);
        }

        void Settings_Click(object sender, RoutedEventArgs e) => ShowPage(new SettingsPage(this));

        // --- banners --------------------------------------------------------------------------------
        public void RefreshBanners()
        {
            Banners.Children.Clear();
            var job = InstallJob.Current;
            if (job != null && job.Running && !(Page.Content is WizardPage))
            {
                var now = job.Now;
                Banner("Info", L.T("Installing", "Kuruluyor") + (now != null ? $" · {Guests.Name(now.Os)} · {now.Title}" : ""),
                    "~" + L.Duration(job.SecondsLeft()) + " " + L.T("left", "kaldı"), L.T("Show", "Göster"), () => OpenWizard(null), null);
            }
            else if (job != null && job.Result == "restart" || LauncherConfig.Current.Install.Stage == "restart")
                Banner("Warn", L.T("Restart Windows to finish installing WSL", "WSL kurulumunu bitirmek için Windows'u yeniden başlatın"),
                    L.T("Then open ASoftware again: the install goes on where it stopped.", "Sonra ASoftware'i yeniden açın: kurulum kaldığı yerden sürer."), null, null, null);
            else if (InstallJob.Unfinished() is InstallChoice u && !(Page.Content is WizardPage))
                Banner("Warn", L.T("An install is not finished", "Bitmemiş bir kurulum var"),
                    L.T($"It stopped in {u.Dir}; it goes on where it stopped.", $"{u.Dir} içinde durdu; kaldığı yerden devam eder."),
                    L.K("Resume"), ResumeInstall, () => { LauncherConfig.Current.Install.Stage = "dismissed"; LauncherConfig.Current.Save(); RefreshBanners(); });
            if (update != null)
                Banner("Accent", L.K("UpdateAvailable") + ": " + (string.IsNullOrEmpty(update.Name) ? update.Tag : update.Name),
                    Updates.DevBuild ? L.T("This is a development build.", "Bu bir geliştirme derlemesi.") : L.T("You have ", "Sizdeki: ") + Updates.AppVersion,
                    L.K("ReleasePage"), () => Open(update.Url), () => { LauncherConfig.Current.SkippedVersion = update.Tag; LauncherConfig.Current.Save(); update = null; RefreshBanners(); });
        }

        /// <summary>A banner: a hairline surface with a tone dot, its text, a capsule for its action and a link to dismiss it.</summary>
        void Banner(string tone, string title, string text, string action, Action act, Action dismiss)
        {
            var b = new Border
            {
                CornerRadius = new CornerRadius(16), Padding = new Thickness(18, 12, 14, 12), Margin = new Thickness(0, 0, 0, 10), BorderThickness = new Thickness(1)
            };
            b.SetResourceReference(Border.BackgroundProperty, "Surface");
            b.SetResourceReference(Border.BorderBrushProperty, "Line");
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var dot = Ui.Dot(tone);
            dot.VerticalAlignment = VerticalAlignment.Top;
            dot.Margin = new Thickness(0, 7, 14, 0);
            g.Children.Add(dot);
            var t = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            t.Children.Add(new TextBlock { Text = title, Style = (Style)FindResource("H3"), TextWrapping = TextWrapping.Wrap });
            if (!string.IsNullOrEmpty(text)) t.Children.Add(new TextBlock { Text = text, Style = (Style)FindResource("Sub"), Margin = new Thickness(0, 2, 0, 0) });
            Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            if (dismiss != null) { var d = new Button { Content = L.K("Dismiss"), Style = (Style)FindResource("BtnLink"), Margin = new Thickness(12, 0, 0, 0) }; d.SetResourceReference(ForegroundProperty, "Text2"); d.Click += (s, e) => dismiss(); buttons.Children.Add(d); }
            if (action != null) { var a = new Button { Content = action, Style = (Style)FindResource("Btn"), Margin = new Thickness(16, 0, 0, 0) }; a.Click += (s, e) => act(); buttons.Children.Add(a); }
            Grid.SetColumn(buttons, 2);
            g.Children.Add(buttons);
            b.Child = g;
            Banners.Children.Add(b);
        }

        public static void Open(string what)
        {
            var test = Environment.GetEnvironmentVariable("ASOFT_TEST_OPEN");     // the UI tests: what would have been opened
            if (!string.IsNullOrEmpty(test)) { File.AppendAllText(test, what + "\r\n"); return; }
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(what) { UseShellExecute = true }); } catch (Exception e) { Log.Write("open " + what + ": " + e.Message); }
        }

        async Task CheckUpdate()
        {
            var conf = LauncherConfig.Current;
            if (!conf.CheckUpdates) return;
            try
            {
                var r = await Updates.Latest();
                conf.LastUpdateCheck = DateTime.Now.ToString("s");
                conf.Save();
                Log.Write($"update check: latest {r?.Tag}, this {Updates.AppVersion}");
                if (r != null && Updates.Newer(r.Tag) && r.Tag != conf.SkippedVersion) { update = r; RefreshBanners(); if (!IsVisible) TrayTip(L.K("UpdateAvailable"), r.Tag); }
            }
            catch (Exception ex) { Log.Write("update check: " + ex.Message); }
        }

        // --- a note at the bottom -------------------------------------------------------------------
        public void Snack(string text, string kind = "info")
        {
            SnackText.Text = text;
            var tone = kind == "error" ? "Bad" : kind == "good" ? "Good" : kind == "warn" ? "Warn" : "Info";
            SnackDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, tone);
            SnackBar.Visibility = Visibility.Visible;
            snackTimer.Stop();
            snackTimer.Interval = TimeSpan.FromSeconds(kind == "error" ? 14 : 7);
            snackTimer.Start();
            if (!IsVisible) TrayTip("ASoftware", text);
        }
        void Snack_Hide() => SnackBar.Visibility = Visibility.Collapsed;
        void SnackClose_Click(object sender, RoutedEventArgs e) => Snack_Hide();

        // --- the tray -----------------------------------------------------------------------------
        void SetupTray()
        {
            try
            {
                var s = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/logo.ico")).Stream;
                tray = new WF.NotifyIcon { Icon = new System.Drawing.Icon(s), Text = "ASoftware", Visible = true };
                tray.DoubleClick += (o, e) => Reveal();
                tray.BalloonTipClicked += (o, e) => Reveal();
                RefreshTray();
            }
            catch (Exception e) { Log.Write("tray: " + e.Message); }
        }

        void RefreshTray()
        {
            if (tray == null) return;
            var m = new WF.ContextMenuStrip();
            m.Items.Add(L.K("Open"), null, (o, e) => Reveal());
            m.Items.Add(new WF.ToolStripSeparator());
            foreach (var os in Guests.Ids)
            {
                if (!Guests.Installed(os)) continue;
                var name = Guests.Name(os);
                bool on = Machines.Runs.TryGetValue(os, out var r) && r.QemuPid != 0;
                if (!on) m.Items.Add(L.K("Start") + " " + name, null, (o, e) => StartOs(os));
                else
                {
                    var sub = new WF.ToolStripMenuItem(name);
                    if (r.Disk != "" && r.QuickBoot) sub.DropDownItems.Add(L.K("SaveClose"), null, (o, e) => SaveClose(os));
                    sub.DropDownItems.Add(L.T("Show window", "Pencereyi göster"), null, (o, e) => Native.Raise(r.QemuPid));
                    sub.DropDownItems.Add(L.K("TurnOff"), null, (o, e) => { Reveal(); TurnOff(os); });
                    m.Items.Add(sub);
                }
            }
            m.Items.Add(new WF.ToolStripSeparator());
            m.Items.Add(L.K("Quit"), null, (o, e) => Quit());
            var old = tray.ContextMenuStrip;
            tray.ContextMenuStrip = m;
            old?.Dispose();
            var running = Machines.Runs.Values.Where(r => r.QemuPid != 0).Select(r => Guests.Name(r.Os)).ToList();
            var text = "ASoftware" + (running.Count > 0 ? " · " + string.Join(", ", running) : "");
            tray.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        void TrayTip(string title, string text)
        {
            try { tray?.ShowBalloonTip(5000, title, text, WF.ToolTipIcon.Info); } catch { }
        }

        public void Reveal()
        {
            Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Activate();
            Topmost = true; Topmost = false;
        }

        void OnClosing(object sender, CancelEventArgs e)
        {
            if (quitting) return;
            bool busy = Machines.Runs.Values.Any(r => r.Ours && r.QemuPid != 0) || (InstallJob.Current?.Running ?? false);
            if (LauncherConfig.Current.CloseToTray && busy && tray != null)
            {
                e.Cancel = true;
                Hide();
                if (!trayHinted) { trayHinted = true; TrayTip("ASoftware", L.T("Still running here; your guests and the install go on.", "Burada çalışmaya devam ediyor; konuklar ve kurulum sürer.")); }
                return;
            }
            if (InstallJob.Current?.Running ?? false)
            {
                if (Dialog.Show(this, L.T("An install is running", "Bir kurulum çalışıyor"),
                        L.T("Closing the launcher stops it; the next run goes on from the step it was in.", "Başlatıcıyı kapatmak onu durdurur; sonraki çalıştırma bulunduğu adımdan sürer."),
                        L.T("Stop and close", "Durdur ve kapat"), L.K("Cancel")) != 0) { e.Cancel = true; return; }
                InstallJob.Current.StopNow();
            }
            Quit();
        }

        public void Quit()
        {
            quitting = true;
            try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch { }
            // the guests go on in their own windows
            Application.Current.Shutdown();
        }

        void InstallEnded()
        {
            var j = InstallJob.Current;
            if (j == null || j.Running || j.Result == "" || notified == j) return;
            notified = j;
            var t = j.Result == "done" ? L.T("The install is done.", "Kurulum bitti.")
                  : j.Result == "paused" ? L.T("The install is paused.", "Kurulum duraklatıldı.")
                  : j.Result == "restart" ? L.T("Restart Windows to finish installing WSL.", "WSL kurulumunu bitirmek için Windows'u yeniden başlatın.")
                  : L.T("The install stopped: ", "Kurulum durdu: ") + j.Message;
            if (!IsVisible) TrayTip("ASoftware", t);
            RefreshTray();
        }
        InstallJob notified;

        // --- screenshots for the notes (-shot FILE.png -page PAGE) ------------------------------------
        async Task Shot()
        {
            try
            {
                // -size WxH: the window's outer size, e.g. its minimum 760x600
                var size = (Program.Arg("-size") ?? "").Split('x');
                if (size.Length == 2 && double.TryParse(size[0], out var sw) && double.TryParse(size[1], out var sh)) { Width = sw; Height = sh; }
                var page = Program.Arg("-page") ?? "home";
                Go(page, Program.Arg("-tab"));
                // -snack TEXT: a note at the bottom, as after a start
                if (Program.Arg("-snack") != null) Snack(Program.Arg("-snack"), "good");
                // -page dialog: the turn-off question over the home page
                Window dialog = null;
                if (page == "dialog")
                {
                    dialog = Dialog.Make(this, L.T("Turn off iOS 26?", "iOS 26 kapatılsın mı?"),
                        L.T("The next start boots it afresh. Save and close instead keeps it where it is. Its disk is synced first.",
                            "Sonraki açılış baştan başlar. Kaydet ve kapat ise olduğu yerde saklar. Önce diski eşitlenir."), null, new[] { L.K("TurnOff"), L.K("Cancel") }, n => { }, out _);
                    dialog.Show();
                }
                await Task.Delay(int.TryParse(Program.Arg("-wait"), out var ms) ? ms : 2500);
                Poll();
                await Task.Delay(1200);
                var root = (FrameworkElement)Content;
                var dpi = VisualTreeHelper.GetDpi(this);
                var bmp = new RenderTargetBitmap((int)(root.ActualWidth * dpi.DpiScaleX), (int)(root.ActualHeight * dpi.DpiScaleY), 96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, PixelFormats.Pbgra32);
                var bg = new DrawingVisual();
                using (var dc = bg.RenderOpen()) dc.DrawRectangle((Brush)FindResource("Bg"), null, new Rect(0, 0, root.ActualWidth, root.ActualHeight));
                bmp.Render(bg);
                bmp.Render(root);
                if (dialog?.Content is FrameworkElement card)
                {
                    // the dialog's own window, drawn where it stands: over the middle of this one
                    var over = new DrawingVisual();
                    double w = card.ActualWidth + card.Margin.Left + card.Margin.Right, h = card.ActualHeight + card.Margin.Top + card.Margin.Bottom;
                    using (var dc = over.RenderOpen()) dc.DrawRectangle(new VisualBrush((Visual)dialog.Content) { Stretch = Stretch.None }, null, new Rect((root.ActualWidth - w) / 2, (root.ActualHeight - h) / 2, w, h));
                    bmp.Render(over);
                    dialog.Close();
                }
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(bmp));
                var file = Path.GetFullPath(Program.Arg("-shot"));
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                using (var f = File.Create(file)) enc.Save(f);
                Log.Write("shot " + file);
            }
            catch (Exception ex) { Log.Write("shot: " + ex); }
            Quit();
        }
    }

    public interface IRetext { void Retext(); }
}
