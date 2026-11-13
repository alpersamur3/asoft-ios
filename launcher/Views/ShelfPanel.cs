using System;
using System.Windows;
using System.Windows.Controls;

namespace ASoftware.Views
{
    /// <summary>The shelf's panel: a WrapPanel of equal-width cards whose last, shorter row stands in the middle (five systems
    /// as three over two, not three over two on the left).</summary>
    public class ShelfPanel : Panel
    {
        public static readonly DependencyProperty ItemWidthProperty = DependencyProperty.Register(nameof(ItemWidth), typeof(double), typeof(ShelfPanel),
            new FrameworkPropertyMetadata(270.0, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsArrange));
        public double ItemWidth { get => (double)GetValue(ItemWidthProperty); set => SetValue(ItemWidthProperty, value); }

        int Columns(double width) => double.IsInfinity(width) ? Math.Max(1, InternalChildren.Count) : Math.Max(1, (int)Math.Floor(width / ItemWidth));

        protected override Size MeasureOverride(Size available)
        {
            int cols = Columns(available.Width);
            double[] h = new double[Math.Max(1, (InternalChildren.Count + cols - 1) / cols)];
            for (int i = 0; i < InternalChildren.Count; i++)
            {
                var c = InternalChildren[i];
                c.Measure(new Size(ItemWidth, double.PositiveInfinity));
                h[i / cols] = Math.Max(h[i / cols], c.DesiredSize.Height);
            }
            double total = 0;
            foreach (var x in h) total += x;
            return new Size(Math.Min(cols, Math.Max(1, InternalChildren.Count)) * ItemWidth, total);
        }

        protected override Size ArrangeOverride(Size finalSize)
        {
            int cols = Columns(finalSize.Width), n = InternalChildren.Count;
            double y = 0;
            for (int r = 0; r * cols < n; r++)
            {
                int inRow = Math.Min(cols, n - r * cols);
                double x = (finalSize.Width - inRow * ItemWidth) / 2, h = 0;
                for (int k = 0; k < inRow; k++) h = Math.Max(h, InternalChildren[r * cols + k].DesiredSize.Height);
                for (int k = 0; k < inRow; k++) InternalChildren[r * cols + k].Arrange(new Rect(x + k * ItemWidth, y, ItemWidth, h));
                y += h;
            }
            return finalSize;
        }
    }
}
