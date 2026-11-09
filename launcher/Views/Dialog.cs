using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>The launcher's own message box and question (rounded, in the theme), built in code.</summary>
    public static class Dialog
    {
        /// <summary>Shows a message with buttons; returns the index of the one pressed (-1: closed). The first is the default.</summary>
        public static int Show(Window owner, string title, string text, params string[] buttons) => Build(owner, title, text, null, buttons).Item1;

        /// <summary>A question with a text field; null when cancelled.</summary>
        public static string Ask(Window owner, string title, string text, string value)
        {
            var r = Build(owner, title, text, value ?? "", new[] { L.K("OK"), L.K("Cancel") });
            return r.Item1 == 0 ? r.Item2 : null;
        }

        static Tuple<int, string> Build(Window owner, string title, string text, string field, string[] buttons)
        {
            owner = owner ?? Application.Current?.MainWindow;
            if (owner != null && !owner.IsVisible) owner = null;
            int pressed = -1;
            var w = new Window
            {
                WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
                ResizeMode = ResizeMode.NoResize, SizeToContent = SizeToContent.WidthAndHeight, ShowInTaskbar = owner == null,
                WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
                Owner = owner, Title = title, FontFamily = (FontFamily)Application.Current.Resources["UiFont"]
            };
            var card = new Border
            {
                Background = (Brush)Application.Current.Resources["Surface"], BorderBrush = (Brush)Application.Current.Resources["LineStrong"],
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16), Padding = new Thickness(24, 22, 24, 20), Margin = new Thickness(24),
                MinWidth = 380, MaxWidth = 560,
                Effect = new DropShadowEffect { BlurRadius = 30, ShadowDepth = 6, Direction = 270, Opacity = 0.35, Color = Colors.Black }
            };
            var stack = new StackPanel();
            stack.Children.Add(new TextBlock { Text = title, Style = (Style)Application.Current.Resources["H2"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) });
            if (!string.IsNullOrEmpty(text))
                stack.Children.Add(new TextBlock { Text = text, Style = (Style)Application.Current.Resources["Sub"], FontSize = 13.5, LineHeight = 20, Margin = new Thickness(0, 0, 0, 16) });
            TextBox box = null;
            if (field != null)
            {
                box = new TextBox { Text = field, Style = (Style)Application.Current.Resources["Field"], Margin = new Thickness(0, 0, 0, 16) };
                stack.Children.Add(box);
            }
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            for (int i = 0; i < buttons.Length; i++)
            {
                int n = i;
                var b = new Button
                {
                    Content = buttons[i], Margin = new Thickness(8, 0, 0, 0), MinWidth = 92,
                    Style = (Style)Application.Current.Resources[i == 0 ? "BtnPrimary" : "Btn"], IsDefault = i == 0, IsCancel = i == buttons.Length - 1 && buttons.Length > 1
                };
                System.Windows.Automation.AutomationProperties.SetAutomationId(b, "dialog-" + n);
                b.Click += (s, e) => { pressed = n; w.Close(); };
                row.Children.Add(b);
            }
            stack.Children.Add(row);
            card.Child = stack;
            card.MouseLeftButtonDown += (s, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { w.DragMove(); } catch { } };
            w.Content = card;
            w.KeyDown += (s, e) => { if (e.Key == Key.Escape) w.Close(); };
            w.Loaded += (s, e) => { if (box != null) { box.Focus(); box.SelectAll(); } };
            w.ShowDialog();
            return Tuple.Create(pressed, box?.Text);
        }
    }
}
