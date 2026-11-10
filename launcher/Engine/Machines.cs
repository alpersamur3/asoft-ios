using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace ASoftware.Engine
{
    /// <summary>A running guest: the QEMU process, what it was started with, and whether the launcher started it.</summary>
    public class GuestRun
    {
        public string Os;
        public int QemuPid;
        public Runner Script;          // the start script (iOS 16's stays until QEMU ends)
        public bool Ours;              // started here: only these are ever stopped by process id
        public int RamMiB, Smp;
        public string Disk = "";       // the disk that keeps its saves ("" when throwaway)
        public bool QuickBoot;
        public string Shape = "";      // the settings it runs with (Guests.Shape); "" when adopted (not known)
        public string QuickAtStart = ""; // the quick save's key when it started: another at the end was made in this run
        public string RunFolder = "";
        /// <summary>The start resumes a save (as the launcher asked, unless the script said the state did not load).</summary>
        public bool Resumed;
        public DateTime Started = DateTime.Now;
        public string Busy = "";       // "saving", "stopping": a request is on its way
    }

    /// <summary>Starting, saving and stopping the guests through their own scripts, QMP and their windows.</summary>
    public static class Machines
    {
        public static readonly Dictionary<string, GuestRun> Runs = new Dictionary<string, GuestRun>();
        public static event Action<string> Changed;      // os
        public static event Action<string, string> Note; // os, a message for the user

        static void Say(string os, string text) { Log.Write(os + ": " + text); Note?.Invoke(os, text); }

        // --- checks before a start ---------------------------------------------------------------
        /// <summary>Ports another process holds that this OS needs.</summary>
        public static List<string> PortProblems(string os)
        {
            var r = new List<string>();
            var l = Native.Listeners();
            foreach (var port in Guests.Ports(os))
            {
                if (!l.TryGetValue(port, out var pid)) continue;
                string who = "pid " + pid;
                try { using (var p = System.Diagnostics.Process.GetProcessById(pid)) who = p.ProcessName + ".exe (pid " + pid + ")"; } catch { }
                r.Add(L.T($"port {port} is in use by {who}", $"{port} numaralı port kullanımda: {who}"));
            }
            return r;
        }

        /// <summary>Whether this PC has the memory for one more guest beside the ones running. (block, warn)</summary>
        public static (string block, string warn) RamProblem(string os, int ramMiB, List<Native.Proc> qemus)
        {
            var m = Native.Memory();
            double need = ramMiB * 1048576.0 + Guests.QemuOverhead(os);
            var running = string.Join(", ", qemus.Select(q => $"pid {q.Pid} {L.Size(q.WorkingSet)}"));
            string ctx = qemus.Count > 0 ? L.T(" Guests running now: ", " Şu an çalışan konuklar: ") + running + "." : "";
            if (need > m.commitFree - 2e9)
                return (L.T($"{Guests.Name(os)} needs about {L.Size(need)} of memory and Windows has {L.Size(m.commitFree)} left to commit (RAM and page file).{ctx} Close a guest or other programs, or give it less RAM.",
                            $"{Guests.Name(os)} yaklaşık {L.Size(need)} bellek ister, Windows'un ayırabileceği {L.Size(m.commitFree)} kaldı (RAM ve sayfa dosyası).{ctx} Bir konuğu ya da başka programları kapatın veya daha az RAM verin."), null);
            if (need > m.free)
                return (null, L.T($"{Guests.Name(os)} needs about {L.Size(need)} and {L.Size(m.free)} of RAM is free now: Windows will page, and it will be slow.{ctx}",
                                  $"{Guests.Name(os)} yaklaşık {L.Size(need)} ister, şu an boş RAM {L.Size(m.free)}: Windows diske yazacak ve yavaşlayacak.{ctx}"));
            return (null, null);
        }

        /// <summary>The RAM and vCPUs a save loads with: its own (a state only loads into the machine it was made on).</summary>
        public static (int ram, int smp, bool known) SaveGuest(string os, string disk, string name)
        {
            var c = Guests.Cfg(os);
            var s = LauncherConfig.Current.FindSave(disk, name);
            if (s != null && s.Smp > 0 && (s.RamMiB > 0 || os == "ios16")) return (s.RamMiB, s.Smp, true);
            // made before the launcher: the tree's own RAM and the vCPUs the old menu had
            return (Guests.DefaultRam(os), c.Smp, false);
        }

        // --- start -------------------------------------------------------------------------------
        public static string StartArgs(string os, int ram, int smp, string loadState, string shape = null)
        {
            var c = Guests.Cfg(os);
            var a = new List<string> { "-Work", Runner.Q(Guests.Work(os)) };
            bool keep = c.DiskMode != "throwaway";
            // the network and GPU a save was made with (a save loads only into the machine it was made on), else the settings
            var sp = Guests.ShapeParts(shape);
            bool netOn = sp.TryGetValue("net", out var n) ? n == "1" : c.Net;
            string hostGpu = sp.TryGetValue("gpu", out var g) ? g : c.HostGpu;
            void Time()
            {
                if (c.TimeZone != "") a.AddRange(new[] { "-TimeZone", Runner.Q(c.TimeZone) });
                if (c.Region != "") a.AddRange(new[] { "-Region", c.Region });
                if (c.Clock != "") a.AddRange(new[] { "-Clock", c.Clock });
            }
            switch (os)
            {
                case "ios16":
                    a.AddRange(new[] { "-Cpus", smp.ToString() });
                    if (keep) a.Add("-Persist");
                    if (keep && !c.QuickBoot) a.Add("-NoQuickBoot");
                    if (!netOn) a.Add("-NoNet");
                    Time();
                    break;
                case "ios26":
                    a.AddRange(new[] { "-Name", "launcher", "-Smp", smp.ToString() });
                    if (keep) a.Add("-Persist");
                    if (!c.QuickBoot) a.Add("-NoQuickBoot");
                    if (netOn) a.Add("-Net");
                    if (c.Wallpaper == "collections") a.AddRange(new[] { "-Wallpaper", "collections" });
                    if (!c.Aod) a.Add("-NoAod");
                    if (ram != Guests.DefaultRam(os)) a.AddRange(new[] { "-RamMiB", ram.ToString() });
                    if (hostGpu == "integrated" || hostGpu == "discrete") a.AddRange(new[] { "-HostGpu", hostGpu });
                    if (c.NoGeneratedCommands) a.Add("-NoGeneratedCommands");
                    Time();
                    break;
                case "vision":
                    // (Start-visionOS.ps1: a device tree for 4, 6 and 8 vCPUs, its RAM the tree's; quick boot on unless
                    // -NoQuickBoot, as Start-watchOS.ps1's; the sound disk and the silent one have each their own saves)
                    a.AddRange(new[] { "-Cpus", (smp == 4 || smp == 6 ? smp : 8).ToString() });
                    if (Guests.Sound(os)) a.Add("-Sound");
                    if (!keep) a.Add("-Snapshot");
                    else if (!c.QuickBoot) a.Add("-NoQuickBoot");
                    if (!netOn) a.Add("-NoNet");
                    if (!c.Frame) a.Add("-NoFrame");
                    // the PC's GPU is iOS 26's setting (one choice for the guests reims-vgpu draws), or the save's
                    var visionGpu = sp.TryGetValue("gpu", out var vg) ? vg : Guests.HostGpu(os);
                    if (visionGpu == "integrated" || visionGpu == "discrete") a.AddRange(new[] { "-HostGpu", visionGpu });
                    break;
                default:
                    // (Start-watchOS.ps1: quick boot is on unless -NoQuickBoot)
                    a.AddRange(new[] { "-Smp", smp.ToString() });
                    if (!keep) a.Add("-Snapshot");
                    else if (!c.QuickBoot) a.Add("-NoQuickBoot");
                    if (!netOn) a.Add("-NoNet");
                    if (ram != Guests.DefaultRam(os)) a.AddRange(new[] { "-RamMiB", ram.ToString() });
                    break;
            }
            if (!string.IsNullOrEmpty(loadState)) a.AddRange(new[] { "-LoadState", Runner.Q(loadState) });
            return string.Join(" ", a);
        }

        static readonly Regex StartedLine = new Regex(@"started (.+?) pid (\d+) -> (.+)$");

        /// <summary>Starts an OS with its settings (or a save's own RAM and vCPUs). Checks first; throws with the reason.</summary>
        public static async Task<GuestRun> Start(string os, string loadState = null, bool ignoreRamWarning = false)
        {
            if (Runs.TryGetValue(os, out var have) && Native.Alive(have.QemuPid)) throw new InvalidOperationException(L.T($"{Guests.Name(os)} is running already.", $"{Guests.Name(os)} zaten çalışıyor."));
            var c = Guests.Cfg(os);
            var script = Guests.StartScript(os);
            if (!File.Exists(script)) throw new FileNotFoundException(L.T("No start script: ", "Başlatma betiği yok: ") + script);
            var ports = PortProblems(os);
            if (ports.Count > 0) throw new InvalidOperationException(string.Join("; ", ports) + L.T(". Close what holds it first.", ". Önce onu tutan programı kapatın."));
            var disk = Guests.SaveDisk(os);
            int ram = Guests.Ram(os), smp = Guests.Smp(os);
            bool saves = Guests.HasQuickSave(os);
            bool quick = saves && c.DiskMode != "throwaway" && c.QuickBoot;
            string shape = Guests.Shape(os, 0, smp);
            var snaps = disk == "" || !saves ? new List<Guests.Snap>() : await Task.Run(() => Guests.Snapshots(os, disk));
            string quickAtStart = snaps.FirstOrDefault(s => s.Quick)?.Key ?? "";
            // The quick save is resumed by itself once; then it is the way back, which only loads when asked (loadState
            // asoft-quick, MainWindow.GoBack). It loads only into the machine it was made on: made with other settings than
            // these (a setting changed since), this start boots afresh with them, and the save stays as the way back.
            string resumes = loadState;
            if (resumes == null && quick)
            {
                var q = snaps.FirstOrDefault(s => s.Quick && !s.WayBack);
                if (q != null)
                {
                    var meta = LauncherConfig.Current.FindSave(disk, Guests.QuickName);
                    if (Guests.Fits(os, meta, shape)) resumes = Guests.QuickName;
                    else
                    {
                        await Task.Run(() => Guests.MarkWayBack(os, disk));
                        Say(os, L.T($"Starts afresh with the new settings. The save of {Guests.When(q.When)} stays as a way back; it opens with {Guests.Hardware(os, Guests.SaveShape(os, meta))}.",
                                    $"Yeni ayarlarla baştan açılıyor. {Guests.When(q.When)} kaydı geri dönüş noktası olarak kalır; {Guests.Hardware(os, Guests.SaveShape(os, meta))} ile açılır."));
                    }
                }
            }
            // a save asked for (the Saves tab, the way back) loads with what it was made with: its RAM, vCPUs, network and
            // GPU, for this run only (the settings stay for later starts)
            if (loadState != null)
            {
                var g = SaveGuest(os, disk, loadState);
                if (g.smp > 0) smp = g.smp;
                if (os != "ios16") ram = g.ram;
                var m = LauncherConfig.Current.FindSave(disk, loadState);
                shape = m != null && m.Shape != "" ? m.Shape : Guests.Shape(os, ram, smp);
                if (shape != Guests.Shape(os))
                    Say(os, L.T($"Opens the save with {Guests.Hardware(os, shape)}, as it was made; the settings apply at the next start without a save.",
                                $"Kayıt alındığı gibi {Guests.Hardware(os, shape)} ile açılıyor; ayarlar kayıtsız bir sonraki açılışta geçerli olur."));
            }
            var qemus = await Task.Run(() => Native.Processes("qemu-system%"));
            var mem = RamProblem(os, ram, qemus);
            if (mem.block != null) throw new InvalidOperationException(mem.block);
            if (mem.warn != null && !ignoreRamWarning) throw new RamWarning(mem.warn);

            var run = new GuestRun { Os = os, RamMiB = ram, Smp = smp, Disk = disk, QuickBoot = quick, Ours = true, Shape = shape, QuickAtStart = quickAtStart, Resumed = resumes != null };
            var env = new Dictionary<string, string> { ["ASOFT_SHARP"] = c.Sharp ? "1" : "0" };
            var log = Path.Combine(AppPaths.LocalData, "logs", os + "-start.log");
            var r = new Runner(script, StartArgs(os, ram, smp, loadState, shape), log);
            run.Script = r;
            var got = new TaskCompletionSource<bool>();
            r.Line += l =>
            {
                var m = StartedLine.Match(l);
                if (m.Success) { run.QemuPid = int.Parse(m.Groups[2].Value); run.RunFolder = m.Groups[3].Value.Trim(); got.TrySetResult(true); }
                // (Start-visionOS.ps1 / Start-watchOS.ps1: a state that did not load, after which the guest boots)
                else if (l.Contains("could not be resumed")) run.Resumed = false;
            };
            r.Exited += code =>
            {
                if (os == "ios16" || run.QemuPid == 0) got.TrySetResult(code == 0 && os != "ios16");
                if (code != 0 && run.QemuPid == 0) got.TrySetException(new InvalidOperationException(StartFailure(r, code)));
            };
            lock (Runs) Runs[os] = run;
            Changed?.Invoke(os);
            r.Start(env, Guests.App(os));
            if (os == "ios16")
            {
                // run-windows.ps1 stays with QEMU (through qemu-sweet.py): QEMU is a child of what it started
                for (int i = 0; i < 120 && run.QemuPid == 0 && r.Running; i++)
                {
                    await Task.Delay(1000);
                    var q = await Task.Run(() => Native.Tree(r.Pid).Skip(1).Select(id => Native.Processes("qemu-system%").FirstOrDefault(p => p.Pid == id)).FirstOrDefault(p => p != null));
                    if (q != null) run.QemuPid = q.Pid;
                }
                if (run.QemuPid == 0)
                {
                    lock (Runs) Runs.Remove(os);
                    Changed?.Invoke(os);
                    throw new InvalidOperationException(StartFailure(r, r.ExitCode ?? -1));
                }
                run.RunFolder = Guests.LastRunFolder(os);
            }
            else
            {
                var done = await Task.WhenAny(got.Task, Task.Delay(180000));
                if (done != got.Task || run.QemuPid == 0)
                {
                    lock (Runs) Runs.Remove(os);
                    Changed?.Invoke(os);
                    if (got.Task.IsFaulted) throw got.Task.Exception.InnerException;
                    throw new InvalidOperationException(StartFailure(r, r.ExitCode ?? -1));
                }
            }
            // quick boot as the script set it (Start-watchOS.ps1 turns it off with too little room for a save): without it
            // closing the window does not save
            var qp = await Task.Run(() => Native.Processes("qemu-system%").FirstOrDefault(x => x.Pid == run.QemuPid));
            if (qp != null && qp.CommandLine != "") run.QuickBoot = quick && qp.CommandLine.Contains("quick-boot=on");
            if (resumes != null && disk != "") LauncherConfig.Current.SetSave(disk, resumes, ram, smp, shape);
            Log.Write($"{os}: started pid {run.QemuPid} ({smp} vCPUs, {ram} MiB, disk {(disk == "" ? "throwaway" : disk)}{(resumes != null ? ", resumes " + resumes : "")})");
            Changed?.Invoke(os);
            Watch(run);
            return run;
        }

        static string StartFailure(Runner r, int code)
        {
            var tail = r.Lines.Where(l => l.Trim() != "").Reverse().Take(6).Reverse();
            return L.T($"The start script ended ({code}): ", $"Başlatma betiği bitti ({code}): ") + string.Join(" | ", tail);
        }

        public class RamWarning : Exception { public RamWarning(string m) : base(m) { } }

        /// <summary>A note for a settings change that a save depends on (Guests.Shape): the next start boots afresh with it,
        /// and the quick save stays as the way back with what it was made with. null when the change does not touch it.</summary>
        public static string ShapeChangeNote(string os, Guests.Snap quick, string shapeBefore)
        {
            if (quick == null || Guests.SaveDisk(os) == "") return null;
            var meta = LauncherConfig.Current.FindSave(Guests.SaveDisk(os), Guests.QuickName);
            // only a change that makes it no longer fit (one back to its settings, or a second change, says nothing)
            if (Guests.Fits(os, meta, Guests.Shape(os)) || !Guests.Fits(os, meta, shapeBefore)) return null;
            var hw = Guests.Hardware(os, Guests.SaveShape(os, meta));
            return L.T($"This applies from the next start, a cold boot. Your save of {Guests.When(quick.When, true)} stays as a way back; it opens with {hw}.",
                       $"Bu bir sonraki açılıştan, soğuk başlatmadan geçerli olur. {Guests.When(quick.When, true)} kaydınız geri dönüş noktası olarak kalır; {hw} ile açılır.");
        }

        /// <summary>Waits for the guest's QEMU to end, then notes what it left (a quick save).</summary>
        static void Watch(GuestRun run)
        {
            Task.Run(async () =>
            {
                bool saves = run.Disk != "" && Guests.HasQuickSave(run.Os);
                // (a guest found running: the quick save it has now is not one made since the launcher looked)
                if (!run.Ours && saves) run.QuickAtStart = Guests.Snapshots(run.Os, run.Disk).FirstOrDefault(s => s.Quick)?.Key ?? "";
                while (Native.Alive(run.QemuPid)) await Task.Delay(1500);
                // iOS 16's script ends with it (its ipa server too)
                if (run.Script != null && run.Script.Running) run.Script.Wait(15000);
                if (saves)
                {
                    // a quick save made in this run (Save and close, the watch's automatic save): what it was made with
                    var quick = Guests.Snapshots(run.Os, run.Disk).FirstOrDefault(s => s.Quick);
                    if (quick != null && quick.Key != run.QuickAtStart) LauncherConfig.Current.SetSave(run.Disk, Guests.QuickName, run.RamMiB, run.Smp, run.Ours ? run.Shape : "");
                }
                lock (Runs) { if (Runs.TryGetValue(run.Os, out var r) && r == run) Runs.Remove(run.Os); }
                Log.Write($"{run.Os}: QEMU pid {run.QemuPid} ended");
                Changed?.Invoke(run.Os);
            });
        }

        /// <summary>A guest that runs without the launcher having started it (an older window, the .cmd): adopted to show
        /// it and to save or turn it off through QMP; never stopped by process id.</summary>
        public static void Adopt(string os, Native.Proc q)
        {
            lock (Runs)
            {
                if (Runs.TryGetValue(os, out var r) && r.QemuPid == q.Pid) return;
                var c = Guests.Cfg(os);
                var cmd = q.CommandLine;
                // (the research VM takes its RAM from the device tree: one made for another size is named dtree...-<MiB>m;
                // a save noted with the wrong size would be resumed into a machine it does not fit)
                var sized = Regex.Match(cmd, @"dtree[^""\\/]*-(\d+)m""?(\s|$)");
                var run = new GuestRun
                {
                    Os = os, QemuPid = q.Pid, Ours = false,
                    Smp = int.TryParse(Regex.Match(cmd, @"-smp\s+(\d+)").Groups[1].Value, out var n) ? n : c.Smp,
                    RamMiB = sized.Success ? int.Parse(sized.Groups[1].Value) : Guests.DefaultRam(os),
                    QuickBoot = cmd.Contains("quick-boot=on"),
                    Disk = Guests.SaveDisk(os),
                };
                // visionOS: the disk it was started on (sound or silent), not the one the settings would take now
                if (os == "vision") run.Disk = Guests.VisionDisk(cmd);
                if (cmd.Contains("-snapshot")) run.Disk = "";
                Runs[os] = run;
                Watch(run);
            }
            Changed?.Invoke(os);
        }

        // --- save and close, turn off --------------------------------------------------------------
        /// <summary>Saves the guest as its quick save and closes it, as the window's close button does with quick boot.</summary>
        public static async Task SaveAndClose(string os)
        {
            if (!Runs.TryGetValue(os, out var run) || !Guests.HasQuickSave(os)) return;
            if (run.Disk == "" || !run.QuickBoot) throw new InvalidOperationException(L.T("This start keeps nothing (throwaway disk or quick boot off): turn it off instead.", "Bu açılış hiçbir şey saklamıyor (atılan disk ya da hızlı açılış kapalı): onun yerine kapatın."));
            // (QEMU deletes the quick save it replaces first: the new one reuses its room)
            var old = (await Task.Run(() => Guests.Snapshots(os, run.Disk))).FirstOrDefault(s => s.Quick);
            long drive = Native.FreeBytes(run.Disk), back = old?.Bytes ?? 0;
            double need = run.RamMiB * 1048576.0 + 1e9;    // the state at most its RAM, and room to spare
            if (drive + back < need)
                throw new InvalidOperationException(L.T($"A save of {Guests.Name(os)} needs about {L.Size(need)} of room. {Path.GetPathRoot(run.Disk)} has {L.Size(drive)} free" + (back > 0 ? $", and the save it replaces gives back {L.Size(back)}" : "") + ". Free some space first.",
                                                        $"{Guests.Name(os)} kaydı yaklaşık {L.Size(need)} yer ister. {Path.GetPathRoot(run.Disk)} üzerinde {L.Size(drive)} boş" + (back > 0 ? $", yerine geçtiği kayıt da {L.Size(back)} geri verir" : "") + ". Önce yer açın."));
            run.Busy = "saving";
            Changed?.Invoke(os);
            bool asked = await Task.Run(() => Native.CloseWindow(run.QemuPid, null));
            if (!asked)
            {
                // no window (display none): the same through QMP
                await Task.Run(() =>
                {
                    Qmp.Run(Guests.QmpPort(os), Qmp.Cmd("stop"));
                    var said = Qmp.HmpRun(Guests.QmpPort(os), "savevm asoft-quick");
                    if (said != "") throw new IOException(said);
                    try { Qmp.Run(Guests.QmpPort(os), 5000, Qmp.Cmd("quit")); } catch { }
                });
            }
            await WaitEnd(run, 600);
        }

        /// <summary>Turns the guest off: iOS 16 powers down (its power key); iOS 26, watchOS and visionOS sync their disk on
        /// the root shell (their serial console), then QEMU quits.</summary>
        public static async Task TurnOff(string os)
        {
            if (!Runs.TryGetValue(os, out var run)) return;
            run.Busy = "stopping";
            Changed?.Invoke(os);
            await Task.Run(() =>
            {
                try
                {
                    if (os == "ios16") Qmp.Run(Guests.QmpPort(os), Qmp.Cmd("system_powerdown"));
                    else
                    {
                        if (run.Disk != "" && !Qmp.SerialSync(Guests.SerialPort(os), 45000))
                            Log.Write(os + ": the root shell did not answer sync; quitting anyway");
                        Qmp.Run(Guests.QmpPort(os), 5000, Qmp.Cmd("quit"));
                    }
                }
                catch (Exception e) { Log.Write(os + ": turn off: " + e.Message); }
            });
            bool ended = await WaitEnd(run, os == "ios16" ? 90 : 60);
            if (!ended && os == "ios16")
            {
                try { Qmp.Run(Guests.QmpPort(os), 5000, Qmp.Cmd("quit")); } catch { }
                ended = await WaitEnd(run, 30);
            }
            // the next start boots afresh: a quick save made while it ran (the watch's automatic one) is the way back now,
            // as the one it resumed is (the start scripts mark that)
            if (ended && run.Disk != "" && Guests.HasQuickSave(os)) await Task.Run(() => Guests.MarkWayBack(os, run.Disk));
        }

        /// <summary>Ends a guest the launcher started, by its process ids (what QEMU had not written is lost).</summary>
        public static void ForceStop(string os)
        {
            if (!Runs.TryGetValue(os, out var run)) return;
            if (!run.Ours) { try { Qmp.Run(Guests.QmpPort(os), 3000, Qmp.Cmd("quit")); } catch { } return; }
            if (run.Script != null && run.Script.Running) run.Script.Kill();
            Native.KillTree(run.QemuPid);
        }

        static async Task<bool> WaitEnd(GuestRun run, int seconds)
        {
            for (int i = 0; i < seconds * 2; i++)
            {
                if (!Native.Alive(run.QemuPid)) { run.Busy = ""; return true; }
                await Task.Delay(500);
            }
            run.Busy = "";
            Changed?.Invoke(run.Os);
            return false;
        }

        // --- saves while it runs -------------------------------------------------------------------
        public static async Task<string> SaveNow(string os)
        {
            if (!Runs.TryGetValue(os, out var run) || run.Disk == "") throw new InvalidOperationException(L.T("Saves need a disk that keeps its changes.", "Kayıt için değişiklikleri saklayan bir disk gerekir."));
            var free = Native.FreeBytes(run.Disk);
            if (free < run.RamMiB * 1048576L + 1_000_000_000L)
                throw new InvalidOperationException(L.T($"Only {L.Size(free)} is free on {Path.GetPathRoot(run.Disk)}.", $"{Path.GetPathRoot(run.Disk)} üzerinde yalnız {L.Size(free)} boş."));
            var name = "state-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
            run.Busy = "saving";
            Changed?.Invoke(os);
            try
            {
                var said = await Task.Run(() => Qmp.HmpRun(Guests.QmpPort(os), "savevm " + name));
                if (said != "") throw new IOException(said);
                LauncherConfig.Current.SetSave(run.Disk, name, run.RamMiB, run.Smp, run.Ours ? run.Shape : "");
                return name;
            }
            finally { run.Busy = ""; Changed?.Invoke(os); }
        }

        public static async Task LoadRunning(string os, string name)
        {
            var run = Runs[os];
            var g = SaveGuest(os, run.Disk, name);
            var meta = LauncherConfig.Current.FindSave(run.Disk, name);
            bool fits = run.Shape != "" ? Guests.Fits(os, meta, run.Shape) : !g.known || g.smp == run.Smp && (os == "ios16" || g.ram == run.RamMiB);
            if (!fits)
                throw new InvalidOperationException(L.T($"This save opens with {Guests.Hardware(os, Guests.SaveShape(os, meta))}; the running guest has other settings. Turn it off, then load the save: it starts with its own.",
                                                        $"Bu kayıt {Guests.Hardware(os, Guests.SaveShape(os, meta))} ile açılır; çalışan konuğun ayarları başka. Kapatıp sonra kaydı yükleyin: kendi ayarlarıyla açılır."));
            run.Busy = "loading";
            Changed?.Invoke(os);
            try
            {
                var said = await Task.Run(() => Qmp.HmpRun(Guests.QmpPort(os), "loadvm " + name));
                if (said != "") throw new IOException(said);
            }
            finally { run.Busy = ""; Changed?.Invoke(os); }
        }

        public static async Task DeleteSave(string os, string disk, string name)
        {
            if (Runs.TryGetValue(os, out var run) && run.Disk == disk && Native.Alive(run.QemuPid))
            {
                var said = await Task.Run(() => Qmp.HmpRun(Guests.QmpPort(os), "delvm " + name));
                if (said != "") throw new IOException(said);
            }
            else
            {
                var r = await Task.Run(() => Guests.DeleteSnapshot(os, disk, name));
                if (r.Item1 != 0) throw new IOException(r.Item2.Trim());
            }
            if (name == Guests.QuickName) try { File.Delete(Guests.QuickUsedFile(disk)); } catch { }
            LauncherConfig.Current.DropSave(disk, name);
        }
    }
}
