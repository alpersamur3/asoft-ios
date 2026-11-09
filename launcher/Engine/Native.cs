using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;

namespace ASoftware.Engine
{
    public static class Native
    {
        // --- memory ----------------------------------------------------------------------------
        [StructLayout(LayoutKind.Sequential)]
        struct MEMORYSTATUSEX
        {
            public uint dwLength, dwMemoryLoad;
            public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
        }
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);

        /// <summary>Total and free physical memory, and the commit charge's room (bytes).</summary>
        public static (ulong total, ulong free, ulong commitFree, ulong commitLimit) Memory()
        {
            var m = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)) };
            GlobalMemoryStatusEx(ref m);
            return (m.ullTotalPhys, m.ullAvailPhys, m.ullAvailPageFile, m.ullTotalPageFile);
        }

        // --- listening TCP ports and their processes --------------------------------------------
        [DllImport("iphlpapi.dll", SetLastError = true)]
        static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int af, int tableClass, uint reserved);

        /// <summary>Port -> PID of every IPv4 TCP listener.</summary>
        public static Dictionary<int, int> Listeners()
        {
            var r = new Dictionary<int, int>();
            int size = 0;
            const int TCP_TABLE_OWNER_PID_LISTENER = 3;
            GetExtendedTcpTable(IntPtr.Zero, ref size, false, 2, TCP_TABLE_OWNER_PID_LISTENER, 0);
            var buf = Marshal.AllocHGlobal(size);
            try
            {
                if (GetExtendedTcpTable(buf, ref size, false, 2, TCP_TABLE_OWNER_PID_LISTENER, 0) != 0) return r;
                int n = Marshal.ReadInt32(buf);
                for (int i = 0; i < n; i++)
                {
                    var row = buf + 4 + i * 24;   // state, localAddr, localPort, remoteAddr, remotePort, pid
                    int port = (Marshal.ReadByte(row + 8) << 8) | Marshal.ReadByte(row + 9);
                    int pid = Marshal.ReadInt32(row + 20);
                    r[port] = pid;
                }
            }
            finally { Marshal.FreeHGlobal(buf); }
            return r;
        }

        // --- processes ---------------------------------------------------------------------------
        public class Proc { public int Pid, Parent; public string Name = "", CommandLine = ""; public ulong WorkingSet; }

        /// <summary>Processes whose image name is like the pattern (WQL LIKE), with their command lines.</summary>
        public static List<Proc> Processes(string like)
        {
            var r = new List<Proc>();
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT ProcessId, ParentProcessId, Name, CommandLine, WorkingSetSize FROM Win32_Process WHERE Name LIKE '" + like + "'"))
                using (var c = s.Get())
                    foreach (ManagementObject o in c)
                        using (o)
                            r.Add(new Proc
                            {
                                Pid = Convert.ToInt32(o["ProcessId"]),
                                Parent = Convert.ToInt32(o["ParentProcessId"]),
                                Name = Convert.ToString(o["Name"]),
                                CommandLine = Convert.ToString(o["CommandLine"]) ?? "",
                                WorkingSet = Convert.ToUInt64(o["WorkingSetSize"] ?? 0UL)
                            });
            }
            catch (Exception e) { Log.Write("wmi: " + e.Message); }
            return r;
        }

        /// <summary>The process and all it started (by parent id; the ids a process started, not names).</summary>
        public static List<int> Tree(int root)
        {
            var all = Processes("%");
            var r = new List<int> { root };
            for (int i = 0; i < r.Count; i++)
                foreach (var p in all) if (p.Parent == r[i] && !r.Contains(p.Pid) && p.Pid != 0) r.Add(p.Pid);
            return r;
        }

        /// <summary>Stops the process tree the launcher started, children first.</summary>
        public static void KillTree(int root)
        {
            var ids = Tree(root);
            ids.Reverse();
            foreach (var id in ids)
            {
                try { using (var p = Process.GetProcessById(id)) { p.Kill(); Log.Write($"killed pid {id} ({p.ProcessName})"); } } catch { }
            }
        }

        public static bool Alive(int pid)
        {
            try { using (var p = Process.GetProcessById(pid)) return !p.HasExited; } catch { return false; }
        }

        // --- windows -------------------------------------------------------------------------------
        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);

        /// <summary>The visible top-level windows of a process, with their titles.</summary>
        public static List<(IntPtr hwnd, string title)> Windows(int pid)
        {
            var r = new List<(IntPtr, string)>();
            EnumWindows((h, l) =>
            {
                GetWindowThreadProcessId(h, out uint p);
                if (p == pid && IsWindowVisible(h) && GetWindow(h, 4 /* GW_OWNER */) == IntPtr.Zero)
                {
                    var sb = new StringBuilder(256);
                    GetWindowText(h, sb, 256);
                    r.Add((h, sb.ToString()));
                }
                return true;
            }, IntPtr.Zero);
            return r;
        }

        /// <summary>Asks the QEMU window to close, as its close button does (quick boot: it saves, then quits).</summary>
        public static bool CloseWindow(int pid, string titleHas)
        {
            var w = Windows(pid).Where(x => titleHas == null || x.title.IndexOf(titleHas, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            if (w.Count == 0) w = Windows(pid);
            if (w.Count == 0) return false;
            PostMessage(w[0].hwnd, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero);
            return true;
        }

        public static void Raise(int pid)
        {
            var w = Windows(pid);
            if (w.Count == 0) return;
            if (IsIconic(w[0].hwnd)) ShowWindow(w[0].hwnd, 9 /* SW_RESTORE */);
            SetForegroundWindow(w[0].hwnd);
        }

        // --- dark title bar ------------------------------------------------------------------------
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public static void DarkTitleBar(IntPtr hwnd, bool dark)
        {
            int v = dark ? 1 : 0;
            if (DwmSetWindowAttribute(hwnd, 20, ref v, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref v, 4);
        }

        /// <summary>Windows 11 rounds the window's corners and gives it the Mica backdrop under the title bar.</summary>
        public static void Win11Look(IntPtr hwnd)
        {
            int round = 2; // DWMWCP_ROUND
            DwmSetWindowAttribute(hwnd, 33, ref round, 4);
        }

        // --- free space ----------------------------------------------------------------------------
        public static long FreeBytes(string path)
        {
            try { return new System.IO.DriveInfo(System.IO.Path.GetPathRoot(System.IO.Path.GetFullPath(path))).AvailableFreeSpace; }
            catch { return 0; }
        }
    }
}
