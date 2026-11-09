using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace ASoftware.Engine
{
    /// <summary>
    /// An Apple device tree's guest RAM: /chosen dram-size, the size in /memory reg and /product/util's base right
    /// after DRAM (QEMU's vresearch takes the RAM size from the tree). The start scripts write a tree with another
    /// size (ios26\scripts\dt-ram.ps1); this reads one, and checks the layout the scripts rely on.
    /// </summary>
    public static class Adt
    {
        /// <summary>The tree's RAM in MiB, or 0 when it has no such layout.</summary>
        public static int RamMiB(string file)
        {
            try
            {
                var b = File.ReadAllBytes(file);
                var at = new long[] { -1, -1, -1 };
                int end = Walk(b, 0, "", at);
                if (end != b.Length || at[0] < 0 || at[1] < 0 || at[2] < 0) return 0;
                long size = BitConverter.ToInt64(b, (int)at[0]);
                long base_ = BitConverter.ToInt64(b, (int)at[1]);
                long memSize = BitConverter.ToInt64(b, (int)at[1] + 8);
                long util = BitConverter.ToInt64(b, (int)at[2]);
                if (memSize != size || util != base_ + size) return 0;
                return (int)(size >> 20);
            }
            catch { return 0; }
        }

        static int Walk(byte[] b, int o, string path, long[] r)
        {
            int np = BitConverter.ToInt32(b, o), nc = BitConverter.ToInt32(b, o + 4);
            o += 8;
            string name = "?";
            var props = new Dictionary<string, int>();
            for (int i = 0; i < np; i++)
            {
                int z = 0;
                while (z < 32 && b[o + z] != 0) z++;
                string pn = Encoding.ASCII.GetString(b, o, z);
                int ln = BitConverter.ToInt32(b, o + 32) & 0x7fffffff;
                props[pn] = o + 36;
                if (pn == "name")
                {
                    int k = 0;
                    while (k < ln && b[o + 36 + k] != 0) k++;
                    name = Encoding.ASCII.GetString(b, o + 36, k);
                }
                o += 36 + ((ln + 3) & ~3);
            }
            string here = path.Length == 0 ? name : path + "/" + name;
            if (name == "chosen" && props.TryGetValue("dram-size", out var d)) r[0] = d;
            else if (name == "memory" && props.TryGetValue("reg", out var m)) r[1] = m;
            else if (here.EndsWith("/product/util") && props.TryGetValue("reg", out var u)) r[2] = u;
            for (int i = 0; i < nc; i++) o = Walk(b, o, here, r);
            return o;
        }
    }
}
