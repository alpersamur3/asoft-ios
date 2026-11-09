using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using ASoftware.Engine;

namespace ASoftware.Views
{
    public sealed class Relay : ICommand
    {
        readonly Action run; readonly Func<bool> can;
        public Relay(Action run, Func<bool> can = null) { this.run = run; this.can = can; }
        public event EventHandler CanExecuteChanged { add => CommandManager.RequerySuggested += value; remove => CommandManager.RequerySuggested -= value; }
        public bool CanExecute(object p) => can?.Invoke() ?? true;
        public void Execute(object p) => run();
    }

    public abstract class Vm : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Set<T>(ref T f, T v, [CallerMemberName] string n = null)
        {
            if (Equals(f, v)) return;
            f = v;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
        }
        protected void Raise(string n) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
    }

    /// <summary>One OS on the home page's shelf: its device, its state, what it is doing and its buttons.</summary>
    public sealed class OsCardVm : Vm
    {
        public string Os { get; }
        public bool Later => Os == "vision";
        public bool HasActions => !Later;
        public string Name => Guests.Name(Os);
        public string Detail => Guests.Detail(Os);

        /// <summary>The phones' height on the shelf: 236 px, down to 170 in a short window (MainWindow.FitDevices).</summary>
        public const double PhoneMax = 236, PhoneMin = 170;
        double phone = PhoneMax;
        public double Phone
        {
            get => phone;
            set { if (Math.Abs(phone - value) < 0.5) return; phone = value; Raise(nameof(DeviceHeight)); Raise(nameof(DeviceRow)); }
        }
        /// <summary>The watch with its band stands at 0.85 of a phone, the headset at 0.555 (about 214 px wide).</summary>
        public double DeviceHeight => Math.Round(Os == "watch" ? phone * 0.85 : Os == "vision" ? phone * 0.555 : phone);
        /// <summary>The devices' row: a phone's height and room for its lift.</summary>
        public GridLength DeviceRow => new GridLength(Math.Round(phone) + 8);
        public ICommand PrimaryCmd { get; }
        public ICommand MoreCmd { get; }
        public ICommand SaveCloseCmd { get; }
        public ICommand TurnOffCmd { get; }
        /// <summary>A click on the device opens the system's page, as its "more" button does.</summary>
        public ICommand DeviceCmd => Later ? null : MoreCmd;

        string state = "", line1 = "", line2 = "", primary = "", stateKey = "Idle";
        double progress, deviceProgress = -1; bool showProgress, running, primaryEnabled = true, canSave, busy, present = true, awake, outline;
        System.Windows.Media.ImageSource shot;
        // (a number keeps its unit on the narrow column: "5 GB", not "5" at a line's end)
        public string StateText { get => state; set => Set(ref state, Ui.KeepUnits(value)); }
        public string Line1 { get => line1; set => Set(ref line1, Ui.KeepUnits(value)); }
        public string Line2 { get => line2; set => Set(ref line2, Ui.KeepUnits(value)); }
        public string Primary { get => primary; set => Set(ref primary, value); }
        public bool PrimaryEnabled { get => primaryEnabled; set => Set(ref primaryEnabled, value); }
        public double Progress { get => progress; set => Set(ref progress, value); }
        public bool ShowProgress { get => showProgress; set => Set(ref showProgress, value); }
        public bool Running { get => running; set => Set(ref running, value); }
        public bool CanSave { get => canSave; set => Set(ref canSave, value); }
        public bool Busy { get => busy; set => Set(ref busy, value); }
        /// <summary>The device: installed, running, and how far its install is (negative: not installing).</summary>
        public bool Present { get => present; set => Set(ref present, value); }
        public bool Awake { get => awake; set => Set(ref awake, value); }
        public double DeviceProgress { get => deviceProgress; set => Set(ref deviceProgress, value); }
        /// <summary>The system's last screen (Engine\Thumbs), or null.</summary>
        public System.Windows.Media.ImageSource Shot { get => shot; set => Set(ref shot, value); }
        /// <summary>The main button: the light capsule for a system that is there, its outline for one to install.</summary>
        public Style PrimaryStyle => (Style)Application.Current.Resources[outline ? "Btn" : "BtnPrimary"];
        void Outline(bool o) { if (outline != o) { outline = o; Raise(nameof(PrimaryStyle)); } }
        public Brush StateBrush => (Brush)Application.Current.Resources[stateKey];
        void Tone(string key) { if (stateKey != key) { stateKey = key; Raise(nameof(StateBrush)); } }

        public string MoreText => L.K("More");
        // (UI Automation ids: tests drive the cards through them)
        public string PrimaryId => "primary-" + Os;
        public string MoreId => "more-" + Os;
        public string SaveId => "saveclose-" + Os;
        public string OffId => "turnoff-" + Os;
        public string StateId => "state-" + Os;
        public string SaveCloseText => L.K("SaveClose");
        public string TurnOffText => L.K("TurnOff");

        /// <summary>The newest quick save of this OS's disk (asoft-quick), looked up in the background.</summary>
        public Guests.Snap Quick;
        public DateTime QuickLooked;

        /// <summary>The screenshots' made-up state (-shot with -state), or null.</summary>
        public readonly string Test;

        readonly MainWindow main;

        public OsCardVm(string os, MainWindow w)
        {
            Os = os; main = w;
            Test = TestState(os);
            PrimaryCmd = new Relay(() => main.Primary(this));
            MoreCmd = new Relay(() => main.OpenOs(Os), () => !Later);
            SaveCloseCmd = new Relay(() => main.SaveClose(Os));
            TurnOffCmd = new Relay(() => main.TurnOff(Os));
        }

        public void Retext() { Raise(nameof(MoreText)); Raise(nameof(SaveCloseText)); Raise(nameof(TurnOffText)); Raise(nameof(StateBrush)); Raise(nameof(PrimaryStyle)); }

        public void LoadShot() => Shot = Later ? null : Thumbs.Get(Os);

        public string Action = "";   // what Primary does: install, resume-install, show-install, start, show, none

        public void Refresh()
        {
            ShowProgress = false; Running = false; CanSave = false; Busy = false; PrimaryEnabled = true; Line2 = "";
            double device = -1; bool there = true, up = false;
            try { State(ref device, ref there, ref up); }
            finally
            {
                Present = there; Awake = up; DeviceProgress = device;
                Outline(Action == "install" || Action == "show-install");
                LoadShot();
            }
        }

        void State(ref double device, ref bool there, ref bool up)
        {
            if (Later)
            {
                StateText = L.K("ComingLater"); Tone("Idle");
                Line1 = L.T("Runs on this PC from local builds; it comes to the installer in a later version.", "Bu PC'de yerel derlemelerle çalışıyor; kurucuya sonraki bir sürümde gelecek.");
                Primary = L.K("ComingLater"); PrimaryEnabled = false; Action = "none";
                return;
            }
            var c = Guests.Cfg(Os);
            var job = InstallJob.Current;
            bool fakeInstall = Test != null && Test.StartsWith("install");
            bool inJob = fakeInstall || job != null && job.Running && job.Plan.Any(p => p.Os == Os);
            Machines.Runs.TryGetValue(Os, out var run);
            if (run != null && Native.Alive(run.QemuPid) || run != null && run.QemuPid == 0)
            {
                Running = run.QemuPid != 0;
                if (run.QemuPid == 0) { StateText = L.T("Starting…", "Başlatılıyor…"); Tone("Info"); Primary = L.T("Starting…", "Başlatılıyor…"); PrimaryEnabled = false; Action = "none"; Line1 = ""; return; }
                up = true;
                var uptime = DateTime.Now - run.Started;
                switch (run.Busy)
                {
                    case "saving": StateText = L.T("Saving…", "Kaydediliyor…"); Tone("Warn"); Busy = true; break;
                    case "stopping": StateText = L.T("Turning off…", "Kapatılıyor…"); Tone("Warn"); Busy = true; break;
                    case "loading": StateText = L.T("Loading a save…", "Kayıt yükleniyor…"); Tone("Warn"); Busy = true; break;
                    default: StateText = L.T("Running", "Çalışıyor") + (run.Ours ? " · " + L.Duration(uptime.TotalSeconds) : ""); Tone("Good"); break;
                }
                Line1 = $"{run.Smp} vCPU · {run.RamMiB / 1024.0:0.#} GB · " + (run.Disk == "" ? L.T("throwaway disk", "atılan disk") : L.T("keeps changes", "değişiklikleri saklar"));
                Line2 = run.Ours ? "" : L.T("Started outside the launcher (pid ", "Başlatıcı dışında açıldı (pid ") + run.QemuPid + ")";
                CanSave = run.Disk != "" && run.QuickBoot && !Busy;
                Primary = L.T("Show window", "Pencereyi göster"); Action = "show"; PrimaryEnabled = !Busy;
                return;
            }
            if (inJob)
            {
                List<PlanStep> steps;
                Func<PlanStep, double> part;
                bool pauseAsked;
                if (fakeInstall) { steps = TestPlan(); part = p => p.Pct / 100.0; pauseAsked = false; }
                else { steps = job.Plan.Where(p => p.Os == Os).ToList(); part = job.StepFraction; pauseAsked = job.PauseAsked; }
                var now = steps.FirstOrDefault(p => p.State == "running");
                int n = steps.FindIndex(p => p.State == "running") + 1;
                if (now != null)
                {
                    StateText = L.T($"Installing · step {n} of {steps.Count}", $"Kuruluyor · adım {n}/{steps.Count}"); Tone("Info");
                    Line1 = now.Text != "" ? now.Text : now.Title;
                    double left = steps.Where(p => p.State == "pending").Sum(p => p.Seconds) + Math.Max(now.Seconds * (1 - part(now)), 0.1 * now.Seconds);
                    Line2 = "~" + L.Duration(left) + " " + L.T("left", "kaldı");
                }
                else if (steps.All(p => p.State == "pending" || p.State == "skip"))
                {
                    StateText = L.T("Waiting to install", "Kurulum sırası bekleniyor"); Tone("Info");
                    Line1 = L.T("after the OS before it in this install", "bu kurulumda önceki işletim sisteminden sonra");
                }
                else { StateText = L.T("Installing", "Kuruluyor"); Tone("Info"); }
                double all = steps.Where(p => p.State != "skip").Sum(p => p.Seconds), done = steps.Where(p => p.State == "done").Sum(p => p.Seconds) + (now != null ? now.Seconds * part(now) : 0);
                Progress = all > 0 ? 100 * done / all : 0; ShowProgress = true;
                device = Progress;
                Primary = L.T("Show progress", "İlerlemeyi göster"); Action = "show-install";
                if (pauseAsked) Line2 = L.T("pausing after this step", "bu adımdan sonra duraklayacak");
                return;
            }
            if (Test == "none" || !Guests.Installed(Os))
            {
                there = false;
                (int done, int total) m = Test == "none" ? (0, 0) : Guests.Markers(Os);
                if (m.done > 0)
                {
                    StateText = L.T($"Install stopped · {m.done} of {m.total} steps", $"Kurulum durdu · {m.total} adımın {m.done}'i bitti"); Tone("Warn");
                    Line1 = L.T("It goes on where it stopped.", "Kaldığı yerden devam eder.");
                    Progress = 100.0 * m.done / Math.Max(1, m.total); ShowProgress = true;
                    device = Progress;
                    Primary = L.T("Resume install", "Kuruluma devam et"); Action = "resume-install";
                }
                else
                {
                    StateText = L.T("Not installed", "Kurulu değil"); Tone("Idle");
                    Line1 = Os == "ios16" ? L.T("About 40 min · 6.4 GB from Apple · 13 GB of disk", "Yaklaşık 40 dk · Apple'dan 6,4 GB · 13 GB disk")
                          : Os == "ios26" ? L.T("About 1.5–2.5 h · 11 GB from Apple · 23 GB of disk; a Vulkan GPU", "Yaklaşık 1,5–2,5 sa · Apple'dan 11 GB · 23 GB disk; Vulkan GPU")
                          // (the watch needs only the base it shares with iOS 26: made here when neither is there)
                          : Guests.HasWatchBase() ? L.T("About 40 min · 5 GB from Apple · 14 GB of disk", "Yaklaşık 40 dk · Apple'dan 5 GB · 14 GB disk")
                          : L.T("About 1 h · 6 GB from Apple · 16 GB of disk; no\u00a0iOS 26 needed", "Yaklaşık 1 sa · Apple'dan 6 GB · 16 GB disk; iOS 26 gerekmez");
                    Primary = L.K("Install"); Action = "install";
                    if (job != null && job.Running) PrimaryEnabled = false;
                }
                return;
            }
            // ready
            if (Test == "saved") Quick = new Guests.Snap { Name = Guests.QuickName, When = DateTime.Now.AddHours(-2) };
            else if (Test == "ready") Quick = null;
            bool keep = c.DiskMode != "throwaway";
            Line1 = $"{c.Smp} vCPU · {Guests.Ram(Os) / 1024.0:0.#} GB · " + (keep ? L.T("keeps changes", "değişiklikleri saklar") : L.T("throwaway disk", "atılan disk"));
            // a save no start has resumed yet, made with the settings it has now (else the start boots afresh with them,
            // and the save becomes the way back: Machines.Start)
            if (Test == "saved" || keep && c.QuickBoot && Quick != null && !Quick.WayBack && Guests.Fits(Os, LauncherConfig.Current.FindSave(Guests.SaveDisk(Os), Guests.QuickName), Guests.Shape(Os)))
            {
                StateText = L.T("Saved", "Kaydedildi"); Tone("Accent");
                Line2 = L.T("Resumes where you left it · ", "Bıraktığınız yerden açılır · ") + Guests.When(Quick.When);
                Primary = L.K("Resume"); Action = "start";
            }
            else
            {
                StateText = L.T("Ready", "Hazır"); Tone("Idle");
                Primary = L.K("Start"); Action = "start";
                // a start boots it afresh from its disk; the last quick save stays, to go back to (the Saves tab)
                if (keep && Quick != null) Line2 = L.T("Way back: ", "Geri dönüş noktası: ") + Guests.When(Quick.When);
            }
        }

        // --- test states, for screenshots of what the test bed does not have (with -shot only) ----------------
        /// <summary>-state os=kind[,os=kind]: running, saving, stopping, starting, saved, ready, none (not installed),
        /// install:NN (installing, NN %).</summary>
        public static string TestState(string os)
        {
            var a = Program.Arg("-shot") != null ? Program.Arg("-state") : null;
            if (a == null) return null;
            foreach (var p in a.Split(','))
            {
                var kv = p.Split('=');
                if (kv.Length == 2 && kv[0].Trim() == os) return kv[1].Trim();
            }
            return null;
        }

        /// <summary>A made-up install of ten steps, NN % through.</summary>
        List<PlanStep> TestPlan()
        {
            int pct = int.TryParse(Test.Split(':').Last(), out var n) ? Math.Max(0, Math.Min(99, n)) : 40;
            var list = new List<PlanStep>();
            for (int i = 0; i < 10; i++)
            {
                var s = new PlanStep { Os = Os, Id = "step" + i, Seconds = 600, Title = L.T("Building the disk", "Disk kuruluyor") };
                if (i < pct / 10) s.State = "done";
                else if (i == pct / 10) { s.State = "running"; s.Pct = pct % 10 * 10; s.Title = L.T("Downloading from Apple", "Apple'dan indiriliyor"); }
                list.Add(s);
            }
            return list;
        }
    }
}
