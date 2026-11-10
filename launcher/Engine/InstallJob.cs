using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace ASoftware.Engine
{
    public class PlanStep
    {
        public string Os, Id, Title;
        public double Seconds;
        public long Download;
        public double AddGB, KeepGB;
        public string State = "pending";   // pending, running, done, skip, fail
        public int Pct = -1;               // the installer's own percent, if it says
        public string Text = "";           // what it says it does
        public DateTime Started;
    }

    public class Estimate
    {
        public List<PlanStep> Plan = new List<PlanStep>();
        public Dictionary<string, double[]> Options = new Dictionary<string, double[]>();   // key -> dl, s, peak, after
        public double Download, Seconds, Peak, After, Need, Free;
        public string Bandwidth = "";
        public List<string> Warnings = new List<string>(), Stops = new List<string>();
        public List<string> Output = new List<string>();
        public int Code;
    }

    /// <summary>The install the launcher runs: installer\Setup-ASoftware.ps1 with the wizard's answers, followed by its
    /// progress lines. One at a time; it survives the wizard being closed (the cards show it).</summary>
    public sealed class InstallJob
    {
        public static InstallJob Current { get; private set; }
        public static event Action Changed;

        public InstallChoice Choice { get; }
        public Runner Runner { get; private set; }
        public List<PlanStep> Plan = new List<PlanStep>();
        public DateTime Started;
        public string Result = "";          // "", done, paused, failed, restart
        public string Message = "";
        public bool PauseAsked;
        public string Ios26Work => Path.Combine(Choice.Dir, "work");

        InstallJob(InstallChoice c) { Choice = c; }

        static string Setup => Path.Combine(AppPaths.Root, "installer", "Setup-ASoftware.ps1");

        public static string Args(InstallChoice c, string mode)
        {
            var a = new List<string>();
            // watchOS or visionOS without iOS 26: Setup makes only the base they share
            string ver = c.Ios16 && c.Ios26 ? "both" : c.Ios26 ? "ios26" : c.Watch ? (c.Ios16 ? "ios16-watchos" : "watchos") : c.Vision ? (c.Ios16 ? "ios16-visionos" : "visionos") : "ios16";
            a.Add("-Version"); a.Add(ver);
            if (c.Ios26 || c.Watch || c.Vision)
            {
                a.Add("-Watch"); a.Add(c.Watch ? "yes" : "no");
                a.Add("-Vision"); a.Add(c.Vision ? "yes" : "no");
                a.Add("-Linux"); a.Add(c.Linux);
            }
            a.Add("-Dir"); a.Add(Runner.Q(c.Dir));
            a.Add("-Lang"); a.Add(L.Lang);
            if (mode != null) a.Add(mode);
            else { a.Add("-Yes"); a.Add("-IfNoWsl"); a.Add("install"); }
            // watchOS's QEMU: a folder of one when this PC has a separate build, as Setup's -WatchQemu
            // (else Setup takes the release package's, which has the watch's devices from 0.3.0 on)
            if (c.Watch)
            {
                var wq = WatchQemu(c);
                if (wq != "") { a.Add("-WatchQemu"); a.Add(Runner.Q(wq)); }
            }
            // visionOS's QEMU (the one every guest runs on, with visionOS's options): a build this PC has, as Setup's
            // -VisionQemu (else Setup takes work\qemu or the package's qemu\bin when they have the options)
            if (c.Vision)
            {
                var vq = Environment.GetEnvironmentVariable("ASOFT_VISION_QEMU");
                if (!string.IsNullOrEmpty(vq) && File.Exists(Path.Combine(vq, "qemu-system-aarch64.exe"))) { a.Add("-VisionQemu"); a.Add(Runner.Q(vq)); }
            }
            return string.Join(" ", a);
        }

        // Install-visionOS.ps1's steps in Turkish (the installer writes its titles in English)
        static readonly Dictionary<string, string> VisionTr = new Dictionary<string, string>
        {
            ["check"] = "Üzerine kurulduğu iOS 26 tabanı, WSL ve araçları, betikler",
            ["qemu"] = "Tüm konukların çalıştığı QEMU, visionOS seçenekleriyle (qemu\\)",
            ["rooms"] = "Altı sentetik oda, Apple'ın visionOS Simulator Runtime'ından",
            ["ipsw"] = "visionOS 27.2 IPSW: trust cache, aygıt ağacı, OS kalıbının anahtarı ve dizini",
            ["firmware"] = "visionOS çekirdeği ve aygıt ağaçları (4, 6 ve 8 vCPU)",
            ["gpu"] = "visionOS için konuk GPU sürücüsü",
            ["rootfs"] = "Kök disk, Apple'ın OS kalıbından okunur (visionos\\rootv.qcow2)",
            ["audio"] = "virtio-snd ses eklentisi (VPhoneVirtIOSound), varsa",
            ["patches"] = "Üstüne yamalar, tercihler, uygulamalar, odalar, klavye kamerası ve GPU sürücüsü",
            ["trustcache"] = "Trust cache'i (visionos\\rootv.tc)",
            ["firstboot"] = "İlk açılış (visionos\\rootv-b.qcow2)",
            ["persona"] = "Persona, MobileGestalt, etkinleştirme ve visionOS tercihleri",
            ["homeboot"] = "İkinci açılış, Home'a kadar",
            ["disks"] = "Sessiz ve sesli diskler",
            ["cleanup"] = "Yalnız kurulumun gerektirdiklerini sil",
            ["shortcut"] = "Start-visionOS.cmd ve Başlat menüsü kısayolu",
        };

        // what its two boots say while they wait (pct lines)
        static readonly Dictionary<string, string> VisionTextTr = new Dictionary<string, string>
        {
            ["waiting for the persona manifest"] = "persona bildirimi bekleniyor",
            ["waiting for Home"] = "Home bekleniyor",
        };

        /// <summary>A step's title in the launcher's language: the installer's own, or for visionOS's steps in Turkish ours.</summary>
        static string Title(string os, string id, string given) =>
            os == "vision" && L.Tr && VisionTr.TryGetValue(id, out var tr) ? tr : given;

        static string StepText(string os, string given) =>
            os == "vision" && L.Tr && VisionTextTr.TryGetValue(given ?? "", out var tr) ? tr : given;

        /// <summary>A QEMU with the watch's devices this PC has: the install's own (work\qemu-watch) or a known one.</summary>
        public static string WatchQemu(InstallChoice c)
        {
            var own = Path.Combine(c.Dir, "work", "qemu-watch");
            if (File.Exists(Path.Combine(own, "qemu-system-aarch64.exe"))) return "";
            var env = Environment.GetEnvironmentVariable("ASOFT_WATCH_QEMU");
            if (!string.IsNullOrEmpty(env) && File.Exists(Path.Combine(env, "qemu-system-aarch64.exe"))) return env;
            var pkg = Path.Combine(AppPaths.Root, "qemu-watch");
            if (File.Exists(Path.Combine(pkg, "qemu-system-aarch64.exe"))) return pkg;
            return "";
        }

        /// <summary>Setup's own estimate for a choice (its -Estimate, with the preflight's warnings).</summary>
        public static async Task<Estimate> Estimate(InstallChoice c)
        {
            var e = new Estimate();
            var log = Path.Combine(AppPaths.LocalData, "logs", "estimate.log");
            var r = new Runner(Setup, Args(c, "-Estimate"), log);
            r.Progress += f => Parse(e, f);
            r.Line += l => { lock (e.Output) e.Output.Add(l); };
            var done = new TaskCompletionSource<int>();
            r.Exited += code => done.TrySetResult(code);
            r.Start(null, AppPaths.Root);
            e.Code = await done.Task;
            r.Wait(2000);
            return e;
        }

        static double D(string s) => double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;

        static void Parse(Estimate e, string[] f)
        {
            switch (f[0])
            {
                case "plan" when f.Length >= 9:
                    e.Plan.Add(new PlanStep { Os = f[1], Id = f[2], Seconds = D(f[3]), Download = (long)D(f[4]), AddGB = D(f[5]), KeepGB = D(f[6]), State = f[7] == "1" ? "skip" : "pending", Title = Title(f[1], f[2], f[8]) });
                    break;
                case "option" when f.Length >= 6:
                    e.Options[f[1]] = new[] { D(f[2]), D(f[3]), D(f[4]), D(f[5]) };
                    break;
                case "total" when f.Length >= 7:
                    e.Download = D(f[1]); e.Seconds = D(f[2]); e.Peak = D(f[3]); e.After = D(f[4]); e.Need = D(f[5]); e.Free = D(f[6]);
                    e.Bandwidth = f.Length > 7 ? f[7] : "";
                    break;
                case "warn" when f.Length >= 2: e.Warnings.Add(f[1]); break;
                case "stop" when f.Length >= 2: e.Stops.Add(f[1]); break;
            }
        }

        /// <summary>A made-up install for the screenshots (-shot -page wizard -tab run): never Current, never run.</summary>
        public static InstallJob Test(InstallChoice c, List<PlanStep> plan, string result, string message) =>
            new InstallJob(c) { Plan = plan, Started = DateTime.Now.AddMinutes(-47), Result = result, Message = message };

        /// <summary>Starts (or resumes: the installers go on from their markers) the install of a choice.</summary>
        public static InstallJob Start(InstallChoice c, List<PlanStep> plan)
        {
            if (Current != null && Current.Runner != null && Current.Runner.Running) throw new InvalidOperationException(L.T("An install is running already.", "Zaten bir kurulum çalışıyor."));
            var j = new InstallJob(c) { Plan = plan ?? new List<PlanStep>(), Started = DateTime.Now };
            try { if (File.Exists(AppPaths.PauseFile)) File.Delete(AppPaths.PauseFile); } catch { }
            // a system installed afresh gets a new disk: the last screen of one before it goes
            if (c.Ios16 && !Guests.Installed("ios16")) Thumbs.Drop("ios16");
            if (c.Ios26 && !Guests.Installed("ios26")) Thumbs.Drop("ios26");
            if (c.Watch && !Guests.Installed("watch")) Thumbs.Drop("watch");
            if (c.Vision && !Guests.Installed("vision")) Thumbs.Drop("vision");
            // iOS 26's setup asks where its GPU driver comes from: the wizard's answer, in its config
            var conf = LauncherConfig.Current;
            if (c.Ios26 || c.Watch || c.Vision)
            {
                conf.Ios26.GpuMode = c.GpuMode;
                conf.Ios26.GpuDriver = c.GpuMode == "gpu" ? c.GpuDriver : "";
                if (c.Ios26 && (conf.Ios26.Work == "" || !Guests.Installed("ios26"))) conf.Ios26.Work = j.Ios26Work;
                conf.WriteIos26Config();
            }
            if (c.Ios16 && (conf.Ios16.Work == "" || !Guests.Installed("ios16"))) { conf.Ios16.Work = Path.Combine(c.Dir, "work"); conf.Ios16.App = c.Dir; }
            if (c.Ios26 && (conf.Ios26.App == "" || !Guests.Installed("ios26"))) conf.Ios26.App = c.Dir;
            if (c.Watch && (conf.Watch.Work == "" || !Guests.Installed("watch"))) { conf.Watch.Work = j.Ios26Work; conf.Watch.App = c.Dir; }
            if (c.Vision && (conf.Vision.Work == "" || !Guests.Installed("vision"))) { conf.Vision.Work = j.Ios26Work; conf.Vision.App = c.Dir; }
            c.Started = DateTime.Now.ToString("s");
            c.Stage = "running";
            conf.Install = c;
            conf.Save();
            var log = Path.Combine(AppPaths.LocalData, "logs", "install-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
            j.Runner = new Runner(Setup, Args(c, null), log);
            j.Runner.Progress += j.OnProgress;
            j.Runner.Exited += j.OnExit;
            j.Runner.Line += l => { if (l.StartsWith("Step ") && l.Contains(" failed")) j.Message = l; };
            Current = j;
            j.Runner.Start(new Dictionary<string, string> { ["ASOFT_PAUSE_FILE"] = AppPaths.PauseFile }, AppPaths.Root);
            Changed?.Invoke();
            return j;
        }

        PlanStep Find(string os, string id) => Plan.FirstOrDefault(p => p.Os == os && p.Id == id);

        void OnProgress(string[] f)
        {
            switch (f[0])
            {
                case "plan" when f.Length >= 9:
                    // the run's own plan replaces the estimate's (it knows what earlier runs finished)
                    lock (Plan)
                    {
                        if (!sawPlan) { Plan.Clear(); sawPlan = true; }
                        Plan.Add(new PlanStep { Os = f[1], Id = f[2], Seconds = D(f[3]), Download = (long)D(f[4]), State = f[7] == "1" ? "skip" : "pending", Title = Title(f[1], f[2], f[8]) });
                    }
                    break;
                case "step" when f.Length >= 7:
                    {
                        var s = Find(f[1], f[5]);
                        if (s == null) break;
                        var st = f[6];
                        if (st == "start")
                        {
                            foreach (var p in Plan.Where(p => p.State == "running" && p != s)) p.State = "done";
                            s.State = "running"; s.Started = DateTime.Now; s.Pct = -1; s.Text = "";
                        }
                        else s.State = st;
                        if (st == "fail" && f.Length > 7) Message = f[7];
                    }
                    break;
                case "pct" when f.Length >= 5:
                    {
                        var s = Find(f[1], f[2]);
                        if (s == null) break;
                        s.Pct = int.TryParse(f[3], out var n) ? n : -1;
                        s.Text = StepText(f[1], f[4]);
                    }
                    break;
                case "paused": Result = "paused"; break;
                case "wsl-restart": Result = "restart"; break;
                case "stop" when f.Length >= 2: Message = f[1]; break;
            }
            Changed?.Invoke();
        }
        bool sawPlan;

        void OnExit(int code)
        {
            foreach (var p in Plan.Where(p => p.State == "running")) p.State = code == 0 ? "done" : code == 5 ? "pending" : "fail";
            Result = code == 0 ? "done" : code == 5 ? "paused" : code == 3010 ? "restart" : "failed";
            if (Result == "failed" && Message == "")
                Message = string.Join(" ", Runner.Lines.Where(l => l.Trim() != "" && !l.StartsWith("  >")).Reverse().Take(3).Reverse());
            try { if (File.Exists(AppPaths.PauseFile)) File.Delete(AppPaths.PauseFile); } catch { }
            var conf = LauncherConfig.Current;
            conf.Install.Stage = Result;
            conf.Save();
            Log.Write($"install {Result} ({code}): {Message}");
            Changed?.Invoke();
        }

        public void Pause()
        {
            PauseAsked = true;
            Directory.CreateDirectory(AppPaths.LocalData);
            File.WriteAllText(AppPaths.PauseFile, DateTime.Now.ToString("s"));
            Changed?.Invoke();
        }

        public void StopNow()
        {
            Runner?.Kill();
        }

        public bool Running => Runner != null && Runner.Running;

        public PlanStep Now => Plan.FirstOrDefault(p => p.State == "running");

        /// <summary>Seconds left: the steps not done, the running one at its own percent (or by its time so far).</summary>
        public double SecondsLeft()
        {
            double left = 0;
            foreach (var p in Plan)
            {
                if (p.State == "pending") left += p.Seconds;
                else if (p.State == "running")
                {
                    double est = p.Seconds;
                    double frac = StepFraction(p);
                    left += Math.Max(est * (1 - frac), 0.1 * est);
                }
            }
            return left;
        }

        /// <summary>How far the whole install is, 0..1, by the estimated seconds.</summary>
        public double Fraction()
        {
            double all = 0, done = 0;
            foreach (var p in Plan)
            {
                if (p.State == "skip") continue;
                all += p.Seconds;
                if (p.State == "done") done += p.Seconds;
                else if (p.State == "running") done += p.Seconds * StepFraction(p);
            }
            return all <= 0 ? 0 : Math.Min(1, done / all);
        }

        /// <summary>The running step's part done: its percent, a download's bytes on the drive, else its time.</summary>
        public double StepFraction(PlanStep p)
        {
            if (p.Pct >= 0) return p.Pct / 100.0;
            if (p.Download > 50_000_000)
            {
                var got = Downloaded(p);
                if (got >= 0) return Math.Min(0.99, got / (double)p.Download);
            }
            var t = (DateTime.Now - p.Started).TotalSeconds;
            return p.Seconds <= 0 ? 0.5 : Math.Min(0.95, t / p.Seconds);
        }

        long lastBytes = -1; DateTime lastLook;
        long Downloaded(PlanStep p)
        {
            if ((DateTime.Now - lastLook).TotalSeconds < 4) return lastBytes;
            lastLook = DateTime.Now;
            var w = Path.Combine(Choice.Dir, "work");
            string dir = p.Os == "ios16" && p.Id == "ipsw" ? Path.Combine(w, "ipsw")
                : p.Os == "ios26" && p.Id == "iphone" ? Path.Combine(w, "iphone")
                : p.Os == "ios26" && p.Id == "cloudos" ? Path.Combine(w, "cloudos")
                : p.Os == "watch" && p.Id == "download" ? Path.Combine(w, "watchos", "ipsw")
                // (the runtime's .dmg as it streams in: steps\rooms.sh writes it there, then deletes it)
                : p.Os == "vision" && p.Id == "rooms" ? Path.Combine(w, "visionos", "build", "rooms")
                : null;
            if (dir == null || !Directory.Exists(dir)) return lastBytes = -1;
            long sum = 0;
            try
            {
                foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                {
                    if (f.Contains(".trustcache")) continue;
                    try { using (var s = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) sum += s.Length; } catch { }
                }
            }
            catch { }
            return lastBytes = sum;
        }

        /// <summary>A paused or stopped install this PC has (setup.json / launcher.json): what to resume.</summary>
        public static InstallChoice Unfinished()
        {
            var c = LauncherConfig.Current.Install;
            if (c == null || string.IsNullOrEmpty(c.Dir)) return null;
            if (Current != null && Current.Running) return null;
            var setup = Json.ReadObject(AppPaths.SetupState);
            var stage = Json.Str(setup, "Stage");
            if (stage == "") stage = c.Stage;
            if (stage == "running" || stage == "paused" || stage == "failed" || stage == "wsl-install" || c.Stage == "restart") return c;
            return null;
        }

        public static void Notify() => Changed?.Invoke();
    }
}
