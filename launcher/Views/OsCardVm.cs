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

    /// <summary>One OS's card on the home page: its state, what it is doing and its buttons.</summary>
    public sealed class OsCardVm : Vm
    {
        public string Os { get; }
        public bool Later => Os == "vision";
        public string Name => Guests.Name(Os);
        public string Detail => Guests.Detail(Os);
        public Brush Gradient => Theme.OsGradient(Os);
        public ICommand PrimaryCmd { get; }
        public ICommand MoreCmd { get; }
        public ICommand SaveCloseCmd { get; }
        public ICommand TurnOffCmd { get; }

        string state = "", line1 = "", line2 = "", primary = "", stateKey = "Text3", primaryIcon = "";
        double progress; bool showProgress, running, primaryEnabled = true, canSave, busy;
        public string StateText { get => state; set => Set(ref state, value); }
        public string Line1 { get => line1; set => Set(ref line1, value); }
        public string Line2 { get => line2; set => Set(ref line2, value); }
        public string Primary { get => primary; set => Set(ref primary, value); }
        public string PrimaryIcon { get => primaryIcon; set => Set(ref primaryIcon, value); }
        public bool PrimaryEnabled { get => primaryEnabled; set => Set(ref primaryEnabled, value); }
        public double Progress { get => progress; set => Set(ref progress, value); }
        public bool ShowProgress { get => showProgress; set => Set(ref showProgress, value); }
        public bool Running { get => running; set => Set(ref running, value); }
        public bool CanSave { get => canSave; set => Set(ref canSave, value); }
        public bool Busy { get => busy; set => Set(ref busy, value); }
        public Brush StateBrush => (Brush)Application.Current.Resources[stateKey];
        public Brush StateSoft => (Brush)Application.Current.Resources[stateKey == "Text3" ? "Surface2" : stateKey + "Soft"];
        void Tone(string key) { if (stateKey != key) { stateKey = key; Raise(nameof(StateBrush)); Raise(nameof(StateSoft)); } }

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

        readonly MainWindow main;

        public OsCardVm(string os, MainWindow w)
        {
            Os = os; main = w;
            PrimaryCmd = new Relay(() => main.Primary(this));
            MoreCmd = new Relay(() => main.OpenOs(Os), () => !Later);
            SaveCloseCmd = new Relay(() => main.SaveClose(Os));
            TurnOffCmd = new Relay(() => main.TurnOff(Os));
        }

        public void Retext() { Raise(nameof(MoreText)); Raise(nameof(SaveCloseText)); Raise(nameof(TurnOffText)); Raise(nameof(StateBrush)); Raise(nameof(StateSoft)); Raise(nameof(Gradient)); }

        public string Action = "";   // what Primary does: install, resume-install, show-install, start, show, none

        public void Refresh()
        {
            ShowProgress = false; Running = false; CanSave = false; Busy = false; PrimaryEnabled = true; Line2 = "";
            if (Later)
            {
                StateText = L.K("ComingLater"); Tone("Text3");
                Line1 = L.T("Runs on this PC from local builds; it comes to the installer in a later version.", "Bu PC'de yerel derlemelerle çalışıyor; kurucuya sonraki bir sürümde gelecek.");
                Primary = L.K("ComingLater"); PrimaryIcon = "\uE823"; PrimaryEnabled = false; Action = "none";
                return;
            }
            var c = Guests.Cfg(Os);
            var job = InstallJob.Current;
            bool inJob = job != null && job.Running && job.Plan.Any(p => p.Os == Os);
            Machines.Runs.TryGetValue(Os, out var run);
            if (run != null && Native.Alive(run.QemuPid) || run != null && run.QemuPid == 0)
            {
                Running = run.QemuPid != 0;
                if (run.QemuPid == 0) { StateText = L.T("Starting…", "Başlatılıyor…"); Tone("Info"); Primary = L.T("Starting…", "Başlatılıyor…"); PrimaryEnabled = false; Action = "none"; PrimaryIcon = "\uE768"; Line1 = ""; return; }
                var up = DateTime.Now - run.Started;
                switch (run.Busy)
                {
                    case "saving": StateText = L.T("Saving…", "Kaydediliyor…"); Tone("Warn"); Busy = true; break;
                    case "stopping": StateText = L.T("Turning off…", "Kapatılıyor…"); Tone("Warn"); Busy = true; break;
                    case "loading": StateText = L.T("Loading a save…", "Kayıt yükleniyor…"); Tone("Warn"); Busy = true; break;
                    default: StateText = L.T("Running", "Çalışıyor") + (run.Ours ? " · " + L.Duration(up.TotalSeconds) : ""); Tone("Good"); break;
                }
                Line1 = $"{run.Smp} vCPU · {run.RamMiB / 1024.0:0.#} GB · " + (run.Disk == "" ? L.T("throwaway disk", "atılan disk") : L.T("keeps changes", "değişiklikleri saklar"));
                Line2 = run.Ours ? "" : L.T("Started outside the launcher (pid ", "Başlatıcı dışında açıldı (pid ") + run.QemuPid + ")";
                CanSave = run.Disk != "" && run.QuickBoot && !Busy;
                Primary = L.T("Show window", "Pencereyi göster"); PrimaryIcon = "\uE8A7"; Action = "show"; PrimaryEnabled = !Busy;
                return;
            }
            if (inJob)
            {
                var steps = job.Plan.Where(p => p.Os == Os).ToList();
                var now = steps.FirstOrDefault(p => p.State == "running");
                int n = steps.FindIndex(p => p.State == "running") + 1;
                if (now != null)
                {
                    StateText = L.T($"Installing · step {n} of {steps.Count}", $"Kuruluyor · adım {n}/{steps.Count}"); Tone("Info");
                    Line1 = now.Text != "" ? now.Text : now.Title;
                    double left = steps.Where(p => p.State == "pending").Sum(p => p.Seconds) + Math.Max(now.Seconds * (1 - job.StepFraction(now)), 0.1 * now.Seconds);
                    Line2 = "~" + L.Duration(left) + " " + L.T("left", "kaldı");
                }
                else if (steps.All(p => p.State == "pending" || p.State == "skip"))
                {
                    StateText = L.T("Waiting to install", "Kurulum sırası bekleniyor"); Tone("Info");
                    Line1 = L.T("after the OS before it in this install", "bu kurulumda önceki işletim sisteminden sonra");
                }
                else { StateText = L.T("Installing", "Kuruluyor"); Tone("Info"); }
                double all = steps.Where(p => p.State != "skip").Sum(p => p.Seconds), done = steps.Where(p => p.State == "done").Sum(p => p.Seconds) + (now != null ? now.Seconds * job.StepFraction(now) : 0);
                Progress = all > 0 ? 100 * done / all : 0; ShowProgress = true;
                Primary = L.T("Show progress", "İlerlemeyi göster"); PrimaryIcon = "\uE9D9"; Action = "show-install";
                if (job.PauseAsked) Line2 = L.T("pausing after this step", "bu adımdan sonra duraklayacak");
                return;
            }
            if (!Guests.Installed(Os))
            {
                var m = Guests.Markers(Os);
                if (m.done > 0)
                {
                    StateText = L.T($"Install stopped · {m.done} of {m.total} steps", $"Kurulum durdu · {m.total} adımın {m.done}'i bitti"); Tone("Warn");
                    Line1 = L.T("It goes on where it stopped.", "Kaldığı yerden devam eder.");
                    Progress = 100.0 * m.done / Math.Max(1, m.total); ShowProgress = true;
                    Primary = L.T("Resume install", "Kuruluma devam et"); PrimaryIcon = "\uE768"; Action = "resume-install";
                }
                else
                {
                    StateText = L.T("Not installed", "Kurulu değil"); Tone("Text3");
                    Line1 = Os == "ios16" ? L.T("About 40 min · 6.4 GB from Apple · 13 GB of disk", "Yaklaşık 40 dk · Apple'dan 6,4 GB · 13 GB disk")
                          : Os == "ios26" ? L.T("About 1.5–2.5 h · 11 GB from Apple · 23 GB of disk; a Vulkan GPU", "Yaklaşık 1,5–2,5 sa · Apple'dan 11 GB · 23 GB disk; Vulkan GPU")
                          : L.T("About 30 min after iOS 26 · 5 GB from Apple · 9 GB of disk", "iOS 26'dan sonra yaklaşık 30 dk · Apple'dan 5 GB · 9 GB disk");
                    Primary = L.K("Install"); PrimaryIcon = "\uE896"; Action = "install";
                    if (job != null && job.Running) PrimaryEnabled = false;
                }
                return;
            }
            // ready
            bool keep = c.DiskMode != "throwaway";
            Line1 = $"{c.Smp} vCPU · {Guests.Ram(Os) / 1024.0:0.#} GB · " + (keep ? L.T("keeps changes", "değişiklikleri saklar") : L.T("throwaway disk", "atılan disk"));
            if (keep && c.QuickBoot && Quick != null)
            {
                StateText = L.T("Saved", "Kaydedildi"); Tone("Accent");
                Line2 = L.T("Resumes where you left it · ", "Bıraktığınız yerden açılır · ") + Quick.When.ToString(L.Tr ? "d MMM HH:mm" : "MMM d, HH:mm", L.Tr ? new System.Globalization.CultureInfo("tr-TR") : System.Globalization.CultureInfo.InvariantCulture);
                Primary = L.K("Resume"); PrimaryIcon = "\uE768"; Action = "start";
            }
            else
            {
                StateText = L.T("Ready", "Hazır"); Tone("Good");
                Primary = L.K("Start"); PrimaryIcon = "\uE768"; Action = "start";
            }
        }
    }
}
