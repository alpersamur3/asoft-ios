using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

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

        public static Button Btn(string text, Action click, string style = "Btn", string icon = null)
        {
            object content = text;
            if (icon != null)
            {
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                var ic = Icon(icon, 13, null); ic.Margin = new Thickness(0, 1, 8, 0);
                ic.SetResourceReference(TextBlock.ForegroundProperty, style == "BtnPrimary" ? "AccentText" : style == "BtnDanger" ? "Bad" : "Text");
                sp.Children.Add(ic);
                sp.Children.Add(new TextBlock { Text = text });
                content = sp;
            }
            var b = new Button { Content = content, Style = S(style) };
            b.Click += (s, e) => click();
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
            var box = new Border { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(14), Child = inner };
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
            foreach (var i in items) if (i != null) { if (i is FrameworkElement fe && sp.Children.Count > 0) fe.Margin = new Thickness(8, 0, 0, 0); sp.Children.Add(i); }
            return sp;
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
}
