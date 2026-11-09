using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace ASoftware.Engine
{
    /// <summary>A short QMP session on 127.0.0.1:port (QEMU takes one client at a time; this one leaves at once).</summary>
    public static class Qmp
    {
        public static bool Open(int port)
        {
            try
            {
                using (var c = new TcpClient())
                {
                    var t = c.ConnectAsync("127.0.0.1", port);
                    return t.Wait(700) && c.Connected;
                }
            }
            catch { return false; }
        }

        /// <summary>Runs commands (JSON lines) and returns each one's reply line; throws when QMP is not there.</summary>
        public static List<string> Run(int port, params string[] commands) => Run(port, 30000, commands);

        public static List<string> Run(int port, int timeoutMs, params string[] commands)
        {
            var replies = new List<string>();
            using (var c = new TcpClient())
            {
                if (!c.ConnectAsync("127.0.0.1", port).Wait(3000)) throw new IOException("QMP " + port + " does not answer");
                c.ReceiveTimeout = timeoutMs;
                var s = c.GetStream();
                var r = new StreamReader(s, new UTF8Encoding(false));
                var w = new StreamWriter(s, new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
                r.ReadLine();   // greeting
                w.WriteLine("{\"execute\":\"qmp_capabilities\"}");
                ReadReply(r);
                foreach (var cmd in commands)
                {
                    w.WriteLine(cmd);
                    replies.Add(ReadReply(r));
                }
            }
            return replies;
        }

        static string ReadReply(StreamReader r)
        {
            while (true)
            {
                var l = r.ReadLine();
                if (l == null) throw new IOException("QMP closed");
                if (l.Contains("\"return\"") || l.Contains("\"error\"")) return l;
                // events ({"event": ...}) are skipped
            }
        }

        public static string Cmd(string name) => "{\"execute\":\"" + name + "\"}";

        public static string Hmp(string line) =>
            "{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":" + Quote(line) + "}}";

        /// <summary>An HMP line through QMP; its text output (an error from savevm is text, not a QMP error).</summary>
        public static string HmpRun(int port, string line, int timeoutMs = 600000)
        {
            var rep = Run(port, timeoutMs, Hmp(line))[0];
            var o = Json.Parse(rep) as Dictionary<string, object>;
            if (o != null && o.TryGetValue("error", out var e))
                throw new IOException(Json.Str(e as Dictionary<string, object>, "desc"));
            return o != null && o.TryGetValue("return", out var ret) ? Convert.ToString(ret).Trim() : "";
        }

        public static string Quote(string s)
        {
            var sb = new StringBuilder("\"");
            foreach (var ch in s)
            {
                if (ch == '"' || ch == '\\') sb.Append('\\').Append(ch);
                else if (ch < 0x20) sb.Append("\\u").Append(((int)ch).ToString("x4"));
                else sb.Append(ch);
            }
            return sb.Append('"').ToString();
        }

        /// <summary>iOS 26 / watchOS: "sync" on the guest's root shell (its serial console), so a quit loses nothing.
        /// True when the shell answered.</summary>
        public static bool SerialSync(int port, int timeoutMs = 60000)
        {
            try
            {
                using (var c = new TcpClient())
                {
                    if (!c.ConnectAsync("127.0.0.1", port).Wait(2000)) return false;
                    var s = c.GetStream();
                    s.ReadTimeout = 1000;
                    var mark = "ASOFT-SYNCED-" + Environment.TickCount;
                    var cmd = Encoding.ASCII.GetBytes("\nsync; echo " + mark.Substring(0, 6) + "\"" + mark.Substring(6) + "\"\n");
                    s.Write(cmd, 0, cmd.Length);
                    var got = new StringBuilder();
                    var buf = new byte[4096];
                    var until = DateTime.UtcNow.AddMilliseconds(timeoutMs);
                    while (DateTime.UtcNow < until)
                    {
                        try
                        {
                            int n = s.Read(buf, 0, buf.Length);
                            if (n <= 0) break;
                            got.Append(Encoding.ASCII.GetString(buf, 0, n));
                            if (got.ToString().Contains(mark)) return true;
                        }
                        catch (IOException) { }
                    }
                }
            }
            catch { }
            return false;
        }
    }
}
