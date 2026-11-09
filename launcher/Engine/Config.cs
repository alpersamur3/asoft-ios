using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace ASoftware.Engine
{
    public static class AppPaths
    {
        public static readonly string ExeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        /// <summary>The app folder: where installer\Setup-ASoftware.ps1 is (the exe's folder in an install or the
        /// release package; launcher\out\ of a checkout finds the checkout two levels up).</summary>
        public static readonly string Root = FindRoot(ExeDir);
        public static readonly string LocalData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ASoftware");
        public static string ConfigFile = Path.Combine(LocalData, "launcher.json");
        public static readonly string SetupState = Path.Combine(LocalData, "setup.json");
        public static readonly string Ios26Config = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ASoftware iOS 26", "ios26.config.json");
        public static string PauseFile => Path.Combine(LocalData, "pause.request");

        public static string FindRoot(string from)
        {
            var d = new DirectoryInfo(from);
            for (int i = 0; i < 4 && d != null; i++, d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "installer", "Setup-ASoftware.ps1"))) return d.FullName;
            return from;
        }

        public static bool IsAppFolder(string dir) =>
            !string.IsNullOrEmpty(dir) && Directory.Exists(dir) && File.Exists(Path.Combine(dir, "installer", "Setup-ASoftware.ps1"));
    }

    /// <summary>One OS's settings in launcher.json.</summary>
    public class OsConfig
    {
        /// <summary>The app folder with its scripts (an install's -Dir); empty: the launcher's own.</summary>
        public string App { get; set; } = "";
        public string Work { get; set; } = "";
        public int Smp { get; set; } = 4;
        /// <summary>MiB; 0 = the device tree's own size.</summary>
        public int RamMiB { get; set; } = 0;
        public bool Net { get; set; } = true;
        /// <summary>keep (what the OS writes stays, with quick boot) or throwaway.</summary>
        public string DiskMode { get; set; } = "keep";
        public bool QuickBoot { get; set; } = true;
        public string Wallpaper { get; set; } = "ios26";
        public bool Aod { get; set; } = true;
        public bool Sharp { get; set; } = true;
        /// <summary>IANA zone, region code, 12/24; empty = the PC's.</summary>
        public string TimeZone { get; set; } = "";
        public string Region { get; set; } = "";
        public string Clock { get; set; } = "";
        public string GpuMode { get; set; } = "";
        public string GpuDriver { get; set; } = "";
        /// <summary>iOS 26: the PC's GPU it draws on (auto, integrated, discrete), and no generated commands on it.</summary>
        public string HostGpu { get; set; } = "auto";
        public bool NoGeneratedCommands { get; set; }
    }

    /// <summary>What the launcher knows of a save (an internal snapshot of a disk): the guest it was made with.</summary>
    public class SaveMeta
    {
        public string Disk { get; set; } = "";
        public string Name { get; set; } = "";
        public string Label { get; set; } = "";
        public int RamMiB { get; set; }
        public int Smp { get; set; }
        public string Made { get; set; } = "";
        /// <summary>The settings it loads with only (Guests.Shape); "" for a save from before it was kept.</summary>
        public string Shape { get; set; } = "";
    }

    public class InstallChoice
    {
        public bool Ios16 { get; set; }
        public bool Ios26 { get; set; }
        public bool Watch { get; set; }
        public string Linux { get; set; } = "wsl";
        public string Dir { get; set; } = "";
        public string GpuMode { get; set; } = "cloudos";
        public string GpuDriver { get; set; } = "";
        public string Started { get; set; } = "";
        public string Stage { get; set; } = "";
    }

    public class LauncherConfig
    {
        public int Format { get; set; } = 1;
        public string Lang { get; set; } = "auto";
        public string Theme { get; set; } = "auto";
        public bool CloseToTray { get; set; } = true;
        public bool CheckUpdates { get; set; } = true;
        public string SkippedVersion { get; set; } = "";
        public string LastUpdateCheck { get; set; } = "";
        public OsConfig Ios16 { get; set; } = new OsConfig { Smp = 4 };
        public OsConfig Ios26 { get; set; } = new OsConfig { Smp = 4, GpuMode = "" };
        public OsConfig Watch { get; set; } = new OsConfig { Smp = 4 };
        public List<SaveMeta> Saves { get; set; } = new List<SaveMeta>();
        public InstallChoice Install { get; set; } = new InstallChoice();
        public string Imported { get; set; } = "";

        public static LauncherConfig Current { get; private set; }

        public OsConfig For(string os) => os == "ios16" ? Ios16 : os == "ios26" ? Ios26 : Watch;

        public static LauncherConfig Load()
        {
            var c = Json.Read<LauncherConfig>(AppPaths.ConfigFile);
            bool fresh = c == null;
            // one that does not read is kept beside the new one, not written over
            if (c == null && File.Exists(AppPaths.ConfigFile))
                try { File.Copy(AppPaths.ConfigFile, AppPaths.ConfigFile + ".bad", true); Log.Write("kept the unreadable " + AppPaths.ConfigFile + " as .bad"); } catch { }
            if (c == null) c = new LauncherConfig();
            if (c.Ios16 == null) c.Ios16 = new OsConfig();
            if (c.Ios26 == null) c.Ios26 = new OsConfig();
            if (c.Watch == null) c.Watch = new OsConfig();
            if (c.Saves == null) c.Saves = new List<SaveMeta>();
            if (c.Install == null) c.Install = new InstallChoice();
            if (string.IsNullOrEmpty(c.Imported)) c.ImportOld();
            Current = c;
            if (fresh || c.dirty) c.Save();
            return c;
        }

        bool dirty;

        public void Save()
        {
            try { Json.Write(AppPaths.ConfigFile, this); }
            catch (Exception e) { Log.Write("cannot write " + AppPaths.ConfigFile + ": " + e.Message); }
        }

        /// <summary>First run: the setup's choices (setup.json) and iOS 26's menu config (ios26.config.json).</summary>
        void ImportOld()
        {
            var from = new List<string>();
            var setup = Json.ReadObject(AppPaths.SetupState);
            if (setup != null)
            {
                string dir = Json.Str(setup, "Dir"), ver = Json.Str(setup, "Version");
                if (dir != "")
                {
                    Install.Dir = dir;
                    Install.Ios16 = ver == "ios16" || ver == "both";
                    Install.Ios26 = ver == "ios26" || ver == "both";
                    Install.Watch = Json.Str(setup, "Watch") == "yes";
                    Install.Linux = Json.Str(setup, "Linux") == "helper" ? "helper" : "wsl";
                    Install.Stage = Json.Str(setup, "Stage");
                    Install.Started = Json.Str(setup, "Started");
                    if (Install.Ios16) { Ios16.App = dir; Ios16.Work = Path.Combine(dir, "work"); }
                    if (Install.Ios26) { Ios26.App = dir; Ios26.Work = Path.Combine(dir, "work"); }
                    if (Install.Watch) { Watch.App = dir; Watch.Work = Path.Combine(dir, "work"); }
                }
                var lang = Json.Str(setup, "Lang");
                if (lang == "en" || lang == "tr") Lang = lang;
                from.Add("setup.json");
            }
            var c26 = Json.ReadObject(AppPaths.Ios26Config);
            if (c26 != null)
            {
                var w = Json.Str(c26, "Work");
                if (w != "") { Ios26.Work = w; if (Watch.Work == "") Watch.Work = w; }
                Ios26.GpuMode = Json.Str(c26, "GpuMode");
                Ios26.GpuDriver = Json.Str(c26, "GpuDriver");
                var wp = Json.Str(c26, "Wallpaper"); if (wp == "collections") Ios26.Wallpaper = wp;
                var dm = Json.Str(c26, "DiskMode"); Ios26.DiskMode = dm == "throwaway" ? "throwaway" : "keep";
                var qb = Json.Bool(c26, "QuickBoot"); if (qb.HasValue) Ios26.QuickBoot = qb.Value;
                var net = Json.Bool(c26, "Net"); if (net.HasValue) Ios26.Net = net.Value;
                var smp = Json.Int(c26, "Smp"); if (smp == 8) Ios26.Smp = 8;
                var hg = Json.Str(c26, "HostGpu"); if (hg == "integrated" || hg == "discrete") Ios26.HostGpu = hg;
                from.Add("ios26.config.json");
            }
            var e16 = Environment.GetEnvironmentVariable("ASOFT_WORK");
            if (Ios16.Work == "" && !string.IsNullOrEmpty(e16)) { Ios16.Work = e16; from.Add("ASOFT_WORK"); }
            var e26 = Environment.GetEnvironmentVariable("ASOFT26_WORK");
            if (Ios26.Work == "" && !string.IsNullOrEmpty(e26)) { Ios26.Work = e26; from.Add("ASOFT26_WORK"); }
            Imported = DateTime.Now.ToString("s") + (from.Count > 0 ? ": " + string.Join(", ", from) : ": nothing to import");
            dirty = true;
            Log.Write("imported " + Imported);
        }

        /// <summary>The keys the iOS 26 scripts read (Install-iOS26.ps1, Start-iOS26-Menu.ps1, Install-watchOS.ps1) kept in step.</summary>
        public void WriteIos26Config()
        {
            try
            {
                var o = Json.ReadObject(AppPaths.Ios26Config) ?? new Dictionary<string, object>();
                if (Ios26.Work != "") o["Work"] = Ios26.Work;
                o["GpuMode"] = Ios26.GpuMode ?? "";
                o["GpuDriver"] = Ios26.GpuDriver ?? "";
                o["Wallpaper"] = Ios26.Wallpaper;
                o["DiskMode"] = Ios26.DiskMode == "throwaway" ? "throwaway" : "persist";
                o["QuickBoot"] = Ios26.QuickBoot;
                o["Net"] = Ios26.Net;
                o["Smp"] = Ios26.Smp;
                o["HostGpu"] = Ios26.HostGpu ?? "auto";
                Json.Write(AppPaths.Ios26Config, o);
            }
            catch (Exception e) { Log.Write("cannot write " + AppPaths.Ios26Config + ": " + e.Message); }
        }

        public SaveMeta FindSave(string disk, string name) =>
            Saves.FirstOrDefault(s => string.Equals(s.Disk, disk, StringComparison.OrdinalIgnoreCase) && s.Name == name);

        public void SetSave(string disk, string name, int ramMiB, int smp, string shape = null)
        {
            var s = FindSave(disk, name);
            if (s == null) { s = new SaveMeta { Disk = disk, Name = name }; Saves.Add(s); }
            s.RamMiB = ramMiB; s.Smp = smp; s.Made = DateTime.Now.ToString("s");
            if (shape != null) s.Shape = shape;
            Save();
        }

        public void DropSave(string disk, string name)
        {
            Saves.RemoveAll(s => string.Equals(s.Disk, disk, StringComparison.OrdinalIgnoreCase) && s.Name == name);
            Save();
        }
    }
}
