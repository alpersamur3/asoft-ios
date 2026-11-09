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
        public static readonly string[] Ids = { "ios16", "ios26", "watch" };

        public static string Name(string os) => os == "ios16" ? "iOS 16" : os == "ios26" ? "iOS 26" : os == "watch" ? "watchOS" : "visionOS";
        public static string Detail(string os) => os == "ios16" ? "16.7.16 · iPhone X" : os == "ios26" ? "26.6.2 · iPhone 16" : os == "watch" ? "27.2 · Apple Watch Series 9" : "27.2 · Apple Vision Pro";

        /// <summary>The ports a running guest holds; a start refuses when another process has one.</summary>
        public static int[] Ports(string os) => os == "ios16" ? new[] { 4445 } : os == "ios26" ? new[] { 4451, 4452, 4453 } : new[] { 4471, 4472, 4473 };
        public static int QmpPort(string os) => os == "ios16" ? 4445 : os == "ios26" ? 4453 : 4473;
        public static int SerialPort(string os) => os == "ios26" ? 4451 : os == "watch" ? 4471 : 0;
        public static bool HasRamSetting(string os) => os != "ios16";
        public static int[] RamChoices(string os) => os == "watch" ? new[] { 2048, 3072, 4096 } : new[] { 3072, 4096, 6144, 8192 };
        public static string[] Windows(string os) => os == "ios16" ? new[] { "ASoftware iOS" } : os == "ios26" ? new[] { "ASoftware iOS 26" } : new[] { "ASoftware watchOS" };

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
                default:
                    return Has(os, @"watchos\watch.qcow2.ready") && Has(os, @"watchos\watch.qcow2");
            }
        }

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
                if (os == "ios26") return (marks.Count(f => !f.StartsWith("watch-")), 25 - 4);   // its every-run steps leave none
                return (marks.Count(f => f.StartsWith("watch-")), 13 - 3);
            }
            catch { return (0, 0); }
        }

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

        // --- saves ---------------------------------------------------------------------------------
        public class Snap
        {
            public string Id, Name, VmSize, Date, Clock;
            public DateTime When;
            public bool Quick => Name == "asoft-quick";
        }

        static readonly Regex SnapRow = new Regex(@"^\s*(\d+)\s+(\S+)\s+([\d.]+\s*[KMGT]?i?B|\d+)\s+(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\s+(\S+)");

        /// <summary>The internal snapshots of a disk (qemu-img snapshot -l -U: it also reads a disk in use).</summary>
        public static List<Snap> Snapshots(string os, string disk)
        {
            var r = new List<Snap>();
            var img = QemuImg(os);
            if (disk == "" || !File.Exists(disk) || img == "") return r;
            var res = Run(img, "snapshot -l -U \"" + disk + "\"", 20000);
            foreach (var l in res.Item2.Split('\n'))
            {
                var m = SnapRow.Match(l);
                if (!m.Success) continue;
                DateTime.TryParseExact(m.Groups[4].Value, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var when);
                r.Add(new Snap { Id = m.Groups[1].Value, Name = m.Groups[2].Value, VmSize = m.Groups[3].Value, Date = m.Groups[4].Value, Clock = m.Groups[5].Value, When = when });
            }
            return r;
        }

        public static (int, string) DeleteSnapshot(string os, string disk, string name) =>
            Run(QemuImg(os), "snapshot -d \"" + name + "\" \"" + disk + "\"", 300000);

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
            }
            return null;
        }

        /// <summary>The newest run folder of an OS (where its serial and QEMU logs are).</summary>
        public static string LastRunFolder(string os)
        {
            var w = Work(os);
            if (w == "") return "";
            var runs = os == "watch" ? Path.Combine(w, "watchos", "runs") : Path.Combine(w, "runs");
            if (!Directory.Exists(runs)) return "";
            var d = new DirectoryInfo(runs).GetDirectories().OrderByDescending(x => x.LastWriteTimeUtc).FirstOrDefault();
            return d?.FullName ?? "";
        }

        public static string IpaFolder(string os) => W(os, "ipa");
    }
}
