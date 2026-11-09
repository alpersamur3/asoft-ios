using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace ASoftware.Engine
{
    /// <summary>The newest release of alpersamur3/asoft-ios on GitHub (read only: the public API, no sign-in).</summary>
    public static class Updates
    {
        public const string Repo = "alpersamur3/asoft-ios";

        public static string AppVersion
        {
            get
            {
                var a = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
                int plus = a.IndexOf('+');
                return plus > 0 ? a.Substring(0, plus) : a;
            }
        }

        public static bool DevBuild => AppVersion.StartsWith("0.0.0");

        public class Release { public string Tag, Name, Url, Published; }

        /// <summary>GitHub's record of a repository's newest release.</summary>
        public static async Task<Dictionary<string, object>> LatestOf(string repo)
        {
            using (var h = new HttpClient { Timeout = TimeSpan.FromSeconds(15) })
            {
                h.DefaultRequestHeaders.UserAgent.ParseAdd("ASoftware-launcher/" + AppVersion);
                h.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
                var text = await h.GetStringAsync("https://api.github.com/repos/" + repo + "/releases/latest");
                return Json.Parse(text) as Dictionary<string, object>;
            }
        }

        public static async Task<Release> Latest()
        {
            var o = await LatestOf(Repo);
            if (o == null) return null;
            return new Release { Tag = Json.Str(o, "tag_name"), Name = Json.Str(o, "name"), Url = Json.Str(o, "html_url"), Published = Json.Str(o, "published_at") };
        }

        static Version Parse(string tag)
        {
            var m = Regex.Match(tag ?? "", @"(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?");
            if (!m.Success) return new Version(0, 0);
            return new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), m.Groups[3].Success ? int.Parse(m.Groups[3].Value) : 0, m.Groups[4].Success ? int.Parse(m.Groups[4].Value) : 0);
        }

        public static bool Newer(string tag) => Parse(tag) > Parse(AppVersion);
        public static bool IsNewer(string tag, string than) => Parse(tag) > Parse(than);
    }
}
