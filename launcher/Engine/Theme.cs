using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace ASoftware.Engine
{
    /// <summary>Dark and light, following Windows (Settings > Personalization > Colors, "app mode") unless chosen.
    /// The brushes are application resources the XAML takes as DynamicResource, so a switch repaints at once.</summary>
    public static class Theme
    {
        public static bool Dark { get; private set; } = true;
        public static event Action Changed;
        static string choice = "auto";

        public static void Init(string c)
        {
            choice = c;
            SystemEvents.UserPreferenceChanged += (s, e) =>
            {
                if (e.Category == UserPreferenceCategory.General || e.Category == UserPreferenceCategory.Color || e.Category == UserPreferenceCategory.VisualStyle)
                    Application.Current?.Dispatcher.BeginInvoke(new Action(Apply));
            };
            Apply();
        }

        public static void Set(string c) { choice = c; Apply(); }

        public static bool WindowsDark()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                    return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch { return false; }
        }

        static void Apply()
        {
            Dark = choice == "dark" || (choice != "light" && WindowsDark());
            var r = Application.Current.Resources;
            void B(string key, string hex) => r[key] = Brush(hex);
            if (Dark)
            {
                B("Bg", "#0E1014"); B("BgGlow", "#151A2A");
                B("Surface", "#171A21"); B("Surface2", "#1F232C"); B("Surface3", "#272C37");
                B("Line", "#2A2F3A"); B("LineStrong", "#3A4150");
                B("Text", "#F3F5F9"); B("Text2", "#A8AFBD"); B("Text3", "#6E7685");
                B("Hover", "#14FFFFFF"); B("Pressed", "#22FFFFFF");
                B("Accent", "#5B8CFF"); B("AccentHover", "#729CFF"); B("AccentPressed", "#4A78E8"); B("AccentText", "#FFFFFF");
                B("AccentSoft", "#1F2A4A");
                B("Good", "#3DD68C"); B("GoodSoft", "#173A2A");
                B("Warn", "#F7B547"); B("WarnSoft", "#3D3018");
                B("Bad", "#FF6B6B"); B("BadSoft", "#40201F");
                B("Info", "#5AC8FA"); B("InfoSoft", "#16313D");
                B("Track", "#2A2F3A");
                r["ShadowColor"] = Color("#000000");
                r["ShadowOpacity"] = 0.45;
            }
            else
            {
                B("Bg", "#F2F4F8"); B("BgGlow", "#E6ECFA");
                B("Surface", "#FFFFFF"); B("Surface2", "#F2F4F7"); B("Surface3", "#E8EBF0");
                B("Line", "#E1E5EC"); B("LineStrong", "#CBD1DB");
                B("Text", "#15171C"); B("Text2", "#5A6170"); B("Text3", "#8C93A1");
                B("Hover", "#0F000000"); B("Pressed", "#1A000000");
                B("Accent", "#3368F0"); B("AccentHover", "#4A7BFA"); B("AccentPressed", "#2756D6"); B("AccentText", "#FFFFFF");
                B("AccentSoft", "#E3EBFF");
                B("Good", "#17A864"); B("GoodSoft", "#DDF5E9");
                B("Warn", "#C98400"); B("WarnSoft", "#FFF1D6");
                B("Bad", "#D93B3B"); B("BadSoft", "#FCE3E3");
                B("Info", "#0A84C9"); B("InfoSoft", "#DDF0FA");
                B("Track", "#E1E5EC");
                r["ShadowColor"] = Color("#1A2240");
                r["ShadowOpacity"] = 0.12;
            }
            foreach (Window w in Application.Current.Windows) TitleBar(w);
            Changed?.Invoke();
        }

        public static void TitleBar(Window w)
        {
            try
            {
                var h = new System.Windows.Interop.WindowInteropHelper(w).Handle;
                if (h != IntPtr.Zero) { Native.DarkTitleBar(h, Dark); Native.Win11Look(h); }
            }
            catch { }
        }

        public static Color Color(string hex) => (Color)ColorConverter.ConvertFromString(hex);

        public static SolidColorBrush Brush(string hex)
        {
            var b = new SolidColorBrush(Color(hex));
            b.Freeze();
            return b;
        }

        /// <summary>Each OS's card colours: the gradient of its header.</summary>
        public static LinearGradientBrush OsGradient(string os)
        {
            string[] c;
            switch (os)
            {
                case "ios16": c = new[] { "#19B3C4", "#1667A0", "#1D2C6B" }; break;
                case "ios26": c = new[] { "#62A4FF", "#4A5DF0", "#6236D6" }; break;
                case "watch": c = new[] { "#FF9F45", "#F2546B", "#B4307A" }; break;
                default: c = new[] { "#9AA6BC", "#5D6884", "#343B52" }; break;
            }
            var g = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
            g.GradientStops.Add(new GradientStop(Color(c[0]), 0));
            g.GradientStops.Add(new GradientStop(Color(c[1]), 0.55));
            g.GradientStops.Add(new GradientStop(Color(c[2]), 1));
            g.Freeze();
            return g;
        }
    }
}
