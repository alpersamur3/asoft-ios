using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace ASoftware.Engine
{
    /// <summary>What the launcher knows of each OS: its scripts, folders, ports and disks, as the scripts lay them out.</summary>
    public static class Guests
    {
        public static readonly string[] Ids = { "ios16", "ios26", "watch", "vision" };
        /// <summary>The systems the phone app runs (visionOS is PC only).</summary>
        public static readonly string[] PhoneIds = { "ios16", "ios26", "watch" };

        public static string Name(string os) => os == "ios16" ? "iOS 16" : os == "ios26" ? "iOS 26" : os == "watch" ? "watchOS" : "visionOS";
        public static string Detail(string os) => os == "ios16" ? "16.7.16 · iPhone X" : os == "ios26" ? "26.6.2 · iPhone 16" : os == "watch" ? "27.2 · Apple Watch Series 9" : "27.2 · Apple Vision Pro";

        /// <summary>The ports a running guest holds; a start refuses when another process has one.</summary>
        public static int[] Ports(string os) => os == "ios16" ? new[] { 4445 } : os == "ios26" ? new[] { 4451, 4452, 4453 } : os == "vision" ? new[] { 4481, 4482, 4483 } : new[] { 4471, 4472, 4473 };
        public static int QmpPort(string os) => os == "ios16" ? 4445 : os == "ios26" ? 4453 : os == "vision" ? 4483 : 4473;
        public static int SerialPort(string os) => os == "ios26" ? 4451 : os == "watch" ? 4471 : os == "vision" ? 4481 : 0;
        /// <summary>iOS 16's RAM is fixed by its device tree, visionOS's too (4 GiB, the dtree-v trees').</summary>
        public static bool HasRamSetting(string os) => os != "ios16" && os != "vision";
        // iOS 26's 6 and 8 GB need qemu-sptm f76157c or later (the boot framebuffer above RAM): an older QEMU puts it
        // inside RAM from 5 GB, and reims-vgpu then refuses the split RAM map (rvg_device_create fails, QEMU ends at once)
        public static int[] RamChoices(string os) => os == "watch" ? new[] { 2048, 3072, 4096 } : new[] { 3072, 4096, 6144, 8192 };
        /// <summary>The vCPU counts a start takes: visionOS has a device tree for 4, 6 and 8 (Start-visionOS.ps1 -Cpus).</summary>
        public static int[] CpuChoices(string os) => os == "vision" ? new[] { 4, 6, 8 } : new[] { 4, 8 };
        public static string[] Windows(string os) => os == "ios16" ? new[] { "ASoftware iOS" } : os == "ios26" ? new[] { "ASoftware iOS 26" } : os == "vision" ? new[] { "ASoftware visionOS 27.2" } : new[] { "ASoftware watchOS" };

        /// <summary>Saves of the whole machine: the quick save closing the window makes, the way back, the Saves tab and a
        /// start that resumes one. Every control of that kind asks this, so a system without them is one place to say.
        /// All four have them: visionOS since Start-visionOS.ps1's quick boot (-NoQuickBoot, -LoadState, &lt;disk&gt;.quick-used
        /// as watchOS's; each of its two disks, sound and silent, has its own saves; Vision-AutoSave.ps1 after a cold boot, as the watch's).</summary>
        public static bool HasQuickSave(string os) => true;

        /// <summary>The PC's GPU a guest drawn by reims-vgpu runs on: iOS 26's setting, which visionOS shares.</summary>
        public static string HostGpu(string os) => (os == "vision" ? LauncherConfig.Current.Ios26 : Cfg(os)).HostGpu;

        public static OsConfig Cfg(string os) => LauncherConfig.Current.For(os);

        /// <summary>The app folder (scripts, kernel, python) for an OS: its own if set and real, else the launcher's.</summary>
        public static string App(string os)
        {
            var a = Cfg(os).App;
            return AppPaths.IsAppFolder(a) ? a : AppPaths.Root;
        }

        public static string Work(string os) => Cfg(os).Work ?? "";

        static string W(string os, string rel) => Work(os) == "" ? "" : Path.Combine(Work(os), rel);
        static bool Has(string os, string rel) { var p = W(os, rel); return p != "" && File.Exists(p); }

        public static string StartScript(string os) =>
            os == "ios16" ? Path.Combine(App(os), "scripts", "run-windows.ps1")
            : os == "ios26" ? Path.Combine(App(os), "ios26", "Start-iOS26.ps1")
            : os == "vision" ? Path.Combine(App(os), "visionos", "Start-visionOS.ps1")
            : Path.Combine(App(os), "watchos", "Start-watchOS.ps1");

        // --- installed? ------------------------------------------------------------------------
        /// <summary>iOS 16's base disk (the installer's, or a hand-built one's v5 layer).</summary>
        public static string Ios16Base(string work)
        {
            var b = Path.Combine(work, "root", "ios16-base.qcow2");
            if (File.Exists(b)) return b;
            var v5 = Path.Combine(work, "root", "ios16-root-20H392-v5.qcow2");
            return File.Exists(v5) ? v5 : "";
        }

        public static bool Installed(string os)
        {
            var w = Work(os);
            if (w == "" || !Directory.Exists(w)) return false;
            switch (os)
            {
                case "ios16":
                    // the installer's disk once its first start is done, or a hand-built work folder
                    var base16 = Ios16Base(w);
                    if (base16 == "") return false;
                    if (base16.EndsWith("ios16-base.qcow2", StringComparison.OrdinalIgnoreCase) && !Has(os, @"root\ios16-base.ready")) return false;
                    return Has(os, @"qemu\qemu-system-aarch64.exe") || Has(os, @"qemu\v11.1.2-asoft\qemu-system-aarch64.exe");
                case "ios26":
                    return Has(os, "root.qcow2") && Has(os, "root.tc") && Has(os, @"fw\bootkc") && Has(os, "dtree-smp4") && Has(os, "rd-shell.hfs");
                case "vision":
                    // the silent disk is always made (Install-visionOS.ps1's disks step); the sound disk only with the plug-in
                    return Has(os, @"visionos\vision-silent.qcow2.ready") && Has(os, @"visionos\vision-silent.qcow2");
                default:
                    return Has(os, @"watchos\watch.qcow2.ready") && Has(os, @"watchos\watch.qcow2");
            }
        }

        /// <summary>visionOS's sound disk is there (made only when the install had the audio plug-in).</summary>
        public static bool HasSoundDisk() => Has("vision", @"visionos\vision.qcow2.ready") && Has("vision", @"visionos\vision.qcow2");

        /// <summary>A visionOS start with sound: asked for, and the install has the sound disk.</summary>
        public static bool Sound(string os) => os == "vision" && Cfg(os).Sound && HasSoundDisk();

        /// <summary>Steps an install of this OS finished (its markers), and how many it has; (0, 0) when none started.</summary>
        public static (int done, int total) Markers(string os)
        {
            var w = Work(os);
            if (w == "" || !Directory.Exists(w)) return (0, 0);
            try
            {
                if (os == "ios16")
                {
                    var log = Path.Combine(w, "install16.log");
                    if (!File.Exists(log)) return (0, 0);
                    int n = 0;
                    foreach (var l in File.ReadAllLines(log)) { var m = Regex.Match(l, @" (\d)/6 "); if (m.Success) n = Math.Max(n, int.Parse(m.Groups[1].Value) - 1); }
                    return (n, 6);
                }
                var dir = Path.Combine(w, "install");
                if (!Directory.Exists(dir)) return (0, 0);
                var marks = Directory.GetFiles(dir, "*.done").Select(Path.GetFileName).ToList();
                var asked = LauncherConfig.Current.Install;
                int watch = marks.Count(f => f.StartsWith("watch-", StringComparison.Ordinal));
                int vision = marks.Count(f => f.StartsWith("vision-", StringComparison.Ordinal));
                // Install-iOS26.ps1: 26 steps, of which setup, prereq, cleanup and shortcut run every time and leave none
                if (os == "ios26")
                {
                    var own = marks.Where(f => !f.StartsWith("watch-", StringComparison.Ordinal) && !f.StartsWith("vision-", StringComparison.Ordinal)).ToList();
                    // a watch-only or visionOS-only install leaves the base's markers here and nothing else of iOS 26: that
                    // is no iOS 26 install that stopped, unless iOS 26 was asked for too
                    bool onlyBase = own.All(f => BaseOnce.Contains(Path.GetFileNameWithoutExtension(f)));
                    bool forOther = watch > 0 || vision > 0 || asked != null && (asked.Watch || asked.Vision);
                    if (onlyBase && forOther && !(asked != null && asked.Ios26)) return (0, 0);
                    return (own.Count, 26 - 4);
                }
                // Install-watchOS.ps1: 13 steps, Install-visionOS.ps1: 16; in both check, cleanup and shortcut run every time
                // and leave none. One without iOS 26 makes the base first, in this folder and before any of its own markers
                // (its check step runs Install-iOS26.ps1 -Base): the base's steps are this install's too, unless a finished
                // iOS 26 or the other one of the two here made them, or nothing says this one was ever asked for (then they
                // are an iOS 26 install's that stopped)
                bool isWatch = os == "watch";
                int mine = isWatch ? watch : vision, total = isWatch ? 13 - 3 : 16 - 3;
                bool wanted = asked != null && (isWatch ? asked.Watch : asked.Vision);
                string other = isWatch ? "vision" : "watch";
                bool baseBefore = Installed("ios26") && SameFolder(Work("ios26"), w) || Installed(other) && SameFolder(Work(other), w);
                if (baseBefore || mine == 0 && !wanted) return (mine, total);
                return (mine + marks.Count(f => BaseOnce.Contains(Path.GetFileNameWithoutExtension(f))), total + BaseOnce.Length);
            }
            catch { return (0, 0); }
        }

        // the base watchOS shares with iOS 26 (Install-iOS26.ps1's $BaseSteps), its steps that leave a marker
        // (install\<id>.done; setup and prereq run every time)
        static readonly string[] BaseOnce = { "python", "qemu", "linux", "sysroot", "cloudos", "firmware", "devicetree", "ramdisk", "gpudriver" };

        static bool SameFolder(string a, string b) =>
            string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

        /// <summary>A watchOS or visionOS install has its base already: iOS 26 is installed (the wizard puts them in its
        /// folder), or the system's work folder has every marker of the base's steps.</summary>
        public static bool HasBase(string os)
        {
            if (Installed("ios26")) return true;
            var w = Work(os);
            return w != "" && BaseOnce.All(id => File.Exists(Path.Combine(w, "install", id + ".done")));
        }

        public static bool HasWatchBase() => HasBase("watch");

        // --- disks, trees, tools -----------------------------------------------------------------
        /// <summary>The disk that keeps what the OS writes, which holds its saves; "" in throwaway mode.</summary>
        public static string SaveDisk(string os)
        {
            var c = Cfg(os);
            if (c.DiskMode == "throwaway" || Work(os) == "") return "";
            switch (os)
            {
                case "ios16": return W(os, @"root\ios16-user.qcow2");
                case "ios26": return W(os, c.Wallpaper == "collections" ? "root-collections-user.qcow2" : "root26-user.qcow2");
                // (two disks of their own, as Start-visionOS.ps1 picks them: what one keeps is not on the other)
                case "vision": return W(os, Sound(os) ? @"visionos\vision.qcow2" : @"visionos\vision-silent.qcow2");
                default: return W(os, @"watchos\watch.qcow2");
            }
        }

        public static string QemuImg(string os)
        {
            foreach (var rel in os == "watch" ? new[] { @"qemu-watch\qemu-img.exe", @"qemu\qemu-img.exe" } : new[] { @"qemu\qemu-img.exe", @"qemu\v11.1.2-asoft\qemu-img.exe" })
                if (Has(os, rel)) return W(os, rel);
            var pf = @"C:\Program Files\qemu\qemu-img.exe";
            return File.Exists(pf) ? pf : "";
        }

        /// <summary>The device tree a start boots (before a RAM change), as the start scripts pick it.</summary>
        public static string Tree(string os, int smp)
        {
            if (os == "ios26")
            {
                var t = W(os, "dtree-smp" + smp);
                if (Cfg(os).Aod && File.Exists(t + "-aod")) t += "-aod";
                return t;
            }
            if (os == "watch") return W(os, smp == 8 ? @"watchos\dtree-w8" : @"watchos\dtree-w");
            if (os == "vision") return W(os, smp == 8 ? @"visionos\dtree-v8" : smp == 6 ? @"visionos\dtree-v6" : @"visionos\dtree-v");
            return "";
        }

        /// <summary>The RAM the guest gets by default (its tree's, or iOS 16's fixed size), MiB.</summary>
        public static int DefaultRam(string os)
        {
            if (os == "ios16") return 7168;   // qemu-sweet.py: -m 7G for mkadt.py --highmem's DRAM
            var t = Tree(os, 4);
            int r = t != "" && File.Exists(t) ? Adt.RamMiB(t) : 0;
            return r > 0 ? r : os == "watch" ? 4096 : 4096;
        }

        public static int Ram(string os) => Cfg(os).RamMiB > 0 && HasRamSetting(os) ? Cfg(os).RamMiB : DefaultRam(os);

        /// <summary>The vCPUs a start takes: the setting, one of the counts there is a device tree for (visionOS: 8 else).</summary>
        public static int Smp(string os)
        {
            int n = Cfg(os).Smp;
            return os == "vision" && Array.IndexOf(CpuChoices(os), n) < 0 ? 8 : n;
        }

        /// <summary>The commit charge a guest's QEMU takes beyond its RAM, bytes: the code buffer (tb-size 2 GB on the research
        /// VM), GTK, and the GPU library. Measured: a 6 GB iOS 26 guest about 9.3 GB in all. When commit runs short Windows
        /// grows the page file on C:.</summary>
        public static double QemuOverhead(string os) => os == "ios16" ? 1.0e9 : 3.5e9;

        /// <summary>The settings a save depends on besides its disk (QEMU loads a state only into the machine it was made on):
        /// vCPUs, RAM, the network card, and for iOS 26 and visionOS the PC's GPU. Its own RAM and vCPUs when given.
        /// (visionOS's sound is not in it: sound and silent are two disks, each with its own saves.)</summary>
        public static string Shape(string os, int ram = 0, int smp = 0)
        {
            var c = Cfg(os);
            var s = $"smp={(smp > 0 ? smp : Smp(os))};ram={(os == "ios16" ? 0 : ram > 0 ? ram : Ram(os))};net={(c.Net ? 1 : 0)}";
            var g = HostGpu(os);
            if (os == "ios26" || os == "vision") s += ";gpu=" + (g == "integrated" || g == "discrete" ? g : "auto");
            return s;
        }

        /// <summary>Whether a save loads with these settings (Shape): from what it was made with, or for a save from before
        /// the launcher kept that, its vCPUs and RAM; true when nothing is known.</summary>
        public static bool Fits(string os, SaveMeta m, string shape)
        {
            if (m == null) return true;
            if (!string.IsNullOrEmpty(m.Shape)) return m.Shape == shape;
            if (m.Smp <= 0) return true;
            return Shape(os, m.RamMiB > 0 ? m.RamMiB : Ram(os), m.Smp).Split(';').Take(2).SequenceEqual(shape.Split(';').Take(2));
        }

        /// <summary>A Shape's parts (smp, ram, net, gpu).</summary>
        public static Dictionary<string, string> ShapeParts(string shape) =>
            (shape ?? "").Split(';').Select(p => p.Split(new[] { '=' }, 2)).Where(p => p.Length == 2).ToDictionary(p => p[0], p => p[1]);

        /// <summary>The shape a save loads with: what the launcher noted when it was made, else its vCPUs and RAM as known
        /// (SaveGuest) and nothing about its network ("" parts are not shown).</summary>
        public static string SaveShape(string os, SaveMeta m)
        {
            if (m != null && !string.IsNullOrEmpty(m.Shape)) return m.Shape;
            var c = Cfg(os);
            int smp = m != null && m.Smp > 0 ? m.Smp : c.Smp;
            int ram = os == "ios16" ? 0 : m != null && m.RamMiB > 0 ? m.RamMiB : DefaultRam(os);
            return $"smp={smp};ram={ram}";
        }

        /// <summary>The hardware a save opens with, for people: "4 GB RAM · 4 vCPU · network on".</summary>
        public static string Hardware(string os, string shape)
        {
            var p = ShapeParts(shape);
            var parts = new List<string>();
            int ram = p.TryGetValue("ram", out var r) && int.TryParse(r, out var n) ? n : 0;
            if (os == "ios16") ram = DefaultRam(os);
            if (ram > 0) parts.Add($"{ram / 1024.0:0.#} GB RAM");
            if (p.TryGetValue("smp", out var s)) parts.Add(s + " vCPU");
            if (p.TryGetValue("net", out var net)) parts.Add(net == "1" ? L.T("network on", "ağ açık") : L.T("network off", "ağ kapalı"));
            if (p.TryGetValue("gpu", out var g) && g != "auto") parts.Add(g == "integrated" ? L.T("integrated GPU", "tümleşik GPU") : L.T("graphics card", "ekran kartı"));
            return string.Join(" · ", parts);
        }

        /// <summary>Keeps the disk's quick save as the way back: no start resumes it by itself (the start scripts' Keep-WayBack).</summary>
        public static void MarkWayBack(string os, string disk)
        {
            var q = Snapshots(os, disk).FirstOrDefault(s => s.Quick);
            if (q == null || q.WayBack) return;
            try { File.WriteAllText(QuickUsedFile(disk), q.Key + "\r\n", Encoding.ASCII); Log.Write(os + ": the quick save " + q.Key + " is the way back now"); }
            catch (Exception e) { Log.Write(os + ": cannot mark the way back: " + e.Message); }
        }

        // --- saves ---------------------------------------------------------------------------------
        public class Snap
        {
            public string Id, Name;
            public long DateSec, DateNsec, Bytes;
            public DateTime When;
            public string VmSize => L.Size(Bytes);
            public bool Quick => Name == QuickName;
            /// <summary>The quick save a start has resumed (or passed over) already: no start resumes it by itself
            /// again; it stays as the way back until the next Save and close replaces it.</summary>
            public bool WayBack;
            /// <summary>Its id and time, as the start scripts write them to &lt;disk&gt;.quick-used (no time zone in them).</summary>
            public string Key => Id + " " + DateSec + " " + DateNsec;
        }

        public const string QuickName = "asoft-quick";

        /// <summary>Names the quick save that is the way back (written by the start scripts, Start-iOS26.ps1 Quick-Key).</summary>
        public static string QuickUsedFile(string disk) => disk + ".quick-used";

        /// <summary>The internal snapshots of a disk (qemu-img info --output=json -U: it also reads a disk in use).</summary>
        public static List<Snap> Snapshots(string os, string disk)
        {
            var r = new List<Snap>();
            var img = QemuImg(os);
            if (disk == "" || !File.Exists(disk) || img == "") return r;
            var res = Run(img, "info --output=json -U \"" + disk + "\"", 20000);
            if (res.Item1 != 0) { Log.Write(os + ": qemu-img info: " + res.Item2.Trim()); return r; }
            Dictionary<string, object> o;
            try { o = Json.Parse(res.Item2) as Dictionary<string, object>; } catch (Exception e) { Log.Write(os + ": qemu-img info: " + e.Message); return r; }
            if (o == null || !o.TryGetValue("snapshots", out var list) || !(list is object[] snaps)) return r;
            string used = "";
            try { var f = QuickUsedFile(disk); if (File.Exists(f)) used = (File.ReadAllLines(f).FirstOrDefault() ?? "").Trim(); } catch { }
            long N(Dictionary<string, object> d, string k) => d.TryGetValue(k, out var v) && v != null ? Convert.ToInt64(v, CultureInfo.InvariantCulture) : 0;
            foreach (var d in snaps.OfType<Dictionary<string, object>>())
            {
                var s = new Snap { Id = Json.Str(d, "id") ?? "", Name = Json.Str(d, "name") ?? "", DateSec = N(d, "date-sec"), DateNsec = N(d, "date-nsec"), Bytes = N(d, "vm-state-size") };
                s.When = DateTimeOffset.FromUnixTimeSeconds(s.DateSec).LocalDateTime;
                s.WayBack = s.Quick && used == s.Key;
                r.Add(s);
            }
            return r;
        }

        public static (int, string) DeleteSnapshot(string os, string disk, string name) =>
            Run(QemuImg(os), "snapshot -d \"" + name + "\" \"" + disk + "\"", 300000);

        /// <summary>A short date and time for a save, in the launcher's language.</summary>
        public static string When(DateTime t, bool longForm = false) =>
            t.ToString(longForm ? (L.Tr ? "d MMMM yyyy, HH:mm" : "MMMM d, yyyy, HH:mm") : (L.Tr ? "d MMM HH:mm" : "MMM d, HH:mm"),
                       L.Tr ? new CultureInfo("tr-TR") : CultureInfo.InvariantCulture);

        /// <summary>A tool's exit code and its output (stdout and stderr), without a window.</summary>
        public static (int, string) Run(string exe, string args, int timeoutMs)
        {
            try
            {
                var psi = new ProcessStartInfo(exe, args)
                {
                    UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
                };
                using (var p = Process.Start(psi))
                {
                    var o = p.StandardOutput.ReadToEndAsync();
                    var e = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(timeoutMs)) { try { p.Kill(); } catch { } return (-1, "timed out"); }
                    return (p.ExitCode, o.Result + e.Result);
                }
            }
            catch (Exception ex) { return (-1, ex.Message); }
        }

        // --- running -------------------------------------------------------------------------------
        /// <summary>The QEMU running this OS from its work folder, if any (by command line: its machine and folder).</summary>
        public static Native.Proc FindRunning(string os, List<Native.Proc> qemus)
        {
            var w = Work(os);
            if (w == "") return null;
            foreach (var p in qemus)
            {
                var c = p.CommandLine;
                if (c.IndexOf(w, StringComparison.OrdinalIgnoreCase) < 0 && c.IndexOf(w.Replace('\\', '/'), StringComparison.OrdinalIgnoreCase) < 0) continue;
                bool vres = c.Contains("vresearch");
                if (os == "ios16" && !vres && c.Contains("virt")) return p;
                if (os == "ios26" && vres && c.Contains("fb=1179x2556")) return p;
                if (os == "watch" && vres && c.Contains("fb=352x430")) return p;
                // (on one of its two user disks: Install-visionOS.ps1's boots run Start-visionOS.ps1 on its build disks)
                if (os == "vision" && vres && c.Contains("fb=1920x1080") && VisionDisk(c) != "") return p;
            }
            return null;
        }

        /// <summary>The visionOS user disk a QEMU command line runs (sound or silent), or "" for another disk.</summary>
        public static string VisionDisk(string cmd) =>
            cmd.IndexOf("vision-silent.qcow2", StringComparison.OrdinalIgnoreCase) >= 0 ? W("vision", @"visionos\vision-silent.qcow2")
            : Regex.IsMatch(cmd, @"[\\/]vision\.qcow2", RegexOptions.IgnoreCase) ? W("vision", @"visionos\vision.qcow2") : "";

        /// <summary>The newest run folder of an OS (where its serial and QEMU logs are).</summary>
        public static string LastRunFolder(string os)
        {
            var w = Work(os);
            if (w == "") return "";
            var runs = os == "watch" ? Path.Combine(w, "watchos", "runs") : os == "vision" ? Path.Combine(w, "visionos", "runs") : Path.Combine(w, "runs");
            if (!Directory.Exists(runs)) return "";
            var d = new DirectoryInfo(runs).GetDirectories().OrderByDescending(x => x.LastWriteTimeUtc).FirstOrDefault();
            return d?.FullName ?? "";
        }

        public static string IpaFolder(string os) => W(os, "ipa");
    }
}
