using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Text;
using System.Text.RegularExpressions;

namespace ASoftware.Engine
{
    /// <summary>What a problem report needs: a short description of this PC, and the logs in one zip on the desktop.
    /// The user name is taken out of paths in both.</summary>
    public static class LogPack
    {
        static string Wmi(string query, Func<ManagementObject, string> one)
        {
            try
            {
                using (var s = new ManagementObjectSearcher(query))
                    return string.Join(" + ", s.Get().Cast<ManagementObject>().Select(one).Where(x => !string.IsNullOrWhiteSpace(x)));
            }
            catch { return ""; }
        }

        /// <summary>Plain facts, no paths: goes into the issue text as it is shown on the report page.</summary>
        public static string PcInfo()
        {
            var sb = new StringBuilder();
            var m = Native.Memory();
            sb.AppendLine($"ASoftware {Updates.AppVersion}");
            sb.AppendLine($"Windows {Environment.OSVersion.Version}");
            sb.AppendLine($"CPU {Wmi("SELECT Name FROM Win32_Processor", o => Convert.ToString(o["Name"]).Trim())} ({Environment.ProcessorCount} threads)");
            sb.AppendLine("RAM " + (m.total / 1073741824.0).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture) + " GB");
            sb.AppendLine($"GPU {Wmi("SELECT Name, DriverVersion FROM Win32_VideoController", o => Convert.ToString(o["Name"]).Contains("Basic Display") ? "" : o["Name"] + " " + o["DriverVersion"])}");
            foreach (var os in Guests.Ids)
            {
                if (!Guests.Installed(os)) continue;
                var c = Guests.Cfg(os);
                sb.AppendLine($"{Guests.Name(os)}: {c.Smp} vCPU, RAM {(c.RamMiB == 0 ? "default" : c.RamMiB + " MiB")}, {c.DiskMode}{(os == "ios26" && c.GpuMode != "" ? ", gpu " + c.GpuMode : "")}");
            }
            return sb.ToString().TrimEnd();
        }

        // the logs' bytes are kept as they are (read as Latin-1); only the user name in a path changes
        static readonly Regex UserInPath = MakeUserRegex();
        static Regex MakeUserRegex()
        {
            var name = Environment.UserName;
            var utf8 = Encoding.GetEncoding(28591).GetString(Encoding.UTF8.GetBytes(name));
            return new Regex(@"(Users(?:\\+|/))(" + Regex.Escape(name) + "|" + Regex.Escape(utf8) + @")(?=[\\/""'\s:;,]|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Multiline);
        }
        public static string Scrub(string text) => UserInPath.Replace(text, "$1USER");

        /// <summary>The last run of one OS (or of every installed one when os is null), the install's step logs,
        /// the launcher's own log and config. Text files up to 20 MB, the tail of bigger ones.</summary>
        public static string Make(string os)
        {
            var zip = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), $"ASoftware-logs-{os ?? "all"}-{DateTime.Now:yyyyMMdd-HHmmss}.zip");
            var latin = Encoding.GetEncoding(28591);
            using (var z = ZipFile.Open(zip, ZipArchiveMode.Create))
            {
                void Put(string file, string name)
                {
                    try
                    {
                        var fi = new FileInfo(file);
                        if (!fi.Exists) return;
                        string text;
                        using (var from = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                        {
                            if (fi.Length > 20 << 20) from.Seek(-(20 << 20), SeekOrigin.End);
                            text = new StreamReader(from, latin).ReadToEnd();
                        }
                        var e = z.CreateEntry(name, CompressionLevel.Optimal);
                        using (var to = new StreamWriter(e.Open(), latin)) to.Write(Scrub(text));
                    }
                    catch { }
                }
                foreach (var g in os != null ? new[] { os } : Guests.Ids.Where(Guests.Installed).ToArray())
                {
                    var run = Guests.LastRunFolder(g);
                    if (run != "")
                        foreach (var f in Directory.EnumerateFiles(run, "*", SearchOption.AllDirectories).Where(f => new[] { ".log", ".txt", ".json" }.Contains(Path.GetExtension(f).ToLowerInvariant())))
                            Put(f, g + "/run/" + f.Substring(run.Length).TrimStart('\\').Replace('\\', '/'));
                    var marks = Path.Combine(Guests.Work(g), "install");
                    var inst = Path.Combine(marks, "logs");
                    if (Directory.Exists(inst)) foreach (var f in Directory.EnumerateFiles(inst, "*.log")) Put(f, g + "/install/" + Path.GetFileName(f));
                    if (Directory.Exists(marks)) foreach (var f in Directory.EnumerateFiles(marks, "*.done").Take(60)) Put(f, g + "/install/markers/" + Path.GetFileName(f));
                    Put(Path.Combine(Guests.Work(g), "qemu", "BUILD.txt"), g + "/qemu-BUILD.txt");
                    var dir = Path.GetDirectoryName(Guests.Work(g).TrimEnd('\\'));
                    if (dir != null) Put(Path.Combine(dir, "install-summary.txt"), g + "/install-summary.txt");
                }
                var ll = Path.Combine(AppPaths.LocalData, "logs");
                if (Directory.Exists(ll)) foreach (var f in Directory.EnumerateFiles(ll, "*.log").OrderByDescending(File.GetLastWriteTime).Take(8)) Put(f, "launcher/" + Path.GetFileName(f));
                Put(Log.File, "launcher/launcher.log");
                Put(AppPaths.ConfigFile, "config/launcher.json");
                Put(AppPaths.SetupState, "config/setup.json");
                Put(AppPaths.Ios26Config, "config/ios26.config.json");
                using (var w = new StreamWriter(z.CreateEntry("pc.txt").Open()))
                {
                    w.WriteLine(PcInfo());
                    foreach (var g in Guests.Ids.Where(Guests.Installed)) w.WriteLine($"{Guests.Name(g)} drive free: {L.Size(Native.FreeBytes(Guests.Work(g)))}");
                }
            }
            return zip;
        }
    }
}
