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
            var w = Make(owner, title, text, field, buttons, n => pressed = n, out var box);
            w.ShowDialog();
            return Tuple.Create(pressed, box?.Text);
        }

        /// <summary>The dialog's window, not shown yet (the screenshots draw one with -page dialog).</summary>
        public static Window Make(Window owner, string title, string text, string field, string[] buttons, Action<int> pressed, out TextBox box)
        {
            var w = new Window
            {
                WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
                ResizeMode = ResizeMode.NoResize, SizeToContent = SizeToContent.WidthAndHeight, ShowInTaskbar = owner == null,
                WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
                Owner = owner, Title = title, FontFamily = (FontFamily)Application.Current.Resources["UiFont"]
            };
            // a hairline surface in the theme, its title, its text, the main answer as the light capsule on the right
            var card = new Border
            {
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(20), Padding = new Thickness(24, 22, 24, 20), Margin = new Thickness(24),
                MinWidth = 380, MaxWidth = 560,
                Effect = new DropShadowEffect { BlurRadius = 30, ShadowDepth = 6, Direction = 270, Opacity = Theme.Dark ? 0.5 : 0.18, Color = Colors.Black }
            };
            card.SetResourceReference(Border.BackgroundProperty, "Surface");
            card.SetResourceReference(Border.BorderBrushProperty, "LineStrong");
            var stack = new StackPanel();
            stack.Children.Add(new TextBlock { Text = title, Style = (Style)Application.Current.Resources["H2"], TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) });
            if (!string.IsNullOrEmpty(text))
                stack.Children.Add(new TextBlock { Text = text, Style = (Style)Application.Current.Resources["Sub"], FontSize = 13.5, LineHeight = 20, Margin = new Thickness(0, 0, 0, 18) });
            TextBox field1 = null;
            if (field != null)
            {
                field1 = new TextBox { Text = field, Style = (Style)Application.Current.Resources["Field"], Margin = new Thickness(0, 0, 0, 18) };
                stack.Children.Add(field1);
            }
            box = field1;
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            for (int i = 0; i < buttons.Length; i++)
            {
                int n = i;
                var b = new Button
                {
                    Content = buttons[i], Margin = new Thickness(i == 0 ? 0 : 10, 0, 0, 0), MinWidth = 92,
                    Style = (Style)Application.Current.Resources[i == 0 ? "BtnPrimary" : "Btn"], IsDefault = i == 0, IsCancel = i == buttons.Length - 1 && buttons.Length > 1
                };
                System.Windows.Automation.AutomationProperties.SetAutomationId(b, "dialog-" + n);
                b.Click += (s, e) => { pressed(n); w.Close(); };
                row.Children.Add(b);
            }
            stack.Children.Add(row);
            card.Child = stack;
            card.MouseLeftButtonDown += (s, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { w.DragMove(); } catch { } };
            w.Content = card;
            w.KeyDown += (s, e) => { if (e.Key == Key.Escape) w.Close(); };
            w.Loaded += (s, e) => { if (field1 != null) { field1.Focus(); field1.SelectAll(); } };
            return w;
        }
    }
}
