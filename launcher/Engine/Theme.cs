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
            // (the three text levels each keep 4.5:1 or more on a surface and on the page, Text3 too: it carries 12 px text)
            if (Dark)
            {
                B("Bg", "#000000");
                r["Surface"] = Vertical("#19191C", "#111113");
                B("Surface2", "#1C1C1F"); B("Surface3", "#2A2A2E");
                B("Line", "#26262A"); B("LineStrong", "#3A3A3F");
                B("Text", "#F5F5F7"); B("Text2", "#A1A1A6"); B("Text3", "#86868B");
                B("Hover", "#12FFFFFF"); B("Pressed", "#20FFFFFF");
                B("Accent", "#6CB2FF");
                B("Good", "#32D74B"); B("Warn", "#FF9F0A"); B("Bad", "#FF5A50"); B("Info", "#6CB2FF");
                B("Idle", "#48484A");
                B("Track", "#2A2A2E"); B("SwitchOff", "#39393D"); B("SegOn", "#3A3A3F");
                // the main button: a light capsule
                B("Fill", "#F5F5F7"); B("FillHover", "#D9D9DE"); B("FillPressed", "#C2C2C8"); B("FillText", "#0B0B0D");
                r["DeviceShadow"] = null;
                r["DeviceFaint"] = 0.32;
                r["DeviceLater"] = 0.55;
            }
            else
            {
                B("Bg", "#F5F5F7");
                B("Surface", "#FFFFFF"); B("Surface2", "#F2F2F4"); B("Surface3", "#E8E8EC");
                B("Line", "#E2E2E7"); B("LineStrong", "#C7C7CC");
                B("Text", "#1D1D1F"); B("Text2", "#48484C"); B("Text3", "#6E6E73");
                B("Hover", "#0A000000"); B("Pressed", "#16000000");
                B("Accent", "#0A6CDE");
                B("Good", "#1FA83C"); B("Warn", "#B86E00"); B("Bad", "#D70015"); B("Info", "#0A6CDE");
                B("Idle", "#C7C7CC");
                B("Track", "#E5E5EA"); B("SwitchOff", "#E5E5EA"); B("SegOn", "#FFFFFF");
                B("Fill", "#1D1D1F"); B("FillHover", "#3A3A3C"); B("FillPressed", "#505053"); B("FillText", "#FFFFFF");
                // the devices are objects: the same metal in both themes, standing on the light page with a shadow
                var s = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, Opacity = 0.16, BlurRadius = 22, ShadowDepth = 7, Direction = 270 };
                s.Freeze();
                r["DeviceShadow"] = s;
                r["DeviceFaint"] = 0.17;
                r["DeviceLater"] = 0.9;     // on a light page half of a dark glass is a grey blob
            }
            foreach (Window w in Application.Current.Windows) TitleBar(w);
            Changed?.Invoke();
        }

        /// <summary>The title bar in the page's own colour (Windows 11), else dark or light (Windows 10).</summary>
        public static void TitleBar(Window w)
        {
            try
            {
                var h = new System.Windows.Interop.WindowInteropHelper(w).Handle;
                if (h != IntPtr.Zero)
                {
                    Native.DarkTitleBar(h, Dark);
                    Native.CaptionColor(h, Dark ? Color("#000000") : Color("#F5F5F7"));
                    Native.Win11Look(h);
                }
            }
            catch { }
        }

        /// <summary>A surface: a little lighter at its top.</summary>
        static LinearGradientBrush Vertical(string top, string bottom)
        {
            var g = new LinearGradientBrush(Color(top), Color(bottom), new Point(0, 0), new Point(0, 1));
            g.Freeze();
            return g;
        }

        public static Color Color(string hex) => (Color)ColorConverter.ConvertFromString(hex);

        public static SolidColorBrush Brush(string hex)
        {
            var b = new SolidColorBrush(Color(hex));
            b.Freeze();
            return b;
        }
    }
}
