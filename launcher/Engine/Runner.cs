using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace ASoftware.Engine
{
    /// <summary>One of the scripts (installers, start scripts) as a child process with no window: its output lines,
    /// its machine-readable progress lines (##asoft|...), its exit. The launcher stops only the processes it started.</summary>
    public sealed class Runner
    {
        public string Script { get; }
        public string Args { get; }
        public int Pid { get; private set; }
        public int? ExitCode { get; private set; }
        public bool Running => Pid != 0 && ExitCode == null;
        public string LogFile { get; }
        public DateTime Started { get; private set; }
        readonly List<string> lines = new List<string>();
        // each output stream's end (its null line): all its lines are in by then
        readonly ManualResetEventSlim outEnded = new ManualResetEventSlim(), errEnded = new ManualResetEventSlim();
        readonly object logGate = new object();
        Process proc;

        public event Action<string> Line;          // every output line (not progress lines)
        public event Action<string[]> Progress;    // ##asoft|kind|... split on |
        public event Action<int> Exited;

        public Runner(string script, string args, string logFile)
        {
            Script = script; Args = args; LogFile = logFile;
        }

        [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern int GetOEMCP();
        public static readonly Encoding Oem = GetOem();
        static Encoding GetOem() { try { return Encoding.GetEncoding(GetOEMCP()); } catch { return Encoding.Default; } }

        public static string Q(string a) => a == "" || a.IndexOfAny(new[] { ' ', '\t', '"', '\'' }) >= 0 ? "\"" + a.Replace("\"", "\\\"") + "\"" : a;

        public IReadOnlyList<string> Lines { get { lock (lines) return lines.ToList(); } }

        public void Start(IDictionary<string, string> env = null, string workDir = null)
        {
            var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File " + Q(Script) + " " + Args)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
                // Windows PowerShell writes a redirected console in the OEM code page (857 on a Turkish PC)
                StandardOutputEncoding = Oem, StandardErrorEncoding = Oem,
                WorkingDirectory = workDir ?? Path.GetDirectoryName(Script)
            };
            psi.EnvironmentVariables["ASOFT_PROGRESS"] = "1";
            if (env != null) foreach (var kv in env) psi.EnvironmentVariables[kv.Key] = kv.Value;
            Directory.CreateDirectory(Path.GetDirectoryName(LogFile));
            File.AppendAllText(LogFile, $"\r\n# {DateTime.Now:yyyy-MM-dd HH:mm:ss} powershell -File {Script} {Args}\r\n", Encoding.UTF8);
            Log.Write($"run {Script} {Args}");
            proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.OutputDataReceived += (s, e) => { if (e.Data != null) Got(e.Data); else outEnded.Set(); };
            proc.ErrorDataReceived += (s, e) => { if (e.Data != null) Got(e.Data); else errEnded.Set(); };
            proc.Exited += (s, e) =>
            {
                // the last lines first: both streams' ends, at most 3 s. (Not WaitForExit(): it waits for them with no limit,
                // and what the script started with inherited handles (QEMU through Start-Process -Redirect...) holds
                // them open for as long as it runs. Lines that come later still go to the log and Lines.)
                var t = Stopwatch.StartNew();
                if (!outEnded.Wait(3000) || !errEnded.Wait(Math.Max(0, 3000 - (int)t.ElapsedMilliseconds)))
                    Log.Write($"{Path.GetFileName(Script)} ended; a process it started still holds its output open");
                ExitCode = proc.ExitCode;
                Append($"# exit {ExitCode} at {DateTime.Now:HH:mm:ss}");
                Log.Write($"exit {ExitCode}: {Path.GetFileName(Script)}");
                Exited?.Invoke(ExitCode.Value);
            };
            Started = DateTime.Now;
            proc.Start();
            Pid = proc.Id;
            proc.StandardInput.Close();     // questions read "" (the scripts take their defaults)
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
        }

        void Got(string l)
        {
            l = l.Replace("\0", "").TrimEnd();
            Append(l);
            int i = l.IndexOf("##asoft|", StringComparison.Ordinal);
            if (i >= 0)
            {
                Progress?.Invoke(l.Substring(i + 8).Split('|'));
                return;
            }
            lock (lines) { lines.Add(l); if (lines.Count > 5000) lines.RemoveRange(0, 1000); }
            Line?.Invoke(l);
        }

        // (the two streams' lines, and a late one with the exit line, come on different threads: one writer at a time)
        void Append(string l)
        {
            lock (logGate) try { File.AppendAllText(LogFile, l + "\r\n", Encoding.UTF8); } catch { }
        }

        /// <summary>Stops this script and what it started (by process id, never by name).</summary>
        public void Kill()
        {
            if (Running) Native.KillTree(Pid);
        }

        // (a finite wait: on .NET Framework only WaitForExit(-1) also waits for the output streams' end)
        public bool Wait(int ms) => proc == null || proc.WaitForExit(ms);
    }
}
