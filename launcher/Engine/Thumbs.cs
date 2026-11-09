using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ASoftware.Engine
{
    /// <summary>Each system's last screen, for its device in the launcher: thumbs\&lt;os&gt;.jpg beside the launcher.json in use
    /// (a run with -config keeps its own). Taken with QMP's screendump while the guest runs. QEMU's QMP serves one client at
    /// a time and this is the least important one: when QMP does not greet at once (the launcher's save, load or turn off,
    /// Watch-AutoSave, a start script waiting for the machine to run, or QEMU's main loop busy saving) it lets go and
    /// tries again at the next round, so it never queues in front of anything for long.</summary>
    public static class Thumbs
    {
        /// <summary>A system's picture changed (taken, or dropped); raised on any thread.</summary>
        public static event Action<string> Changed;

        public static string Dir => Path.Combine(Path.GetDirectoryName(Path.GetFullPath(AppPaths.ConfigFile)), "thumbs");
        public static string FileOf(string os) => Path.Combine(Dir, os + ".jpg");

        const int Width = 360;       // twice what a device on the home page shows
        const int Budget = 3000;     // ms one capture may take in all
        const int Greeting = 800;    // ms QMP has to greet: longer means another client holds it

        static readonly Dictionary<string, (DateTime time, long size, BitmapSource img)> cache = new Dictionary<string, (DateTime, long, BitmapSource)>();
        static readonly Dictionary<string, Task> taking = new Dictionary<string, Task>();
        static readonly HashSet<string> said = new HashSet<string>();

        /// <summary>The picture or null, read again only when the file changed. Frozen: any thread may use it.</summary>
        public static BitmapSource Get(string os)
        {
            try
            {
                var f = new FileInfo(FileOf(os));
                if (!f.Exists) { lock (cache) cache.Remove(os); return null; }
                lock (cache) if (cache.TryGetValue(os, out var c) && c.time == f.LastWriteTimeUtc && c.size == f.Length) return c.img;
                BitmapSource img = null;
                try { img = Load(f.FullName); }
                catch (Exception e) { Log.Write(os + ": its last screen does not read: " + e.Message); }
                // (one that does not read is not read again until it changes)
                lock (cache) cache[os] = (f.LastWriteTimeUtc, f.Length, img);
                return img;
            }
            catch { return null; }
        }

        /// <summary>Read whole into memory, so the file is never held open: the next capture replaces it.</summary>
        static BitmapSource Load(string file)
        {
            var b = new BitmapImage();
            b.BeginInit();
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.StreamSource = new MemoryStream(File.ReadAllBytes(file));
            b.EndInit();
            b.Freeze();
            return b;
        }

        /// <summary>A disk is erased or installed afresh: its old screen must not stand for the new system.</summary>
        public static void Drop(string os)
        {
            try
            {
                var f = FileOf(os);
                if (File.Exists(f)) { File.Delete(f); Log.Write(os + ": its last screen is dropped (a new disk)"); }
            }
            catch (Exception e) { Log.Write(os + ": cannot drop its last screen: " + e.Message); }
            lock (cache) cache.Remove(os);
            Changed?.Invoke(os);
        }

        /// <summary>Takes the screen of a running guest in the background; one at a time per system (a second ask gets the
        /// first's task). Never throws.</summary>
        public static Task Capture(string os)
        {
            lock (taking)
            {
                if (taking.TryGetValue(os, out var t)) return t;
                t = Task.Run(() => Take(os));
                taking[os] = t;
                t.ContinueWith(_ => { lock (taking) taking.Remove(os); });
                return t;
            }
        }

        /// <summary>Once more just before Save and close or Turn off: waits at most the capture's budget, never fails.</summary>
        public static async Task Before(string os)
        {
            try { await Task.WhenAny(Capture(os), Task.Delay(Budget + 500)); }
            catch { }
        }

        static void Take(string os)
        {
            GuestRun run;
            lock (Machines.Runs) Machines.Runs.TryGetValue(os, out run);
            if (run == null || run.QemuPid == 0 || run.Busy != "" || !Native.Alive(run.QemuPid)) return;
            string png = null;
            try
            {
                Directory.CreateDirectory(Dir);
                png = Path.Combine(QemuDir(os), os + ".screen.png");
                try { File.Delete(png); } catch { }
                var err = Screendump(Guests.QmpPort(os), png);
                if (err == "") return;                      // QMP was taken or not there yet: the next round
                if (err != null) { Once(os, err); return; }
                var frame = Decode(png);
                // the display sleeps (a black frame): the picture from before stays
                if (NearlyBlack(frame)) return;
                BitmapSource small = frame;
                if (frame.PixelWidth > Width)
                {
                    double k = (double)Width / frame.PixelWidth;
                    small = new TransformedBitmap(frame, new ScaleTransform(k, k));
                }
                var enc = new JpegBitmapEncoder { QualityLevel = 85 };
                enc.Frames.Add(BitmapFrame.Create(new FormatConvertedBitmap(small, PixelFormats.Bgr24, null, 0)));
                // written beside it, then put in its place: a reader never sees half a picture
                var dest = FileOf(os);
                var tmp = dest + ".tmp";
                using (var f = File.Create(tmp)) enc.Save(f);
                if (File.Exists(dest)) File.Replace(tmp, dest, null);
                else File.Move(tmp, dest);
                lock (said) said.Remove(os);
                Changed?.Invoke(os);
            }
            catch (Exception e) { Once(os, e.Message); }
            finally { if (png != null) try { File.Delete(png); } catch { } }
        }

        /// <summary>A failure goes to the log once, not every round, until a capture works again.</summary>
        static void Once(string os, string what)
        {
            lock (said) if (!said.Add(os)) return;
            Log.Write(os + ": its screen was not taken: " + what);
        }

        /// <summary>QMP screendump into @file (QEMU writes it). null when it worked, "" when QMP was taken or did not answer
        /// in time (skip this round), else what went wrong.</summary>
        static string Screendump(int port, string file)
        {
            int until = Environment.TickCount + Budget;
            int Left() => Math.Max(100, until - Environment.TickCount);
            using (var c = new TcpClient())
            {
                try { if (!c.ConnectAsync("127.0.0.1", port).Wait(500)) return ""; }
                catch { return ""; }
                var s = c.GetStream();
                var r = new StreamReader(s, new UTF8Encoding(false));
                var w = new StreamWriter(s, new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
                try
                {
                    // a free QMP greets at once; a connection it has not taken yet only waits in the queue
                    s.ReadTimeout = Greeting;
                    if (r.ReadLine() == null) return "";
                    s.ReadTimeout = Left();
                    w.WriteLine("{\"execute\":\"qmp_capabilities\"}");
                    if (Reply(r) == null) return "";
                    s.ReadTimeout = Left();
                    w.WriteLine("{\"execute\":\"screendump\",\"arguments\":{\"filename\":" + Qmp.Quote(file.Replace('\\', '/')) + ",\"format\":\"png\"}}");
                    var rep = Reply(r);
                    if (rep == null) return "";
                    if (rep.Contains("\"error\"")) return "screendump: " + rep;
                    return File.Exists(file) ? null : "screendump wrote no file";
                }
                catch (IOException) { return ""; }
            }
        }

        static string Reply(StreamReader r)
        {
            while (true)
            {
                var l = r.ReadLine();
                if (l == null) return null;
                if (l.Contains("\"return\"") || l.Contains("\"error\"")) return l;
                // events ({"event": ...}) are skipped
            }
        }

        static BitmapSource Decode(string file)
        {
            var d = BitmapDecoder.Create(new MemoryStream(File.ReadAllBytes(file)), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            return d.Frames[0];
        }

        /// <summary>Whether almost nothing on the frame is lit (one sample in 8 x 8 pixels).</summary>
        static bool NearlyBlack(BitmapSource b)
        {
            var c = new FormatConvertedBitmap(b, PixelFormats.Bgra32, null, 0);
            int w = c.PixelWidth, h = c.PixelHeight, stride = w * 4, lit = 0, n = 0;
            var row = new byte[stride];
            for (int y = 0; y < h; y += 8)
            {
                c.CopyPixels(new Int32Rect(0, y, w, 1), row, stride, 0);
                for (int x = 0; x < w; x += 8, n++)
                    if (Math.Max(row[x * 4], Math.Max(row[x * 4 + 1], row[x * 4 + 2])) > 40) lit++;
            }
            return lit < n * 0.004;
        }

        // QEMU opens the file with the C library's open(), which on Windows takes the ANSI code page: a folder whose name
        // has other letters (a user name with a ğ) goes to it by its short 8.3 name, else the guest's work folder has the file
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetShortPathName(string path, StringBuilder shortPath, int size);

        static bool Ascii(string s) { foreach (var ch in s) if (ch > 127) return false; return true; }

        static string QemuDir(string os)
        {
            var dir = Dir;
            if (Ascii(dir)) return dir;
            var sb = new StringBuilder(520);
            if (GetShortPathName(dir, sb, sb.Capacity) > 0 && Ascii(sb.ToString())) return sb.ToString();
            var work = Guests.Work(os);
            return work != "" && Ascii(work) && Directory.Exists(work) ? work : dir;
        }
    }
}
