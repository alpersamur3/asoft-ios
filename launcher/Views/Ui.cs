using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ASoftware.Views
{
    /// <summary>Small builders for the pages made in code: rows, segmented choices, switches, buttons.</summary>
    public static class Ui
    {
        static object R(string k) => Application.Current.Resources[k];
        public static Style S(string k) => (Style)R(k);
        public static Brush B(string k) => (Brush)R(k);
        public static FontFamily F(string k) => (FontFamily)R(k);

        public static TextBlock Text(string t, string style = "Sub", double top = 0)
        {
            var tb = new TextBlock { Text = t, Style = S(style), Margin = new Thickness(0, top, 0, 0) };
            tb.TextWrapping = TextWrapping.Wrap;
            return tb;
        }

        /// <summary>A brush that follows the theme (dark / light).</summary>
        public static T Dyn<T>(T e, DependencyProperty p, string key) where T : FrameworkElement { e.SetResourceReference(p, key); return e; }

        public static TextBlock Icon(string glyph, double size = 16, string brush = "Text2")
        {
            var t = new TextBlock { Text = glyph, FontFamily = F("Icons"), FontSize = size, VerticalAlignment = VerticalAlignment.Center };
            if (brush != null) t.SetResourceReference(TextBlock.ForegroundProperty, brush);
            return t;
        }

        /// <summary>A button. Capsules and links carry only their text; the quiet text button (Back) keeps its icon.</summary>
        public static Button Btn(string text, Action click, string style = "Btn", string icon = null)
        {
            object content = text;
            if (!string.IsNullOrEmpty(icon) && style == "BtnGhost")
            {
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                // (the icon takes the button's own colour: it is inherited)
                var ic = Icon(icon, 12, null); ic.Margin = new Thickness(0, 1, 8, 0);
                sp.Children.Add(ic);
                sp.Children.Add(new TextBlock { Text = text });
                content = sp;
            }
            var b = new Button { Content = content, Style = S(style) };
            b.Click += (s, e) => click();
            return b;
        }

        /// <summary>A state's dot: its tone (Good, Warn, Bad, Accent, Idle) is the only colour it has.</summary>
        public static Ellipse Dot(string tone, double size = 7)
        {
            var e = new Ellipse { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
            e.SetResourceReference(Shape.FillProperty, tone);
            return e;
        }

        /// <summary>A state: a dot and its text.</summary>
        public static StackPanel State(string text, string tone, double size = 13)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var d = Dot(tone); d.Margin = new Thickness(0, 1, 8, 0);
            sp.Children.Add(d);
            var t = new TextBlock { Text = text, FontSize = size, VerticalAlignment = VerticalAlignment.Center };
            t.SetResourceReference(TextBlock.ForegroundProperty, "Text2");
            sp.Children.Add(t);
            return sp;
        }

        /// <summary>A note on a page: a hairline surface, a tone dot and the text.</summary>
        public static Border Note(string tone, string text)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            var d = Dot(tone); d.VerticalAlignment = VerticalAlignment.Top; d.Margin = new Thickness(0, 6, 12, 0);
            g.Children.Add(d);
            var t = Text(text, "Sub"); Grid.SetColumn(t, 1);
            g.Children.Add(t);
            var b = new Border { CornerRadius = new CornerRadius(14), Padding = new Thickness(16, 11, 16, 12), Margin = new Thickness(0, 0, 0, 16), BorderThickness = new Thickness(1), Child = g };
            b.SetResourceReference(Border.BackgroundProperty, "Surface");
            b.SetResourceReference(Border.BorderBrushProperty, "Line");
            return b;
        }

        /// <summary>A setting: title and description on the left, its control on the right (below on narrow pages).</summary>
        public static Border Row(string title, string desc, UIElement control)
        {
            if (title == null)
                return Dyn(new Border { Child = control, Padding = new Thickness(18, 12, 18, 12), BorderThickness = new Thickness(0, 0, 0, 1) }, Border.BorderBrushProperty, "Line");
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 200 });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var left = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 24, 0) };
            left.Children.Add(new TextBlock { Text = title, Style = S("H3") });
            if (!string.IsNullOrEmpty(desc)) left.Children.Add(Text(desc, "Faint", 3));
            g.Children.Add(left);
            if (control is FrameworkElement fe) { fe.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(fe, 1); g.Children.Add(fe); }
            return Dyn(new Border { Child = g, Padding = new Thickness(18, 14, 18, 14), BorderThickness = new Thickness(0, 0, 0, 1) }, Border.BorderBrushProperty, "Line");
        }

        /// <summary>A group of rows in a rounded panel, with a heading above it.</summary>
        public static StackPanel Group(string heading, params UIElement[] rows)
        {
            var outer = new StackPanel { Margin = new Thickness(0, 0, 0, 22) };
            if (heading != null) outer.Children.Add(Dyn(new TextBlock { Text = heading, Style = S("H3"), FontSize = 12.5, Margin = new Thickness(4, 0, 0, 8) }, TextBlock.ForegroundProperty, "Text2"));
            var inner = new StackPanel();
            foreach (var r in rows) if (r != null) inner.Children.Add(r);
            if (inner.Children.Count > 0 && inner.Children[inner.Children.Count - 1] is Border last) last.BorderThickness = new Thickness(0);
            var box = new Border { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16), Child = inner };
            box.SetResourceReference(Border.BackgroundProperty, "Surface");
            box.SetResourceReference(Border.BorderBrushProperty, "Line");
            outer.Children.Add(box);
            return outer;
        }

        static int seg;
        /// <summary>Segmented choice: (value, label) pairs.</summary>
        public static Border Seg<T>(IEnumerable<(T value, string label)> options, T current, Action<T> changed, bool enabled = true)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            var group = "seg" + (++seg);
            foreach (var o in options)
            {
                var v = o.value;
                var rb = new RadioButton { Content = o.label, Style = S("Seg"), GroupName = group, IsChecked = Equals(v, current), IsEnabled = enabled };
                rb.Checked += (s, e) => changed(v);
                sp.Children.Add(rb);
            }
            return new Border { Style = S("SegBox"), Child = sp };
        }

        public static CheckBox Switch(bool on, Action<bool> changed, string label = null, bool enabled = true)
        {
            var c = new CheckBox { Style = S("Switch"), IsChecked = on, Content = label, IsEnabled = enabled };
            c.Checked += (s, e) => changed(true);
            c.Unchecked += (s, e) => changed(false);
            return c;
        }

        public static TextBox Field(string text, double width = 260)
        {
            return new TextBox { Text = text, Style = S("Field"), Width = width };
        }

        public static StackPanel Hstack(params UIElement[] items)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var i in items)
                if (i != null)
                {
                    // (a text link stands further off: two links 8 px apart read as one)
                    bool link = i is Button b && (b.Style == S("BtnLink") || b.Style == S("BtnDanger"));
                    if (i is FrameworkElement fe && sp.Children.Count > 0) fe.Margin = new Thickness(link ? 18 : 8, 0, 0, 0);
                    sp.Children.Add(i);
                }
            return sp;
        }

        // a number and its unit, an OS's name and its number, and a range's two ends
        static readonly System.Text.RegularExpressions.Regex UnitGap = new System.Text.RegularExpressions.Regex(@"(\d) (GB|MB|KB|TB|min|dk|sa|h|vCPU|%)(?!\p{L})|(iOS|watchOS|visionOS) (\d)");
        static readonly System.Text.RegularExpressions.Regex RangeDash = new System.Text.RegularExpressions.Regex(@"(\d)–(\d)");

        /// <summary>The text with no-break spaces where a line must not break: "5 GB", "40 dk", "iOS 26", "1,5–2,5".</summary>
        public static string KeepUnits(string s)
        {
            if (string.IsNullOrEmpty(s)) return s ?? "";
            s = UnitGap.Replace(s, m => m.Groups[1].Success ? m.Groups[1].Value + "\u00a0" + m.Groups[2].Value : m.Groups[3].Value + "\u00a0" + m.Groups[4].Value);
            return RangeDash.Replace(s, "$1\u2060–\u2060$2");
        }

        public static string Pick(string description, string start)
        {
            using (var d = new System.Windows.Forms.FolderBrowserDialog { Description = description, ShowNewFolderButton = true })
            {
                if (!string.IsNullOrEmpty(start) && System.IO.Directory.Exists(start)) d.SelectedPath = start;
                return d.ShowDialog() == System.Windows.Forms.DialogResult.OK ? d.SelectedPath : null;
            }
        }
    }

    /// <summary>A width that follows another element's, up to a most: one column of cards, all as wide as it.</summary>
    public sealed class AtMost : IValueConverter
    {
        readonly double most;
        public AtMost(double most) { this.most = most; }
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            value is double w && w > 0 && !double.IsInfinity(w) ? Math.Min(most, w) : double.NaN;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();

        /// <summary>@e as wide as @column's width, up to @max.</summary>
        public static void Bind(FrameworkElement e, FrameworkElement column, double max) =>
            e.SetBinding(FrameworkElement.WidthProperty, new Binding(nameof(FrameworkElement.ActualWidth)) { Source = column, Converter = new AtMost(max) });
    }

    /// <summary>Half an element's height as its corner radius (capsules, round focus rings), at whatever size it gets.</summary>
    public sealed class CapsuleRadius : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            new CornerRadius(value is double h && h > 0 && !double.IsInfinity(h) ? h / 2 : 0);

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
    }
}
