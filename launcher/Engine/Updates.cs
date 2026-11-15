using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Text;
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

        public const int Normal = 0, Important = 1, Critical = 2;
        const int MaxText = 300;

        /// <summary>The newest release above this launcher: its page, the text its notes carry for the app (or null) and the highest level among every release not installed yet.</summary>
        public class Release { public string Tag, Name, Url, Published, Text; public int Level; }

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

        /// <summary>
        /// The list, not /releases/latest: the level is the highest among every release this launcher has not got, so
        /// someone two releases behind still sees a critical one in between. Drafts and prereleases are skipped.
        /// ASOFT_UPDATE_JSON (a file holding the API's answer) stands in for GitHub, for the UI tests.
        /// </summary>
        public static async Task<Release> Latest()
        {
            string text;
            var test = Environment.GetEnvironmentVariable("ASOFT_UPDATE_JSON");
            if (!string.IsNullOrEmpty(test)) text = System.IO.File.ReadAllText(test, Encoding.UTF8);
            else
                using (var h = new HttpClient { Timeout = TimeSpan.FromSeconds(15), MaxResponseContentBufferSize = 1 << 20 })
                {
                    h.DefaultRequestHeaders.UserAgent.ParseAdd("ASoftware-launcher/" + AppVersion);
                    h.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
                    text = await h.GetStringAsync("https://api.github.com/repos/" + Repo + "/releases?per_page=10");
                }
            return Pick(Json.Parse(text) as System.Collections.IEnumerable, AppVersion);
        }

        /// <summary>The newest release above @version out of GitHub's list, or null.</summary>
        public static Release Pick(System.Collections.IEnumerable list, string version)
        {
            if (list == null) return null;
            Dictionary<string, object> best = null;
            string body = "";
            int older = Normal;
            foreach (var item in list)
            {
                var r = item as Dictionary<string, object>;
                if (r == null || IsTrue(r, "draft") || IsTrue(r, "prerelease")) continue;
                var tag = Json.Str(r, "tag_name");
                if (string.IsNullOrEmpty(tag) || !IsNewer(tag, version)) continue;
                var b = Json.Str(r, "body") ?? "";
                // newest first as GitHub lists them, but go by the version number in case one was edited later
                if (best == null || IsNewer(tag, Json.Str(best, "tag_name")))
                {
                    if (best != null) older = Math.Max(older, LevelOf(Block(body)));
                    best = r; body = b;
                }
                else older = Math.Max(older, LevelOf(Block(b)));
            }
            if (best == null) return null;
            var block = Block(body);
            return new Release
            {
                Tag = Json.Str(best, "tag_name"), Name = Json.Str(best, "name"), Url = Json.Str(best, "html_url"), Published = Json.Str(best, "published_at"),
                Text = NoticeText(block) ?? Headline(body), Level = Math.Max(older, LevelOf(block))
            };
        }

        static bool IsTrue(Dictionary<string, object> o, string key) => o.ContainsKey(key) && o[key] is bool b && b;

        static readonly Regex BlockStart = new Regex(@"<!--\s*app-notice\b");

        /// <summary>
        /// The lines inside the first app-notice comment of a release body (GitHub's page does not show it), the block
        /// the Android app reads too: "&lt;!-- app-notice", then "level: critical" and "text: ..." lines, then "--&gt;".
        /// CRLF is made \n first; a comment never closed runs to the end, as it does on GitHub's page.
        /// </summary>
        public static string[] Block(string body)
        {
            if (body == null) return new string[0];
            var s = body.Replace("\r\n", "\n").Replace('\r', '\n');
            var m = BlockStart.Match(s);
            if (!m.Success) return new string[0];
            int from = m.Index + m.Length;
            int end = s.IndexOf("-->", from, StringComparison.Ordinal);
            return s.Substring(from, (end < 0 ? s.Length : end) - from).Split('\n');
        }

        static string Field(string line, string key)
        {
            var l = line.Trim();
            int colon = l.IndexOf(':');
            if (colon < 0 || !string.Equals(l.Substring(0, colon).Trim(), key, StringComparison.OrdinalIgnoreCase)) return null;
            return l.Substring(colon + 1).Trim();
        }

        /// <summary>The block's level; a missing or unknown one (a typo, a level added later) is normal.</summary>
        public static int LevelOf(string[] block)
        {
            foreach (var line in block)
            {
                var v = Field(line, "level");
                if (v == null) continue;
                switch (v.ToLowerInvariant())
                {
                    case "critical": return Critical;
                    case "important": return Important;
                    default: return Normal;
                }
            }
            return Normal;
        }

        /// <summary>The block's text: its text: lines one under the other, control characters dropped, cut at ~300 characters; null if none.</summary>
        public static string NoticeText(string[] block)
        {
            var sb = new StringBuilder();
            foreach (var line in block)
            {
                var v = Field(line, "text");
                if (string.IsNullOrEmpty(v)) continue;
                if (sb.Length > 0) sb.Append('\n');
                foreach (var ch in v) sb.Append(char.IsControl(ch) ? ' ' : ch);
            }
            return Cut(sb.ToString().Trim());
        }

        /// <summary>A release without a notice still says what changed: the first line of its notes as plain text.</summary>
        static string Headline(string body)
        {
            if (body == null) return null;
            var s = Regex.Replace(body.Replace("\r\n", "\n").Replace('\r', '\n'), @"<!--.*?(-->|$)", "", RegexOptions.Singleline);
            foreach (var raw in s.Split('\n'))
            {
                var l = Regex.Replace(raw.Trim(), @"^[#>\-\*\s]+", "").Replace("**", "").Replace("`", "");
                if (l.Length > 0) return Cut(l);
            }
            return null;
        }

        static string Cut(string s)
        {
            if (string.IsNullOrEmpty(s)) return null;
            if (s.Length <= MaxText) return s;
            int cut = MaxText - 1;
            // never split a surrogate pair (an emoji) in two
            if (char.IsHighSurrogate(s[cut - 1])) cut--;
            return s.Substring(0, cut).Trim() + "…";
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
