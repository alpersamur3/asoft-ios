// What iOS 26's GPU path needs of a Vulkan driver on Windows, tried in about a second. gpu-check.ps1
// compiles this with Add-Type, so it needs nothing that is not on every Windows.
//
// The guest's RAM reaches the GPU as host memory (VK_EXT_external_memory_host's HOST_ALLOCATION,
// reims-vgpu-vulkan/src/os/windows.rs), and it is a view of a pagefile section mapped over a
// placeholder (os/windows/vm.rs). So on the device the library would pick (metal2vulkan-runtime's
// device/create.rs: discrete first, then enumeration order; the others are tried and printed too):
// a Vulkan 1.2 device with the extension, whose driver imports private pages and such a view, binds
// a buffer to them, and whose GPU writes reach them. Prints lines, and returns 0 when that device
// passes, 1 when it does not, 3 when there is no Vulkan or no device.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GpuCheck
{
    const string V = "vulkan-1.dll";
    [DllImport(V)] static extern int vkCreateInstance(IntPtr info, IntPtr alloc, out IntPtr instance);
    [DllImport(V)] static extern void vkDestroyInstance(IntPtr instance, IntPtr alloc);
    [DllImport(V)] static extern int vkEnumerateInstanceVersion(out uint version);
    [DllImport(V)] static extern int vkEnumeratePhysicalDevices(IntPtr instance, ref uint count, IntPtr[] devices);
    [DllImport(V)] static extern void vkGetPhysicalDeviceProperties2(IntPtr pd, IntPtr props);
    [DllImport(V)] static extern void vkGetPhysicalDeviceFeatures2(IntPtr pd, IntPtr features);
    [DllImport(V)] static extern void vkGetPhysicalDeviceQueueFamilyProperties(IntPtr pd, ref uint count, IntPtr props);
    [DllImport(V)] static extern void vkGetPhysicalDeviceExternalBufferProperties(IntPtr pd, IntPtr info, IntPtr props);
    [DllImport(V)] static extern int vkEnumerateDeviceExtensionProperties(IntPtr pd, IntPtr layer, ref uint count, IntPtr props);
    [DllImport(V)] static extern int vkCreateDevice(IntPtr pd, IntPtr info, IntPtr alloc, out IntPtr device);
    [DllImport(V)] static extern void vkDestroyDevice(IntPtr device, IntPtr alloc);
    [DllImport(V)] static extern IntPtr vkGetDeviceProcAddr(IntPtr device, [MarshalAs(UnmanagedType.LPStr)] string name);
    [DllImport(V)] static extern void vkGetDeviceQueue(IntPtr device, uint family, uint index, out IntPtr queue);
    [DllImport(V)] static extern int vkCreateBuffer(IntPtr device, IntPtr info, IntPtr alloc, out ulong buffer);
    [DllImport(V)] static extern void vkDestroyBuffer(IntPtr device, ulong buffer, IntPtr alloc);
    [DllImport(V)] static extern void vkGetBufferMemoryRequirements(IntPtr device, ulong buffer, IntPtr reqs);
    [DllImport(V)] static extern int vkAllocateMemory(IntPtr device, IntPtr info, IntPtr alloc, out ulong memory);
    [DllImport(V)] static extern void vkFreeMemory(IntPtr device, ulong memory, IntPtr alloc);
    [DllImport(V)] static extern int vkBindBufferMemory(IntPtr device, ulong buffer, ulong memory, ulong offset);
    [DllImport(V)] static extern int vkCreateCommandPool(IntPtr device, IntPtr info, IntPtr alloc, out ulong pool);
    [DllImport(V)] static extern void vkDestroyCommandPool(IntPtr device, ulong pool, IntPtr alloc);
    [DllImport(V)] static extern int vkAllocateCommandBuffers(IntPtr device, IntPtr info, out IntPtr cmd);
    [DllImport(V)] static extern int vkBeginCommandBuffer(IntPtr cmd, IntPtr info);
    [DllImport(V)] static extern int vkEndCommandBuffer(IntPtr cmd);
    [DllImport(V)] static extern void vkCmdFillBuffer(IntPtr cmd, ulong buffer, ulong offset, ulong size, uint data);
    [DllImport(V)] static extern int vkQueueSubmit(IntPtr queue, uint count, IntPtr submits, ulong fence);
    [DllImport(V)] static extern int vkQueueWaitIdle(IntPtr queue);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int HostPointerProps(IntPtr device, uint handleType, IntPtr pointer, IntPtr props);

    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAlloc(IntPtr at, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr CreateFileMappingW(IntPtr file, IntPtr sa, uint protect, uint high, uint low, string name);
    [DllImport("kernelbase.dll", SetLastError = true)] static extern IntPtr VirtualAlloc2(IntPtr process, IntPtr at, UIntPtr size, uint type, uint protect, IntPtr ext, uint count);
    [DllImport("kernelbase.dll", SetLastError = true)] static extern IntPtr MapViewOfFile3(IntPtr section, IntPtr process, IntPtr at, ulong offset, UIntPtr size, uint type, uint protect, IntPtr ext, uint count);

    const uint Host = 0x80;     // VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT
    const string Ext = "VK_EXT_external_memory_host";
    const int Size = 16 << 20;
    const int Page = 16 << 10;  // the guest's page

    static IntPtr New(int bytes)
    {
        IntPtr p = Marshal.AllocHGlobal(bytes);
        for (int i = 0; i < bytes; i++) Marshal.WriteByte(p, i, 0);
        return p;
    }
    static IntPtr Struct(int bytes, int type, IntPtr next)
    {
        IntPtr p = New(bytes);
        Marshal.WriteInt32(p, 0, type);
        Marshal.WriteIntPtr(p, 8, next);
        return p;
    }
    static IntPtr Text(string s)
    {
        return Marshal.StringToHGlobalAnsi(s);
    }

    class Device
    {
        public IntPtr Physical;
        public string Name;
        public string Kind;
        public int Rank;
        public uint Api;
        public uint Vendor;
        public uint Driver;
    }

    static Device Describe(IntPtr pd, out ulong alignment)
    {
        IntPtr host = Struct(24, 1000178002, IntPtr.Zero);
        IntPtr props = Struct(1040, 1000059001, host);
        vkGetPhysicalDeviceProperties2(pd, props);
        alignment = (ulong)Marshal.ReadInt64(host, 16);
        int type = Marshal.ReadInt32(props, 16 + 16);
        string kind; int rank;
        switch (type)
        {
            case 2: kind = "discrete"; rank = 0; break;
            case 1: kind = "integrated"; rank = 1; break;
            case 3: kind = "virtual"; rank = 2; break;
            case 4: kind = "cpu"; rank = 3; break;
            default: kind = "other"; rank = 4; break;
        }
        return new Device
        {
            Physical = pd,
            Name = Marshal.PtrToStringAnsi(new IntPtr(props.ToInt64() + 16 + 20)),
            Kind = kind,
            Rank = rank,
            Api = (uint)Marshal.ReadInt32(props, 16 + 0),
            Driver = (uint)Marshal.ReadInt32(props, 16 + 4),
            Vendor = (uint)Marshal.ReadInt32(props, 16 + 8),
        };
    }

    static bool HasExtension(IntPtr pd)
    {
        uint count = 0;
        if (vkEnumerateDeviceExtensionProperties(pd, IntPtr.Zero, ref count, IntPtr.Zero) != 0) return false;
        IntPtr list = New((int)count * 260);
        if (vkEnumerateDeviceExtensionProperties(pd, IntPtr.Zero, ref count, list) != 0) return false;
        for (int i = 0; i < count; i++)
            if (Marshal.PtrToStringAnsi(new IntPtr(list.ToInt64() + i * 260)) == Ext) return true;
        return false;
    }

    // the first family that does graphics and compute work, or -1
    static int Family(IntPtr pd)
    {
        uint count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(pd, ref count, IntPtr.Zero);
        IntPtr list = New((int)count * 24);
        vkGetPhysicalDeviceQueueFamilyProperties(pd, ref count, list);
        for (int i = 0; i < count; i++)
            if ((Marshal.ReadInt32(list, i * 24) & 3) == 3) return i;
        return -1;
    }

    static IntPtr PrivatePages()
    {
        return VirtualAlloc(IntPtr.Zero, (UIntPtr)Size, 0x3000, 4);     // reserve + commit, read and write
    }

    // a view of a fresh pagefile section over a placeholder, as the library's views of the guest's RAM
    static IntPtr SectionView()
    {
        IntPtr me = new IntPtr(-1);
        IntPtr section = CreateFileMappingW(new IntPtr(-1), IntPtr.Zero, 4 | 0x8000000, 0, (uint)Size, null);
        if (section == IntPtr.Zero) return IntPtr.Zero;
        IntPtr hole = VirtualAlloc2(me, IntPtr.Zero, (UIntPtr)Size, 0x2000 | 0x40000, 1, IntPtr.Zero, 0);
        if (hole == IntPtr.Zero) return IntPtr.Zero;
        return MapViewOfFile3(section, me, hole, 0, (UIntPtr)Size, 0x4000, 4, IntPtr.Zero, 0);
    }

    // Import `bytes` at `at`, bind a buffer to them, fill it from the GPU and read it back here.
    // Returns null, or what failed.
    static string Import(IntPtr device, IntPtr queue, uint family, HostPointerProps props, bool address, IntPtr at, int bytes)
    {
        if (at == IntPtr.Zero) return "could not map the memory (error " + Marshal.GetLastWin32Error() + ")";
        IntPtr hp = Struct(24, 1000178001, IntPtr.Zero);
        int r = props(device, Host, at, hp);
        if (r != 0) return "vkGetMemoryHostPointerPropertiesEXT refused it (" + r + ")";
        uint bits = (uint)Marshal.ReadInt32(hp, 16);
        if (bits == 0) return "vkGetMemoryHostPointerPropertiesEXT gave no memory type";

        IntPtr external = Struct(24, 1000072000, IntPtr.Zero);
        Marshal.WriteInt32(external, 16, (int)Host);
        IntPtr bi = Struct(56, 12, external);
        Marshal.WriteInt64(bi, 24, bytes);
        Marshal.WriteInt32(bi, 32, Usage(address));
        ulong buffer;
        r = vkCreateBuffer(device, bi, IntPtr.Zero, out buffer);
        if (r != 0) return "vkCreateBuffer refused it (" + r + ")";
        IntPtr reqs = New(24);
        vkGetBufferMemoryRequirements(device, buffer, reqs);
        bits &= (uint)Marshal.ReadInt32(reqs, 16);
        if (bits == 0) return "no memory type both the pointer and a buffer take";

        ulong memory = 0;
        r = -1;
        for (int type = 0; type < 32 && r != 0; type++)
        {
            if ((bits & (1u << type)) == 0) continue;
            IntPtr flags = Struct(24, 1000060000, IntPtr.Zero);
            Marshal.WriteInt32(flags, 16, 2);   // device address
            IntPtr import = Struct(32, 1000178000, address ? flags : IntPtr.Zero);
            Marshal.WriteInt32(import, 16, (int)Host);
            Marshal.WriteIntPtr(import, 24, at);
            IntPtr ai = Struct(32, 5, import);
            Marshal.WriteInt64(ai, 16, bytes);
            Marshal.WriteInt32(ai, 24, type);
            r = vkAllocateMemory(device, ai, IntPtr.Zero, out memory);
        }
        if (r != 0) return "vkAllocateMemory refused the import (" + r + ")";
        r = vkBindBufferMemory(device, buffer, memory, 0);
        if (r != 0) return "vkBindBufferMemory refused it (" + r + ")";

        IntPtr pi = Struct(24, 39, IntPtr.Zero);
        Marshal.WriteInt32(pi, 20, (int)family);
        ulong pool;
        r = vkCreateCommandPool(device, pi, IntPtr.Zero, out pool);
        if (r != 0) return "vkCreateCommandPool: " + r;
        IntPtr ca = Struct(32, 40, IntPtr.Zero);
        Marshal.WriteInt64(ca, 16, (long)pool);
        Marshal.WriteInt32(ca, 28, 1);
        IntPtr cmd;
        r = vkAllocateCommandBuffers(device, ca, out cmd);
        if (r != 0) return "vkAllocateCommandBuffers: " + r;
        IntPtr begin = Struct(32, 42, IntPtr.Zero);
        Marshal.WriteInt32(begin, 16, 1);
        vkBeginCommandBuffer(cmd, begin);
        const uint Pattern = 0xA55A0FF0;
        vkCmdFillBuffer(cmd, buffer, 0, (ulong)bytes, Pattern);
        vkEndCommandBuffer(cmd);
        IntPtr cmds = New(8);
        Marshal.WriteIntPtr(cmds, 0, cmd);
        IntPtr si = Struct(72, 4, IntPtr.Zero);
        Marshal.WriteInt32(si, 40, 1);
        Marshal.WriteIntPtr(si, 48, cmds);
        r = vkQueueSubmit(queue, 1, si, 0);
        if (r != 0) return "vkQueueSubmit: " + r;
        r = vkQueueWaitIdle(queue);
        if (r != 0) return "the GPU did not finish (" + r + ")";
        string failed = null;
        foreach (int offset in new[] { 0, bytes / 2, bytes - 4 })
            if ((uint)Marshal.ReadInt32(at, offset) != Pattern) failed = "the GPU's write did not reach the memory at " + offset;
        vkDestroyCommandPool(device, pool, IntPtr.Zero);
        vkDestroyBuffer(device, buffer, IntPtr.Zero);
        vkFreeMemory(device, memory, IntPtr.Zero);
        return failed;
    }

    static int Usage(bool address)
    {
        // transfer, texel, uniform, storage, index, vertex, indirect
        return 0x1FF | (address ? 0x20000 : 0);
    }

    // Returns null, or why the device cannot do it
    static string Try(Device d, ulong alignment)
    {
        IntPtr pd = d.Physical;
        if (d.Api < (1u << 22 | 2u << 12)) return "its driver has Vulkan " + Version(d.Api) + ", and 1.2 is needed";
        if (!HasExtension(pd)) return "its driver has no " + Ext;
        if (alignment > Page) return "its driver wants host memory aligned to " + alignment + " bytes, and the guest's pages are " + Page;

        IntPtr info = Struct(32, 1000071002, IntPtr.Zero);
        Marshal.WriteInt32(info, 20, Usage(false));
        Marshal.WriteInt32(info, 24, (int)Host);
        IntPtr ext = Struct(32, 1000071003, IntPtr.Zero);
        vkGetPhysicalDeviceExternalBufferProperties(pd, info, ext);
        int features = Marshal.ReadInt32(ext, 16);
        if ((features & 4) == 0 || (features & 1) != 0) return "its driver cannot bind a buffer to imported host memory";

        IntPtr bda = Struct(32, 1000257000, IntPtr.Zero);
        IntPtr f2 = Struct(240, 1000059000, bda);
        vkGetPhysicalDeviceFeatures2(pd, f2);
        bool address = Marshal.ReadInt32(bda, 16) != 0;
        int family = Family(pd);
        if (family < 0) return "it has no graphics and compute queue";

        IntPtr priority = New(4);
        Marshal.Copy(BitConverter.GetBytes(1f), 0, priority, 4);
        IntPtr qi = Struct(40, 2, IntPtr.Zero);
        Marshal.WriteInt32(qi, 20, family);
        Marshal.WriteInt32(qi, 24, 1);
        Marshal.WriteIntPtr(qi, 32, priority);
        IntPtr names = New(8);
        Marshal.WriteIntPtr(names, 0, Text(Ext));
        IntPtr enabled = Struct(32, 1000257000, IntPtr.Zero);
        Marshal.WriteInt32(enabled, 16, address ? 1 : 0);
        IntPtr di = Struct(72, 3, enabled);
        Marshal.WriteInt32(di, 20, 1);
        Marshal.WriteIntPtr(di, 24, qi);
        Marshal.WriteInt32(di, 48, 1);
        Marshal.WriteIntPtr(di, 56, names);
        IntPtr device;
        int r = vkCreateDevice(pd, di, IntPtr.Zero, out device);
        if (r != 0) return "vkCreateDevice with " + Ext + " failed (" + r + ")";
        try
        {
            IntPtr queue;
            vkGetDeviceQueue(device, (uint)family, 0, out queue);
            IntPtr fn = vkGetDeviceProcAddr(device, "vkGetMemoryHostPointerPropertiesEXT");
            if (fn == IntPtr.Zero) return "its driver does not have vkGetMemoryHostPointerPropertiesEXT";
            HostPointerProps props = (HostPointerProps)Marshal.GetDelegateForFunctionPointer(fn, typeof(HostPointerProps));
            IntPtr view = SectionView();
            string failed = Import(device, queue, (uint)family, props, address, PrivatePages(), Size);
            if (failed != null) return "private pages: " + failed;
            failed = Import(device, queue, (uint)family, props, address, view, Size);
            if (failed != null) return "a section's view: " + failed;
            // a run of guest pages inside a view, not at its start
            failed = Import(device, queue, (uint)family, props, address, new IntPtr(view.ToInt64() + Page), Page * 8);
            if (failed != null) return "guest pages inside a section's view: " + failed;
            return null;
        }
        finally
        {
            vkDestroyDevice(device, IntPtr.Zero);
        }
    }

    static string Version(uint v)
    {
        return (v >> 22 & 0x7F) + "." + (v >> 12 & 0x3FF) + "." + (v & 0xFFF);
    }

    static string Vendor(uint id)
    {
        switch (id)
        {
            case 0x10DE: return "NVIDIA";
            case 0x1002: return "AMD";
            case 0x8086: return "Intel";
            default: return "0x" + id.ToString("x");
        }
    }

    public static int Run()
    {
        uint api;
        IntPtr instance = IntPtr.Zero;
        try
        {
            if (vkEnumerateInstanceVersion(out api) != 0) api = 1u << 22;
            if (api < (1u << 22 | 2u << 12))
            {
                Console.WriteLine("result|none|the Vulkan loader is " + Version(api) + ", and 1.2 is needed");
                return 3;
            }
            IntPtr app = Struct(48, 0, IntPtr.Zero);
            Marshal.WriteInt32(app, 44, (int)(1u << 22 | 2u << 12));
            IntPtr ii = Struct(64, 1, IntPtr.Zero);
            Marshal.WriteIntPtr(ii, 24, app);
            int r = vkCreateInstance(ii, IntPtr.Zero, out instance);
            if (r != 0)
            {
                Console.WriteLine("result|none|vkCreateInstance failed (" + r + "): update your GPU's driver");
                return 3;
            }
        }
        catch (DllNotFoundException)
        {
            Console.WriteLine("result|none|no Vulkan loader (vulkan-1.dll): install your GPU vendor's driver");
            return 3;
        }

        uint count = 0;
        vkEnumeratePhysicalDevices(instance, ref count, null);
        if (count == 0)
        {
            Console.WriteLine("result|none|Vulkan sees no GPU: install your GPU vendor's driver");
            return 3;
        }
        IntPtr[] handles = new IntPtr[count];
        vkEnumeratePhysicalDevices(instance, ref count, handles);

        // the library's order: by kind, then as enumerated (a stable sort)
        List<Device> devices = new List<Device>();
        List<ulong> alignments = new List<ulong>();
        for (int rank = 0; rank <= 4; rank++)
            foreach (IntPtr pd in handles)
            {
                ulong alignment;
                Device d = Describe(pd, out alignment);
                if (d.Rank != rank) continue;
                devices.Add(d);
                alignments.Add(alignment);
            }

        int code = 0;
        for (int i = 0; i < devices.Count; i++)
        {
            Device d = devices[i];
            string why = Try(d, alignments[i]);
            // gpu|used or other|name|kind|vendor|Vulkan|driver version|host memory alignment|ok or why
            Console.WriteLine("gpu|" + (i == 0 ? "used" : "other") + "|" + d.Name + "|" + d.Kind + "|" + Vendor(d.Vendor) + "|" + Version(d.Api) + "|0x" +
                              d.Driver.ToString("x") + "|" + alignments[i] + "|" + (why ?? "ok"));
            if (i == 0 && why != null) code = 1;
        }
        vkDestroyInstance(instance, IntPtr.Zero);
        Console.WriteLine("result|" + (code == 0 ? "ok" : "fail"));
        return code;
    }
}
