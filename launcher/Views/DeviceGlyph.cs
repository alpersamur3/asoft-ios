using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ASoftware.Views
{
    /// <summary>A drawn device for each OS's card: a phone with a notch (iOS 16), with an island (iOS 26), a watch, a headset.
    /// White lines and a few app tiles over the card's gradient; no logos.</summary>
    public class DeviceGlyph : Grid
    {
        public static readonly DependencyProperty OsProperty = DependencyProperty.Register(nameof(Os), typeof(string), typeof(DeviceGlyph),
            new PropertyMetadata("", (d, e) => ((DeviceGlyph)d).Build()));
        public string Os { get => (string)GetValue(OsProperty); set => SetValue(OsProperty, value); }

        static Brush W(byte a) { var b = new SolidColorBrush(Color.FromArgb(a, 255, 255, 255)); b.Freeze(); return b; }

        void Build()
        {
            Children.Clear();
            switch (Os)
            {
                case "ios16": Phone(false); break;
                case "ios26": Phone(true); break;
                case "watch": Watch(); break;
                default: Vision(); break;
            }
        }

        void Phone(bool island)
        {
            var frame = new Border
            {
                Width = 74, Height = 150, CornerRadius = new CornerRadius(island ? 16 : 14), BorderThickness = new Thickness(3.2),
                BorderBrush = W(235), Background = W(30), VerticalAlignment = VerticalAlignment.Top
            };
            var g = new Grid();
            if (island)
                g.Children.Add(new Border { Width = 22, Height = 7, CornerRadius = new CornerRadius(3.5), Background = W(235), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 5, 0, 0) });
            else
                g.Children.Add(new Border { Width = 30, Height = 7, CornerRadius = new CornerRadius(0, 0, 4, 4), Background = W(235), VerticalAlignment = VerticalAlignment.Top });
            var tiles = new UniformGrid { Columns = 4, Rows = 4, Margin = new Thickness(7, island ? 22 : 20, 7, 0), VerticalAlignment = VerticalAlignment.Top };
            for (int i = 0; i < 14; i++)
                tiles.Children.Add(new Border { Width = 11, Height = 11, Margin = new Thickness(1.8), CornerRadius = new CornerRadius(3), Background = W((byte)(i % 3 == 0 ? 150 : 95)) });
            g.Children.Add(tiles);
            var dock = new Border { Height = 18, Margin = new Thickness(5, 0, 5, 6), CornerRadius = new CornerRadius(island ? 8 : 6), Background = W(55), VerticalAlignment = VerticalAlignment.Bottom };
            var dockTiles = new UniformGrid { Columns = 4, Margin = new Thickness(3, 3, 3, 3) };
            for (int i = 0; i < 4; i++) dockTiles.Children.Add(new Border { Width = 10, Height = 10, CornerRadius = new CornerRadius(3), Background = W(170) });
            dock.Child = dockTiles;
            g.Children.Add(dock);
            frame.Child = g;
            frame.RenderTransform = new RotateTransform(-8, 37, 75);
            Children.Add(frame);
        }

        void Watch()
        {
            var stack = new Grid { Width = 96, Height = 150 };
            // the band, above and below
            stack.Children.Add(new Border { Width = 52, Height = 150, CornerRadius = new CornerRadius(10), Background = W(45) });
            var cse = new Border
            {
                Width = 84, Height = 98, CornerRadius = new CornerRadius(26), BorderThickness = new Thickness(3.2), BorderBrush = W(235),
                Background = new SolidColorBrush(Color.FromArgb(150, 20, 10, 30)), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left
            };
            // a honeycomb of apps
            var hc = new Canvas { Width = 70, Height = 84 };
            double[][] at = { new[] { 35.0, 42 }, new[] { 20.0, 42 }, new[] { 50.0, 42 }, new[] { 27.5, 29 }, new[] { 42.5, 29 }, new[] { 27.5, 55 }, new[] { 42.5, 55 }, new[] { 35.0, 16 }, new[] { 35.0, 68 }, new[] { 12.5, 29 }, new[] { 57.5, 55 } };
            for (int i = 0; i < at.Length; i++)
            {
                var e = new Ellipse { Width = 12, Height = 12, Fill = W((byte)(i == 0 ? 220 : i < 7 ? 150 : 90)) };
                Canvas.SetLeft(e, at[i][0] - 6); Canvas.SetTop(e, at[i][1] - 6);
                hc.Children.Add(e);
            }
            cse.Child = hc;
            stack.Children.Add(cse);
            // the crown and the side button
            stack.Children.Add(new Border { Width = 7, Height = 16, CornerRadius = new CornerRadius(2), Background = W(235), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 5, 16), VerticalAlignment = VerticalAlignment.Center });
            stack.Children.Add(new Border { Width = 4, Height = 20, CornerRadius = new CornerRadius(2), Background = W(200), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 30, 8, 0), VerticalAlignment = VerticalAlignment.Center });
            stack.RenderTransform = new RotateTransform(-8, 48, 75);
            Children.Add(stack);
        }

        void Vision()
        {
            var g = new Grid { Width = 124, Height = 92 };
            var band = new Border { Width = 124, Height = 28, CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(3), BorderBrush = W(110), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 26, 0, 0) };
            var front = new Border { Width = 104, Height = 54, CornerRadius = new CornerRadius(26), BorderThickness = new Thickness(3.2), BorderBrush = W(235), Background = W(40), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 12, 0, 0) };
            var glass = new Border { Margin = new Thickness(8), CornerRadius = new CornerRadius(22), Background = new LinearGradientBrush(Color.FromArgb(120, 255, 255, 255), Color.FromArgb(20, 255, 255, 255), 30) };
            front.Child = glass;
            g.Children.Add(band);
            g.Children.Add(front);
            Children.Add(g);
        }
    }
}
