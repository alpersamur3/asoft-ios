using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using ASoftware.Engine;

namespace ASoftware
{
    public partial class App : Application
    {
    }

    public static class Program
    {
        /// <summary>Test switches: -config FILE (another launcher.json), -shot FILE.png -page home|ios26|ios16|watch|vision|wizard|settings
        /// [-tab saves] [-theme dark|light] [-lang en|tr] [-size WxH] [-scroll PX] [-state os=kind,...] (draws the window into a PNG and quits;
        /// -state makes up a state the test bed does not have: running, saving, stopping, starting, saved, ready, none, install:NN).</summary>
        public static string Arg(string name)
        {
            var a = Environment.GetCommandLineArgs();
            for (int i = 1; i < a.Length - 1; i++) if (string.Equals(a[i], name, StringComparison.OrdinalIgnoreCase)) return a[i + 1];
            return null;
        }
        public static bool Flag(string name) => Environment.GetCommandLineArgs().Skip(1).Any(x => string.Equals(x, name, StringComparison.OrdinalIgnoreCase));

        [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);

        [STAThread]
        public static int Main(string[] args)
        {
            // iOS 26's GPU check (ios26\scripts\gpu-check.cs), in a process of its own: a Vulkan driver that
            // crashes takes only this one down. Lines on stdout, exit 0 / 1 / 3 as gpu-check.ps1's.
            if (Flag("-gpu-check"))
            {
                var h = GetStdHandle(-11);
                if (h == IntPtr.Zero || h == new IntPtr(-1)) AttachConsole(-1);
                try { return GpuCheck.Run(); }
                catch (Exception e) { Console.WriteLine("result|error|" + e.GetType().Name + ": " + e.Message); return 2; }
            }
            // per-monitor DPI (with the manifest's PerMonitorV2)
            AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges", false);
            var cfg = Arg("-config");
            if (cfg != null) AppPaths.ConfigFile = Path.GetFullPath(cfg);
            bool shot = Arg("-shot") != null;

            // one launcher per config: a second start shows the first one's window
            var id = "ASoftwareLauncher-" + (AppPaths.ConfigFile.ToLowerInvariant().GetHashCode() & 0x7fffffff);
            Mutex one = null;
            EventWaitHandle show = null;
            if (!shot)
            {
                one = new Mutex(true, "Local\\" + id, out bool first);
                show = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\" + id + ".show");
                if (!first) { show.Set(); return 0; }
            }
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Write("crash: " + e.ExceptionObject);
            var app = new App();
            app.InitializeComponent();
            app.DispatcherUnhandledException += (s, e) =>
            {
                Log.Write("error: " + e.Exception);
                e.Handled = true;
                try { Views.Dialog.Show(null, L.T("Something went wrong", "Bir şeyler ters gitti"), e.Exception.Message + "\n\n" + Log.File, L.K("OK")); } catch { }
            };
            var conf = LauncherConfig.Load();
            L.Set(Arg("-lang") ?? conf.Lang);
            Theme.Init(Arg("-theme") ?? conf.Theme);
            var w = new Views.MainWindow();
            if (show != null)
            {
                var t = new Thread(() =>
                {
                    while (show.WaitOne()) app.Dispatcher.BeginInvoke(new Action(w.Reveal));
                }) { IsBackground = true };
                t.Start();
            }
            app.MainWindow = w;
            if (!(Flag("-tray") && !shot)) w.Show();
            int rc = app.Run();
            GC.KeepAlive(one);
            return rc;
        }
    }
}
