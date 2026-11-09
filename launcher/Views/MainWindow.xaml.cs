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
            foreach (var os in new[] { "ios16", "ios26", "watch", "vision" }) cards.Add(new OsCardVm(os, this));
            Cards.ItemsSource = cards;
            foreach (var c in cards) c.Refresh();
            RefreshTools();
            Machines.Changed += os => Dispatcher.BeginInvoke(new Action(() => { var c = cards.FirstOrDefault(x => x.Os == os); if (c != null) { c.QuickLooked = DateTime.MinValue; c.Refresh(); } (Page.Content as OsPage)?.Refresh(); RefreshTray(); }));
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
                    if ((DateTime.Now - c.QuickLooked).TotalSeconds > 45 && Guests.Installed(c.Os) && !Machines.Runs.ContainsKey(c.Os))
                    {
                        c.QuickLooked = DateTime.Now;
                        var os = c.Os;
                        var disk = Guests.SaveDisk(os);
                        c.Quick = disk == "" ? null : (await Task.Run(() => Guests.Snapshots(os, disk))).FirstOrDefault(s => s.Quick);
                    }
                    c.Refresh();
                }
                if ((DateTime.Now - pcLooked).TotalSeconds > 9) { pcLooked = DateTime.Now; await RefreshPc(qemus); }
                (Page.Content as OsPage)?.Tick();
                (Page.Content as WizardPage)?.Tick();
                (Page.Content as PhonePage)?.Tick();
            }
            catch (Exception ex) { Log.Write("poll: " + ex.Message); }
            finally { polling = false; }
        }

        // --- the tiles under the cards -----------------------------------------------------------------
        void RefreshTools()
        {
            Tools.Children.Clear();
            var j = PhoneJob.Current;
            var phoneNote = j != null && j.Running
                ? Guests.Name(j.Os) + " · " + j.StepText()
                : L.T("The app and what this PC has, onto an Android phone", "Uygulama ve bu PC'dekiler Android telefona");
            Tile("tile-phone", "\uE8EA", L.T("Install on a phone", "Telefona kur"), phoneNote, OpenPhone);
            Tile("tile-report", "\uEBE8", L.T("Report a problem", "Sorun bildir"), L.T("Opens a filled-in issue on GitHub", "GitHub'da doldurulmuş bir bildirim açar"), () => OpenReport());
        }

        void Tile(string id, string icon, string title, string note, Action click)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var box = new Border { Width = 40, Height = 40, CornerRadius = new CornerRadius(12), Child = new Grid { Children = { Center(Ui.Icon(icon, 18, "Accent")) } } };
            box.SetResourceReference(Border.BackgroundProperty, "AccentSoft");
            g.Children.Add(box);
            var t = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 8, 0) };
            t.Children.Add(new TextBlock { Text = title, Style = (Style)FindResource("H3") });
            t.Children.Add(new TextBlock { Text = note, Style = (Style)FindResource("Faint"), FontWeight = FontWeights.Normal, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, Margin = new Thickness(0, 1, 0, 0) });
            Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var arrow = Ui.Icon("\uE76C", 12, "Text3");
            Grid.SetColumn(arrow, 2);
            g.Children.Add(arrow);
            var b = new Button { Style = (Style)FindResource("Btn"), Content = g, Width = 560, Margin = new Thickness(10, 6, 10, 6), Padding = new Thickness(14, 12, 14, 12), HorizontalContentAlignment = HorizontalAlignment.Stretch };
            b.SetResourceReference(Control.BackgroundProperty, "Surface");
            System.Windows.Automation.AutomationProperties.SetAutomationId(b, id);
            System.Windows.Automation.AutomationProperties.SetName(b, title);
            b.Click += (s, e) => click();
            Tools.Children.Add(b);
        }

        static FrameworkElement Center(FrameworkElement e) { e.HorizontalAlignment = HorizontalAlignment.Center; e.VerticalAlignment = VerticalAlignment.Center; return e; }

        // --- this PC, under the cards ------------------------------------------------------------------
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
            PcStrip.Children.Clear();
            Chip("\uE964", L.T($"Memory {m.free / 1073741824.0:0.0} of {m.total / 1073741824.0:0} GB free", $"Bellek: {m.total / 1073741824.0:0} GB'ın {m.free / 1073741824.0:0.0} GB'ı boş"));
            foreach (var d in Guests.Ids.Select(Guests.Work).Where(w => w != "").Select(w => Path.GetPathRoot(w)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var free = Native.FreeBytes(d);
                Chip("\uEDA2", L.T($"{d.TrimEnd('\\')} {L.Size(free)} free", $"{d.TrimEnd('\\')} {L.Size(free)} boş"), free < 8e9 ? "Warn" : null);
            }
            if (!string.IsNullOrEmpty(gpuName)) Chip("\uE7F4", gpuName);
            if (qemus.Count > 0) Chip("\uE7B5", L.T($"QEMU running: {qemus.Count} ({L.Size(qemus.Sum(q => (double)q.WorkingSet))})", $"Çalışan QEMU: {qemus.Count} ({L.Size(qemus.Sum(q => (double)q.WorkingSet))})"));
        }

        void Chip(string icon, string text, string tone = null)
        {
            var b = new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 6, 12, 6), Margin = new Thickness(5), BorderThickness = new Thickness(1) };
            b.SetResourceReference(Border.BackgroundProperty, "Surface");
            b.SetResourceReference(Border.BorderBrushProperty, tone ?? "Line");
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Ui.Icon(icon, 13, tone ?? "Text3"));
            var t = new TextBlock { Text = text, FontSize = 12, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            t.SetResourceReference(TextBlock.ForegroundProperty, "Text2");
            sp.Children.Add(t);
            b.Child = sp;
            PcStrip.Children.Add(b);
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

        public async void SaveClose(string os)
        {
            try
            {
                await Machines.SaveAndClose(os);
                Snack(L.T($"{Guests.Name(os)} is saved: the next start resumes it.", $"{Guests.Name(os)} kaydedildi: sonraki açılış kaldığı yerden sürer."), "good");
            }
            catch (Exception ex) { Dialog.Show(this, L.T("Not saved", "Kaydedilmedi"), ex.Message, L.K("OK")); }
        }

        public async void TurnOff(string os)
        {
            if (!Machines.Runs.TryGetValue(os, out var run)) return;
            var why = run.Disk != "" && run.QuickBoot
                ? L.T("The next start boots it afresh. Save and close instead keeps it where it is.", "Sonraki açılış baştan başlar. Kaydet ve kapat ise olduğu yerde saklar.")
                : L.T("What it wrote is dropped (a throwaway disk).", "Yazdıkları atılır (atılan disk).");
            if (os != "ios16" && run.Disk != "") why += " " + L.T("Its disk is synced first.", "Önce diski eşitlenir.");
            if (Dialog.Show(this, L.T($"Turn off {Guests.Name(os)}?", $"{Guests.Name(os)} kapatılsın mı?"), why, L.K("TurnOff"), L.K("Cancel")) != 0) return;
            await Machines.TurnOff(os);
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
                case "wizard": OpenWizard(null); break;
                case "settings": ShowPage(new SettingsPage(this)); break;
                case "phone": OpenPhone(); break;
                case "report": OpenReport(); break;
                case "ios16": case "ios26": case "watch": OpenOs(page, tab); break;
                default: GoHome(); break;
            }
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
                Banner("Info", "\uE896", L.T("Installing", "Kuruluyor") + (now != null ? $" · {Guests.Name(now.Os)} · {now.Title}" : ""),
                    "~" + L.Duration(job.SecondsLeft()) + " " + L.T("left", "kaldı"), L.T("Show", "Göster"), () => OpenWizard(null), null);
            }
            else if (job != null && job.Result == "restart" || LauncherConfig.Current.Install.Stage == "restart")
                Banner("Warn", "\uE7E8", L.T("Restart Windows to finish installing WSL", "WSL kurulumunu bitirmek için Windows'u yeniden başlatın"),
                    L.T("Then open ASoftware again: the install goes on where it stopped.", "Sonra ASoftware'i yeniden açın: kurulum kaldığı yerden sürer."), null, null, null);
            else if (InstallJob.Unfinished() is InstallChoice u && !(Page.Content is WizardPage))
                Banner("Warn", "\uE769", L.T("An install is not finished", "Bitmemiş bir kurulum var"),
                    L.T($"It stopped in {u.Dir}; it goes on where it stopped.", $"{u.Dir} içinde durdu; kaldığı yerden devam eder."),
                    L.K("Resume"), ResumeInstall, () => { LauncherConfig.Current.Install.Stage = "dismissed"; LauncherConfig.Current.Save(); RefreshBanners(); });
            if (update != null)
                Banner("Accent", "\uE896", L.K("UpdateAvailable") + ": " + (string.IsNullOrEmpty(update.Name) ? update.Tag : update.Name),
                    Updates.DevBuild ? L.T("This is a development build.", "Bu bir geliştirme derlemesi.") : L.T("You have ", "Sizdeki: ") + Updates.AppVersion,
                    L.K("ReleasePage"), () => Open(update.Url), () => { LauncherConfig.Current.SkippedVersion = update.Tag; LauncherConfig.Current.Save(); update = null; RefreshBanners(); });
        }

        void Banner(string tone, string icon, string title, string text, string action, Action act, Action dismiss)
        {
            var b = new Border
            {
                CornerRadius = new CornerRadius(14), Padding = new Thickness(16, 12, 12, 12), Margin = new Thickness(0, 0, 0, 8), BorderThickness = new Thickness(1)
            };
            b.SetResourceReference(Border.BackgroundProperty, tone + "Soft");
            b.SetResourceReference(Border.BorderBrushProperty, tone);
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var ic = Ui.Icon(icon, 18, tone);
            ic.Margin = new Thickness(0, 0, 14, 0);
            g.Children.Add(ic);
            var t = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            t.Children.Add(new TextBlock { Text = title, Style = (Style)FindResource("H3"), TextWrapping = TextWrapping.Wrap });
            if (!string.IsNullOrEmpty(text)) t.Children.Add(new TextBlock { Text = text, Style = (Style)FindResource("Sub"), Margin = new Thickness(0, 2, 0, 0) });
            Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            if (action != null) { var a = new Button { Content = action, Style = (Style)FindResource("Btn"), Margin = new Thickness(12, 0, 0, 0) }; a.Click += (s, e) => act(); buttons.Children.Add(a); }
            if (dismiss != null) { var d = new Button { Content = "\uE711", Style = (Style)FindResource("BtnIcon"), Width = 32, Height = 32, FontSize = 11, Margin = new Thickness(6, 0, 0, 0), ToolTip = L.K("Dismiss") }; d.Click += (s, e) => dismiss(); buttons.Children.Add(d); }
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
            SnackIcon.Text = kind == "error" ? "\uEA39" : kind == "good" ? "\uE73E" : kind == "warn" ? "\uE7BA" : "\uE946";
            SnackIcon.SetResourceReference(TextBlock.ForegroundProperty, tone);
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
                Go(Program.Arg("-page") ?? "home", Program.Arg("-tab"));
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
