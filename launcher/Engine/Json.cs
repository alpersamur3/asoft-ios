using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace ASoftware.Engine
{
    /// <summary>JSON through the framework's JavaScriptSerializer, written indented (the config is read by people too).</summary>
    public static class Json
    {
        static JavaScriptSerializer Ser() => new JavaScriptSerializer { MaxJsonLength = 64 << 20, RecursionLimit = 64 };

        public static Dictionary<string, object> ReadObject(string file)
        {
            try
            {
                if (!File.Exists(file)) return null;
                var text = File.ReadAllText(file, Encoding.UTF8).TrimStart('﻿');
                return Ser().DeserializeObject(text) as Dictionary<string, object>;
            }
            catch (Exception e) { Log.Write("json: cannot read " + file + ": " + e.Message); return null; }
        }

        public static object Parse(string text) => Ser().DeserializeObject(text);

        public static T Read<T>(string file) where T : class
        {
            try
            {
                if (!File.Exists(file)) return null;
                var text = File.ReadAllText(file, Encoding.UTF8).TrimStart('﻿');
                return Ser().Deserialize<T>(text);
            }
            catch (Exception e) { Log.Write("json: cannot read " + file + ": " + e.Message); return null; }
        }

        /// <summary>Written to a temporary file and moved over: an interrupted write never leaves half a file.</summary>
        public static void Write(string file, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            var compact = Ser().Serialize(value);
            var tmp = file + ".tmp";
            File.WriteAllText(tmp, Indent(compact), new UTF8Encoding(false));
            if (File.Exists(file)) File.Replace(tmp, file, null);
            else File.Move(tmp, file);
        }

        public static string Str(Dictionary<string, object> o, string key)
        {
            if (o == null || !o.TryGetValue(key, out var v) || v == null) return "";
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        public static bool? Bool(Dictionary<string, object> o, string key)
        {
            if (o == null || !o.TryGetValue(key, out var v) || v == null) return null;
            if (v is bool b) return b;
            return null;
        }

        public static int? Int(Dictionary<string, object> o, string key)
        {
            if (o == null || !o.TryGetValue(key, out var v) || v == null) return null;
            try { return Convert.ToInt32(v, CultureInfo.InvariantCulture); } catch { return null; }
        }

        static string Indent(string json)
        {
            var sb = new StringBuilder();
            int depth = 0;
            bool str = false, esc = false;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (str)
                {
                    sb.Append(c);
                    if (esc) esc = false;
                    else if (c == '\\') esc = true;
                    else if (c == '"') str = false;
                    continue;
                }
                switch (c)
                {
                    case '"': str = true; sb.Append(c); break;
                    case '{':
                    case '[':
                        // empty ones on one line
                        if (i + 1 < json.Length && (json[i + 1] == '}' || json[i + 1] == ']')) { sb.Append(c).Append(json[i + 1]); i++; break; }
                        sb.Append(c); depth++; sb.Append("\r\n").Append(' ', depth * 2); break;
                    case '}':
                    case ']':
                        depth--; sb.Append("\r\n").Append(' ', depth * 2).Append(c); break;
                    case ',': sb.Append(c).Append("\r\n").Append(' ', depth * 2); break;
                    case ':': sb.Append(": "); break;
                    default: sb.Append(c); break;
                }
            }
            return sb.ToString();
        }
    }

    public static class Log
    {
        static readonly object gate = new object();
        // next to launcher.json: a test run on its own config (-config) keeps its lines out of the user's log
        public static string File => Path.Combine(Path.GetDirectoryName(Path.GetFullPath(AppPaths.ConfigFile)), "launcher.log");

        public static void Write(string line)
        {
            try
            {
                lock (gate)
                {
                    Directory.CreateDirectory(AppPaths.LocalData);
                    var f = File;
                    var fi = new FileInfo(f);
                    if (fi.Exists && fi.Length > 4 << 20)
                    {
                        var old = f + ".old";
                        if (System.IO.File.Exists(old)) System.IO.File.Delete(old);
                        System.IO.File.Move(f, old);
                    }
                    System.IO.File.AppendAllText(f, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ", CultureInfo.InvariantCulture) + line + "\r\n", Encoding.UTF8);
                }
            }
            catch { }
        }
    }
}
