using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace ASoftware.Engine
{
    /// <summary>An Android phone over adb, the ASoftware iOS app on it (GitHub's newest release), and
    /// scripts\Send-ToPhone.ps1 for what this PC has installed.</summary>
    public static class Phone
    {
        public const string Package = "com.asoft.ios";
        public const string AppRepo = "alpersamur3/asoft-ios-android";
        public const string ToolsUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip";
        public const string ToolsPage = "https://developer.android.com/tools/releases/platform-tools";
        public static string ToolsDir => Path.Combine(AppPaths.LocalData, "platform-tools");

        /// <summary>PATH first, then the places Send-ToPhone.ps1 looks: one adb version for every tool on this PC
        /// (a client of another version restarts the running adb server).</summary>
        public static string FindAdb()
        {
            foreach (var d in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
            {
                try { var f = Path.Combine(d.Trim().Trim('"'), "adb.exe"); if (d.Trim() != "" && File.Exists(f)) return f; } catch { }
            }
            var more = new List<string> { Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "", "Android", "Sdk", "platform-tools", "adb.exe") };
            foreach (var os in Guests.Ids) if (Guests.Work(os) != "") more.Add(Path.Combine(Guests.Work(os), "platform-tools", "adb.exe"));
            more.Add(Path.Combine(ToolsDir, "adb.exe"));
            return more.FirstOrDefault(File.Exists) ?? "";
        }

        public class Device
        {
            public string Serial = "", State = "", Model = "", Android = "", App = "";
            public double Free, Ram;
            public bool Ready => State == "device";
            public bool Filled;
        }

        /// <summary>adb's output and exit code; never waits on the pipe past the timeout (adb's server can keep it open).</summary>
        public static Task<(int code, string text)> Adb(string adb, string serial, string args, int timeoutMs = 20000) => Task.Run(() =>
        {
            var psi = new ProcessStartInfo(adb, (string.IsNullOrEmpty(serial) ? "" : "-s " + serial + " ") + args)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            var sb = new StringBuilder();
            try
            {
                using (var p = new Process { StartInfo = psi })
                {
                    p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
                    p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
                    p.Start();
                    p.BeginOutputReadLine();
                    p.BeginErrorReadLine();
                    if (!p.WaitForExit(timeoutMs))
                    {
                        try { p.Kill(); } catch { }
                        return (-1, "timeout");
                    }
                    Thread.Sleep(60);
                    lock (sb) return (p.ExitCode, sb.ToString());
                }
            }
            catch (Exception e) { return (-2, e.Message); }
        });

        public static async Task<List<Device>> List(string adb)
        {
            var r = await Adb(adb, null, "devices", 15000);
            var all = new List<Device>();
            foreach (var l in r.text.Split('\n').Select(x => x.Trim()))
            {
                var m = Regex.Match(l, @"^(\S+)\s+(device|unauthorized|offline|authorizing|connecting|no permissions.*)$");
                if (m.Success) all.Add(new Device { Serial = m.Groups[1].Value, State = m.Groups[2].Value });
            }
            return all;
        }

        /// <summary>Model, Android version, memory, free space, and the app's version ("" when it is not on the phone).</summary>
        public static async Task Fill(string adb, Device d)
        {
            if (!d.Ready) return;
            var sh = "getprop ro.product.model; echo @; getprop ro.build.version.release; echo @; df -k /sdcard | tail -n 1; echo @; grep MemTotal /proc/meminfo; echo @; dumpsys package " + Package + " | grep -m 1 versionName";
            var r = await Adb(adb, d.Serial, "shell \"" + sh + "\"", 20000);
            var p = r.text.Replace("\r", "").Split('@').Select(x => x.Trim()).ToArray();
            if (p.Length < 5) return;
            d.Model = p[0]; d.Android = p[1];
            var df = Regex.Split(p[2], @"\s+");
            if (df.Length >= 4 && double.TryParse(df[3], out var k)) d.Free = k * 1024;
            var mem = Regex.Match(p[3], @"(\d+)");
            if (mem.Success) d.Ram = double.Parse(mem.Groups[1].Value) * 1024;
            var v = Regex.Match(p[4], @"versionName=(\S+)");
            d.App = v.Success ? v.Groups[1].Value : "";
            d.Filled = true;
        }

        public class Apk { public string Tag = "", Url = "", Name = ""; public double Size; }

        public static async Task<Apk> LatestApk()
        {
            var o = await Updates.LatestOf(AppRepo);
            if (o == null || !o.TryGetValue("assets", out var a) || !(a is object[] assets)) return null;
            foreach (var x in assets.OfType<Dictionary<string, object>>())
            {
                var n = Json.Str(x, "name");
                if (n.EndsWith(".apk", StringComparison.OrdinalIgnoreCase))
                    return new Apk { Tag = Json.Str(o, "tag_name"), Name = n, Url = Json.Str(x, "browser_download_url"), Size = Json.Int(x, "size") ?? 0 };
            }
            return null;
        }

        /// <summary>To a .part file first; only a whole download gets the file's name.</summary>
        public static async Task Download(string url, string file, Action<double> fraction, CancellationToken stop)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            var part = file + ".part";
            using (var h = new HttpClient { Timeout = Timeout.InfiniteTimeSpan })
            {
                h.DefaultRequestHeaders.UserAgent.ParseAdd("ASoftware-launcher/" + Updates.AppVersion);
                using (var r = await h.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, stop))
                {
                    r.EnsureSuccessStatusCode();
                    double total = r.Content.Headers.ContentLength ?? 0, got = 0;
                    using (var from = await r.Content.ReadAsStreamAsync())
                    using (var to = File.Create(part))
                    {
                        var buf = new byte[256 * 1024];
                        for (;;)
                        {
                            int n = await from.ReadAsync(buf, 0, buf.Length, stop);
                            if (n <= 0) break;
                            await to.WriteAsync(buf, 0, n, stop);
                            got += n;
                            if (total > 0) fraction(got / total);
                        }
                    }
                }
            }
            if (File.Exists(file)) File.Delete(file);
            File.Move(part, file);
        }

        /// <summary>Google's platform-tools into ASoftware's own folder.</summary>
        public static async Task GetTools(Action<double> fraction, CancellationToken stop)
        {
            var zip = Path.Combine(AppPaths.LocalData, "platform-tools.zip");
            await Download(ToolsUrl, zip, fraction, stop);
            await Task.Run(() =>
            {
                if (Directory.Exists(ToolsDir)) Directory.Delete(ToolsDir, true);
                ZipFile.ExtractToDirectory(zip, AppPaths.LocalData);     // the zip's top folder is platform-tools
                File.Delete(zip);
            });
        }

        /// <summary>"" when installed, else what adb said in plain words.</summary>
        public static async Task<string> InstallApk(string adb, string serial, string apk)
        {
            var r = await Adb(adb, serial, "install -r " + Runner.Q(apk), 300000);
            if (r.text.Contains("Success")) return "";
            var m = Regex.Match(r.text, @"INSTALL_[A-Z_]+");
            Log.Write("adb install: " + r.text.Trim());
            if (m.Value == "INSTALL_FAILED_UPDATE_INCOMPATIBLE")
                return L.T("The app on the phone was signed with another key. Remove it on the phone first, knowing that the iOS disks inside it go with it, then install again.",
                           "Telefondaki uygulama başka bir anahtarla imzalanmış. İçindeki iOS diskleri de gider, bunu bilerek önce telefondan kaldırın, sonra yeniden kurun.");
            if (m.Value == "INSTALL_FAILED_VERSION_DOWNGRADE")
                return L.T("The phone already has a newer build of the app.", "Telefonda uygulamanın daha yeni bir derlemesi var.");
            if (m.Value == "INSTALL_FAILED_INSUFFICIENT_STORAGE")
                return L.T("The phone has no room for the app.", "Telefonda uygulamaya yer yok.");
            return string.IsNullOrEmpty(m.Value) ? r.text.Trim() : m.Value;
        }
    }

    /// <summary>One run of Send-ToPhone.ps1. Lives on when the page is left; the home tile shows it.</summary>
    public class PhoneJob
    {
        public static PhoneJob Current { get; private set; }
        public static event Action Changed;

        public string Os { get; private set; }
        public string Serial { get; private set; } = "";
        public string Adb { get; private set; } = "";
        public string Out { get; private set; }
        public bool Send { get; private set; }
        public bool DropAfter { get; private set; }
        public Runner Runner { get; private set; }
        public string Step { get; private set; } = "";
        public double Pct { get; private set; } = -1;
        public string Result { get; private set; } = "";     // done, failed, stopped
        public string Message { get; private set; } = "";
        public string Dest { get; private set; } = "";
        public double DestBytes { get; private set; }
        public double DestSize { get; private set; }
        bool stopping;
        public bool Running => Runner != null && Result == "";

        public static string Arg(string os) => os == "ios16" ? "16" : os == "ios26" ? "26" : "watchos";
        public static string FileName(string os) => os == "ios16" ? "ASoftware-iOS16.asoft" : os == "ios26" ? "ASoftware-iOS26.asoft" : "ASoftware-watchOS.asoft";

        public static PhoneJob Start(string os, string folder, bool withData, string adb, string serial, bool dropAfter)
        {
            var j = new PhoneJob { Os = os, Out = Path.Combine(folder, FileName(os)), Send = serial != "", Serial = serial ?? "", Adb = adb ?? "", DropAfter = dropAfter && serial != "" };
            Directory.CreateDirectory(folder);
            var args = "-OS " + Arg(os) + " -Work " + Runner.Q(Guests.Work(os)) + " -Out " + Runner.Q(j.Out);
            if (os == "ios16") args += " -Dir " + Runner.Q(Guests.App(os));
            if (withData && os == "ios16") args += " -WithMyData";
            if (serial == "") args += " -NoSend";
            var env = new Dictionary<string, string>();
            if (serial != "")
            {
                env["ANDROID_SERIAL"] = serial;
                env["PATH"] = Path.GetDirectoryName(adb) + ";" + Environment.GetEnvironmentVariable("PATH");
            }
            var script = Path.Combine(Guests.App(os), "scripts", "Send-ToPhone.ps1");
            var log = Path.Combine(AppPaths.LocalData, "logs", $"send-to-phone-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            j.Runner = new Runner(script, args, log);
            j.Runner.Progress += j.OnProgress;
            j.Runner.Exited += j.OnExit;
            Current = j;
            j.Runner.Start(env);
            Changed?.Invoke();
            return j;
        }

        // ##asoft|step|phone|N|OF|ID|start|TITLE   pct|phone|ID|0-100|   push|DEST|BYTES
        void OnProgress(string[] f)
        {
            if (f[0] == "step" && f.Length >= 7 && f[6] == "start") { Step = f[5]; Pct = -1; Changed?.Invoke(); }
            else if (f[0] == "pct" && f.Length >= 5 && double.TryParse(f[3], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var p)) Pct = p;
            else if (f[0] == "push" && f.Length >= 3) { Dest = f[1]; double.TryParse(f[2], out var b); DestBytes = b; }
        }

        void OnExit(int code)
        {
            if (stopping)
            {
                Result = "stopped";
                Tidy(true);
            }
            else if (code == 0)
            {
                Result = "done";
                if (DropAfter && Sent) try { File.Delete(Out); } catch { }
            }
            else
            {
                Result = "failed";
                var lines = Runner.Lines;
                Message = lines.LastOrDefault(l => l.Trim() != "" && !l.StartsWith("At ", StringComparison.Ordinal) && !l.TrimStart().StartsWith("+ ", StringComparison.Ordinal)) ?? ("exit " + code);
                Tidy(false);
            }
            Log.Write($"send-to-phone {Os}: {Result} {Message}");
            Changed?.Invoke();
        }

        public bool Sent => Runner != null && Runner.Lines.Any(l => l.StartsWith("Done. On the phone", StringComparison.Ordinal));

        /// <summary>What the script leaves when it is killed before its own clean-up: its temporary folders, a half file.</summary>
        void Tidy(bool file)
        {
            try
            {
                var beside = Path.Combine(Path.GetDirectoryName(Out), "asoft-bundle-" + Arg(Os) + ".tmp");
                if (Directory.Exists(beside)) Directory.Delete(beside, true);
                if (Os == "ios16")
                {
                    var t = Path.Combine(Guests.Work(Os), "tmp", "phone-bundle");
                    if (Directory.Exists(t)) Directory.Delete(t, true);
                }
                if (file && File.Exists(Out)) File.Delete(Out);
            }
            catch (Exception e) { Log.Write("send-to-phone: tidy: " + e.Message); }
        }

        public void Stop()
        {
            if (!Running) return;
            stopping = true;
            Runner.Kill();
        }

        /// <summary>adb push prints no progress into a pipe: the size of the file on the phone tells it.</summary>
        public async Task PollPush()
        {
            if (Step != "push" || Dest == "" || DestBytes <= 0 || Serial == "") return;
            var r = await Phone.Adb(Adb, Serial, "shell stat -c %s " + Dest, 8000);
            if (double.TryParse(r.text.Trim(), out var n)) DestSize = n;
        }

        /// <summary>The whole job, 0 to 1.</summary>
        public double Fraction()
        {
            if (Result == "done") return 1;
            double disk = Send ? 0.70 : 0.90, file = Send ? 0.08 : 0.09, tree = 0.01, push = Send ? 0.21 : 0;
            double p = Math.Max(0, Pct) / 100;
            switch (Step)
            {
                case "prepare": return 0;
                case "disk": return tree + disk * p;
                case "file": return tree + disk;
                case "push": return tree + disk + file + (DestBytes > 0 ? push * Math.Min(1, DestSize / DestBytes) : 0);
                default: return 0;
            }
        }

        public string StepText()
        {
            switch (Step)
            {
                case "prepare": return L.T("Preparing", "Hazırlanıyor");
                case "disk": return L.T("Packing the disk", "Disk paketleniyor") + (Pct >= 0 ? $" · {Pct:0} %" : "");
                case "file": return L.T("Making the file", "Dosya yapılıyor");
                case "push": return L.T("Sending to the phone", "Telefona gönderiliyor") + (DestBytes > 0 ? $" · {L.Size(DestSize)} / {L.Size(DestBytes)}" : "");
                default: return L.T("Starting", "Başlıyor");
            }
        }
    }
}
