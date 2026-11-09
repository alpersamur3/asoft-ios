using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>Install on a phone: find it over adb, put the app on it, send it what this PC has installed.</summary>
    public class PhonePage : UserControl, IRetext
    {
        readonly MainWindow main;
        string adb = Phone.FindAdb();
        List<Phone.Device> devices = new List<Phone.Device>();
        string serial = "";
        Phone.Apk apk;
        string apkState = "";       // "" or what is happening to the app, or the last failure
        double apkFraction = -1;
        bool looking, gettingTools, showLog;
        string toolsError = "";
        string detailsOf = "";
        DateTime detailsAt;
        CancellationTokenSource stop;

        string os;
        bool withData, fileOnly, dropAfter = true;
        string folder;

        TextBlock jobHead, jobSub;
        ProgressBar jobBar;
        TextBox logBox;
        ProgressBar apkBar;

        public PhonePage(MainWindow main)
        {
            this.main = main;
            os = Guests.Ids.FirstOrDefault(Guests.Installed);
            if (PhoneJob.Current != null && PhoneJob.Current.Running) os = PhoneJob.Current.Os;
            folder = DefaultFolder(os);
            Build();
            Loaded += async (s, e) =>
            {
                PhoneJob.Changed += OnJob;
                await Look(true);
                try { apk = await Phone.LatestApk(); } catch (Exception ex) { Log.Write("phone: newest apk: " + ex.Message); }
                Build();
            };
            Unloaded += (s, e) => PhoneJob.Changed -= OnJob;
        }

        void OnJob() => Dispatcher.BeginInvoke(new Action(Build));

        public void Retext() => Build();

        /// <summary>On the drive of the guest's work folder, where the room for its disk is; C: is often the full one.</summary>
        static string DefaultFolder(string os)
        {
            if (os == null) return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            return Path.Combine(Guests.Work(os), "phone");
        }

        Phone.Device Selected => devices.FirstOrDefault(d => d.Serial == serial);

        // --- polled every few seconds while the page is open ------------------------------------------
        public async void Tick()
        {
            await Look(false);
            var j = PhoneJob.Current;
            if (j != null && j.Running) { await j.PollPush(); UpdateJob(); }
        }

        async Task Look(bool force)
        {
            if (looking) return;
            if (adb == "") adb = Phone.FindAdb();
            if (adb == "") return;
            looking = true;
            try
            {
                var now = await Phone.List(adb);
                bool changed = force || !now.Select(d => d.Serial + d.State).SequenceEqual(devices.Select(d => d.Serial + d.State));
                if (changed)
                {
                    foreach (var d in now) { var old = devices.FirstOrDefault(x => x.Serial == d.Serial && x.Filled); if (old != null) { d.Model = old.Model; d.Android = old.Android; d.Free = old.Free; d.Ram = old.Ram; d.App = old.App; d.Filled = true; } }
                    devices = now;
                }
                if (!devices.Any(d => d.Serial == serial)) { serial = (devices.FirstOrDefault(d => d.Ready) ?? devices.FirstOrDefault())?.Serial ?? ""; changed = true; }
                var sel = Selected;
                if (sel != null && sel.Ready && (detailsOf != sel.Serial || (DateTime.Now - detailsAt).TotalSeconds > 25) && !(PhoneJob.Current?.Running ?? false))
                {
                    await Phone.Fill(adb, sel);
                    detailsOf = sel.Serial; detailsAt = DateTime.Now;
                    changed = true;
                }
                if (changed) Build();
            }
            catch (Exception e) { Log.Write("phone: " + e.Message); }
            finally { looking = false; }
        }

        // --- the page ----------------------------------------------------------------------------------
        void Build()
        {
            var job = PhoneJob.Current;
            var p = new StackPanel { MaxWidth = 860, Margin = new Thickness(30, 4, 30, 30), HorizontalAlignment = HorizontalAlignment.Left };
            var back = Ui.Btn(L.K("Back"), () => main.GoHome(), "BtnGhost", "");
            back.HorizontalAlignment = HorizontalAlignment.Left;
            back.Margin = new Thickness(-8, 0, 0, 10);
            p.Children.Add(back);
            p.Children.Add(new TextBlock { Text = L.T("Install on a phone", "Telefona kur"), Style = Ui.S("H1") });
            p.Children.Add(Ui.Text(L.T("Puts the ASoftware iOS app on your Android phone and sends it the system this PC has installed.",
                "ASoftware iOS uygulamasını Android telefonunuza kurar ve bu PC'de kurulu sistemi ona gönderir."), "Sub", 4));
            p.Children.Add(new Border { Height = 18 });

            if (job != null) p.Children.Add(JobPanel(job));
            else jobHead = null;
            p.Children.Add(Ui.Group(L.T("1 · The phone", "1 · Telefon"), PhoneRows().ToArray()));
            p.Children.Add(Ui.Group(L.T("2 · The app", "2 · Uygulama"), AppRow()));
            p.Children.Add(WhatToSend());
            if (job == null || !job.Running) p.Children.Add(SendButton());
            Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = p };
            UpdateJob();
        }

        static Border Status(string text, string tone)
        {
            var t = new TextBlock { Text = text, FontSize = 12, FontWeight = FontWeights.SemiBold };
            t.SetResourceReference(TextBlock.ForegroundProperty, tone);
            var b = new Border { Style = Ui.S("Pill"), Child = t };
            b.SetResourceReference(Border.BackgroundProperty, tone + "Soft");
            return b;
        }

        IEnumerable<UIElement> PhoneRows()
        {
            if (adb == "")
            {
                var note = toolsError != "" ? toolsError
                    : L.T("adb from Google's platform-tools, about 7 MB, into ASoftware's own folder. Google's terms for it apply.",
                          "Google'ın platform-tools paketindeki adb, yaklaşık 7 MB, ASoftware'in kendi klasörüne. Google'ın kullanım koşulları geçerlidir.");
                var stack = new StackPanel { Orientation = Orientation.Horizontal };
                var get = Ui.Btn(gettingTools ? L.T("Downloading…", "İndiriliyor…") : L.T("Download", "İndir"), GetTools, "BtnPrimary", "");
                get.IsEnabled = !gettingTools;
                AutomationProperties.SetAutomationId(get, "phone-get-tools");
                stack.Children.Add(Ui.Btn(L.T("Terms", "Koşullar"), () => MainWindow.Open(Phone.ToolsPage), "BtnGhost"));
                stack.Children.Add(Spaced(get));
                yield return Ui.Row(L.T("Android's tools are not on this PC", "Android araçları bu PC'de yok"), note, stack);
                yield break;
            }
            if (devices.Count == 0)
            {
                yield return Ui.Row(L.T("Looking for a phone…", "Telefon aranıyor…"),
                    L.T("Connect it with a USB cable. On the phone: Settings > About phone > Software information, tap Build number seven times; then Developer options > USB debugging. Allow this computer when the phone asks.",
                        "USB kabloyla bağlayın. Telefonda: Ayarlar > Telefon hakkında > Yazılım bilgileri, Yapı numarasına yedi kez dokunun; sonra Geliştirici seçenekleri > USB hata ayıklama. Telefon sorunca bu bilgisayara izin verin."),
                    Status(L.T("Not connected", "Bağlı değil"), "Warn"));
                yield break;
            }
            foreach (var d in devices)
            {
                var name = d.Model != "" ? d.Model : d.Serial;
                string desc;
                Border state;
                if (d.Ready)
                {
                    desc = d.Filled ? $"Android {d.Android} · RAM {d.Ram / 1073741824.0:0} GB · " + L.Size(d.Free) + " " + L.T("free", "boş") : L.T("Reading its details…", "Bilgileri okunuyor…");
                    state = Status(L.T("Connected", "Bağlı"), "Good");
                }
                else if (d.State == "unauthorized") { desc = L.T("Tap Allow on the phone's USB debugging prompt.", "Telefondaki USB hata ayıklama sorusunda İzin ver'e dokunun."); state = Status(L.T("Waiting for you", "Sizi bekliyor"), "Warn"); }
                else { desc = L.T("adb says: ", "adb durumu: ") + d.State; state = Status(d.State, "Warn"); }
                UIElement right = state;
                if (devices.Count > 1)
                {
                    var serialHere = d.Serial;
                    var pick = new RadioButton { GroupName = "phone", IsChecked = d.Serial == serial, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
                    pick.Checked += (s, e) => { serial = serialHere; detailsOf = ""; };
                    var sp = new StackPanel { Orientation = Orientation.Horizontal };
                    sp.Children.Add(state);
                    sp.Children.Add(pick);
                    right = sp;
                }
                yield return Ui.Row(name, desc, right);
            }
        }

        static FrameworkElement Spaced(FrameworkElement e) { e.Margin = new Thickness(8, 0, 0, 0); return e; }

        UIElement AppRow()
        {
            var d = Selected;
            string desc;
            bool canInstall = d != null && d.Ready && d.Filled && apk != null && (apkFraction < 0) && !(PhoneJob.Current?.Running ?? false);
            bool older = d != null && d.App != "" && apk != null && Updates.IsNewer(apk.Tag, d.App);
            if (d == null || !d.Ready) desc = L.T("Connect the phone first.", "Önce telefonu bağlayın.");
            else if (!d.Filled) desc = "…";
            else if (d.App == "") desc = L.T("Not on this phone yet.", "Bu telefonda henüz yok.");
            else desc = L.T("On this phone: ", "Bu telefonda: ") + d.App;
            if (apk != null) desc += "  " + L.T("Newest: ", "En yeni: ") + apk.Tag + " (" + L.Size(apk.Size) + ")";
            if (apkState != "") desc += "\n" + apkState;

            UIElement right;
            if (d != null && d.Filled && d.App != "" && !older && apkFraction < 0)
                right = Status(L.T("Installed", "Kurulu"), "Good");
            else
            {
                var b = Ui.Btn(d != null && d.App != "" ? L.T("Update", "Güncelle") : L.K("Install"), InstallApp, "BtnPrimary", "");
                b.IsEnabled = canInstall;
                AutomationProperties.SetAutomationId(b, "phone-install-app");
                right = b;
            }
            var row = Ui.Row("ASoftware iOS", desc, right);
            if (apkFraction >= 0)
            {
                apkBar = new ProgressBar { Style = Ui.S("Bar"), Maximum = 1, Value = apkFraction, Margin = new Thickness(0, 10, 0, 0) };
                var holder = new StackPanel();
                var g = row.Child;
                row.Child = null;
                holder.Children.Add(g);
                holder.Children.Add(apkBar);
                row.Child = holder;
            }
            return row;
        }

        UIElement WhatToSend()
        {
            var job = PhoneJob.Current;
            bool busy = job != null && job.Running;
            var cards = new WrapPanel();
            foreach (var g in Guests.Ids)
            {
                var id = g;
                bool have = Guests.Installed(g);
                var inside = new StackPanel();
                inside.Children.Add(new TextBlock { Text = Guests.Name(g), Style = Ui.S("H3") });
                inside.Children.Add(Ui.Text(have ? Guests.Detail(g) : L.T("Not on this PC", "Bu PC'de yok"), "Faint", 2));
                var rb = new RadioButton { Style = Ui.S("RadioCard"), Content = inside, GroupName = "phone-os", IsChecked = g == os, IsEnabled = have && !busy, Width = 244, Margin = new Thickness(0, 0, 10, 10) };
                AutomationProperties.SetAutomationId(rb, "phone-os-" + g);
                rb.Checked += (s, e) => { os = id; folder = DefaultFolder(id); Build(); };
                cards.Children.Add(rb);
            }
            var outer = new StackPanel { Margin = new Thickness(0, 0, 0, 22) };
            outer.Children.Add(Ui.Dyn(new TextBlock { Text = L.T("3 · What to send", "3 · Ne gönderilsin"), Style = Ui.S("H3"), FontSize = 12.5, Margin = new Thickness(4, 0, 0, 8) }, TextBlock.ForegroundProperty, "Text2"));
            outer.Children.Add(cards);
            if (Guests.Ids.Any(g => !Guests.Installed(g)))
                outer.Children.Add(Ui.Text(L.T("What is not on this PC can also be installed by the app itself, from Apple: open it on the phone and choose Set up.",
                    "Bu PC'de olmayanı uygulama kendisi de Apple'dan kurabilir: telefonda açıp Kurulum'u seçin."), "Faint", 2));
            var rows = new List<UIElement>();
            if (os == "ios16")
                rows.Add(Ui.Row(L.T("With what iOS wrote on this PC", "iOS'un bu PC'de yazdıklarıyla"), L.T("Your settings and apps go too; without it the phone gets iOS as it was installed.", "Ayarlarınız ve uygulamalarınız da gider; açık değilse telefona kurulduğu hâliyle gider."),
                    Ui.Switch(withData, v => withData = v, null, !busy)));
            rows.Add(Ui.Row(L.T("Only make the file", "Yalnız dosyayı yap"), L.T("To copy it to the phone yourself, then pick it in the app (Set up > Choose file).", "Telefona kendiniz kopyalayıp uygulamada seçmek için (Kurulum > Dosya seç)."),
                Ui.Switch(fileOnly, v => { fileOnly = v; Build(); }, null, !busy)));
            var free = folder != null ? Native.FreeBytes(folder) : 0;
            var change = Ui.Btn(L.K("Browse"), () => { var f = Ui.Pick(L.T("Where to make the file", "Dosya nerede yapılsın"), folder); if (f != null) { folder = f; Build(); } }, "Btn", "");
            change.IsEnabled = !busy;
            rows.Add(Ui.Row(L.T("Where to make it", "Nerede yapılsın"), folder + " · " + L.Size(free) + " " + L.T("free", "boş"), change));
            if (!fileOnly)
                rows.Add(Ui.Row(L.T("Delete this PC's copy once it is on the phone", "Telefona gidince bu PC'deki kopyayı sil"), L.T("The file is several GB; the phone has its own after this.", "Dosya birkaç GB; bundan sonra telefonda kendi kopyası var."),
                    Ui.Switch(dropAfter, v => dropAfter = v, null, !busy)));
            outer.Children.Add(Ui.Group(null, rows.ToArray()));
            outer.Children[outer.Children.Count - 1].SetValue(MarginProperty, new Thickness(0, 8, 0, 0));
            return outer;
        }

        UIElement JobPanel(PhoneJob j)
        {
            var sp = new StackPanel();
            jobHead = new TextBlock { Style = Ui.S("H3"), FontSize = 15 };
            jobSub = Ui.Text("", "Sub", 2);
            jobBar = new ProgressBar { Style = Ui.S("Bar"), Height = 8, Maximum = 1000, Margin = new Thickness(0, 10, 0, 0) };
            AutomationProperties.SetAutomationId(jobHead, "phone-job");
            sp.Children.Add(jobHead); sp.Children.Add(jobSub); sp.Children.Add(jobBar);
            var items = new List<UIElement>();
            if (j.Running) items.Add(Ui.Btn(L.K("StopNow"), () => j.Stop(), "BtnDanger", "\uE71A"));
            items.Add(Ui.Btn(L.K("ShowLog"), () => { showLog = !showLog; Build(); }, "BtnGhost", "\uE9F9"));
            if (j.Result == "failed")
                items.Add(Ui.Btn(L.T("Report this", "Bunu bildir"), () => main.OpenReport("phone", L.T("Sending to the phone failed: ", "Telefona gönderim başarısız: ") + Guests.Name(j.Os), j.Message), "BtnGhost", "\uEBE8"));
            if (j.Result == "done" && !j.Send)
                items.Add(Ui.Btn(L.T("Show the file", "Dosyayı göster"), () => System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + j.Out + "\""), "Btn", "\uE838"));
            var row = Ui.Hstack(items.ToArray());
            row.Margin = new Thickness(0, 12, 0, 0);
            sp.Children.Add(row);
            if (showLog)
            {
                logBox = new TextBox { Style = Ui.S("Field"), IsReadOnly = true, FontFamily = Ui.F("Mono"), FontSize = 11.5, Height = 220, AcceptsReturn = true, TextWrapping = TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalContentAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 12, 0, 0) };
                sp.Children.Add(logBox);
            }
            else logBox = null;
            var box = new Border { Child = sp, Padding = new Thickness(18, 16, 18, 16), CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 0, 22) };
            box.SetResourceReference(Border.BackgroundProperty, "Surface");
            box.SetResourceReference(Border.BorderBrushProperty, "Line");
            return box;
        }

        UIElement SendButton()
        {
            var d = Selected;
            bool haveTarget = fileOnly || (d != null && d.Ready);
            var go = Ui.Btn(fileOnly ? L.T("Make the file", "Dosyayı yap") : L.T("Send to the phone", "Telefona gönder"), Send, "BtnPrimary", fileOnly ? "\uE74E" : "\uE8EA");
            go.IsEnabled = os != null && Guests.Installed(os) && haveTarget;
            go.HorizontalAlignment = HorizontalAlignment.Left;
            AutomationProperties.SetAutomationId(go, "phone-send");
            return go;
        }

        void UpdateJob()
        {
            var j = PhoneJob.Current;
            if (j == null || jobHead == null) return;
            switch (j.Result)
            {
                case "done":
                    jobHead.Text = j.Send ? L.T("Sent", "Gönderildi") : L.T("The file is ready", "Dosya hazır");
                    jobSub.Text = j.Send
                        ? (j.Sent ? L.T($"On the phone: open ASoftware iOS, Set up > Import {PhoneJob.FileName(j.Os)}.", $"Telefonda: ASoftware iOS'u açın, Kurulum > İçe aktar {PhoneJob.FileName(j.Os)}.")
                                  : L.T("adb did not see the phone at the end: copy the file yourself. ", "adb sonda telefonu görmedi: dosyayı kendiniz kopyalayın. ") + j.Out)
                        : j.Out + "  " + L.T("Copy it to the phone, then in the app: Set up > Choose file.", "Telefona kopyalayın, sonra uygulamada: Kurulum > Dosya seç.");
                    break;
                case "failed": jobHead.Text = L.T("It stopped", "Durdu"); jobSub.Text = j.Message; break;
                case "stopped": jobHead.Text = L.T("Stopped", "Durduruldu"); jobSub.Text = L.T("Its temporary files are removed.", "Geçici dosyaları silindi."); break;
                default: jobHead.Text = Guests.Name(j.Os) + " · " + j.StepText(); jobSub.Text = j.Out; break;
            }
            jobHead.SetResourceReference(TextBlock.ForegroundProperty, j.Result == "failed" ? "Bad" : j.Result == "done" ? "Good" : "Text");
            jobBar.Value = 1000 * j.Fraction();
            jobBar.Visibility = j.Result == "stopped" || j.Result == "failed" ? Visibility.Collapsed : Visibility.Visible;
            if (logBox != null)
            {
                logBox.Text = string.Join("\r\n", j.Runner.Lines.Skip(Math.Max(0, j.Runner.Lines.Count - 300)));
                logBox.ScrollToEnd();
            }
        }

        // --- what the buttons do -----------------------------------------------------------------------
        async void GetTools()
        {
            gettingTools = true; toolsError = ""; Build();
            try
            {
                stop = new CancellationTokenSource();
                await Phone.GetTools(f => { }, stop.Token);
                adb = Phone.FindAdb();
            }
            catch (Exception e) { toolsError = L.T("Could not download: ", "İndirilemedi: ") + e.Message; Log.Write("platform-tools: " + e); }
            gettingTools = false;
            Build();
            await Look(true);
        }

        async void InstallApp()
        {
            var d = Selected;
            if (d == null || apk == null) return;
            var file = Path.Combine(AppPaths.LocalData, "downloads", apk.Name);
            try
            {
                apkState = L.T("Downloading the app…", "Uygulama indiriliyor…");
                apkFraction = 0; Build();
                stop = new CancellationTokenSource();
                bool whole = File.Exists(file) && new FileInfo(file).Length == (long)apk.Size;
                if (!whole) await Phone.Download(apk.Url, file, f => Dispatcher.BeginInvoke(new Action(() => { apkFraction = f; if (apkBar != null) apkBar.Value = f; })), stop.Token);
                apkState = L.T("Installing it on the phone…", "Telefona kuruluyor…");
                apkFraction = 1; Build();
                var err = await Phone.InstallApk(adb, d.Serial, file);
                apkState = err;
                if (err == "") main.Snack(L.T("The app is on the phone.", "Uygulama telefonda."), "good");
            }
            catch (Exception e) { apkState = e.Message; Log.Write("phone: install app: " + e); }
            apkFraction = -1;
            detailsOf = "";
            await Look(true);
            Build();
        }

        void Send()
        {
            if (os == null) return;
            if (Machines.Runs.ContainsKey(os))
            {
                Dialog.Show(main, L.T($"{Guests.Name(os)} is running", $"{Guests.Name(os)} çalışıyor"), L.T("Its disk is in use. Save and close it first.", "Diski kullanımda. Önce kaydedip kapatın."), L.K("OK"));
                return;
            }
            var d = Selected;
            if (!fileOnly && d != null && d.Free > 0 && d.Free < 12e9
                && Dialog.Show(main, L.T("Little room on the phone", "Telefonda yer az"), L.T($"It has {L.Size(d.Free)} free; the file and the disk it becomes need more. Send it anyway?", $"{L.Size(d.Free)} boş; dosya ve açılınca oluşan disk daha fazlasını ister. Yine de gönderilsin mi?"),
                    L.T("Send anyway", "Yine de gönder"), L.K("Cancel")) != 0) return;
            var free = Native.FreeBytes(folder);
            if (free > 0 && free < 10e9
                && Dialog.Show(main, L.T("Little room on this drive", "Bu sürücüde yer az"), L.T($"{L.Size(free)} free where the file is made. The packed disk is there twice for a moment. Go on anyway?", $"Dosyanın yapıldığı yerde {L.Size(free)} boş. Paketlenen disk bir an orada iki kez bulunur. Yine de sürsün mü?"),
                    L.T("Go on", "Devam et"), L.K("Cancel")) != 0) return;
            try
            {
                PhoneJob.Start(os, folder, withData, adb, fileOnly ? "" : serial, dropAfter);
            }
            catch (Exception e) { Dialog.Show(main, L.T("It did not start", "Başlamadı"), e.Message, L.K("OK")); }
        }
    }
}
