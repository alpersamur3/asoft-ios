using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace ASoftware.Views
{
    /// <summary>A Border that clips what it holds to its own rounded corners (a plain Border only rounds its
    /// background, and ClipToBounds cuts square).</summary>
    public class ClipBorder : Border
    {
        protected override Size ArrangeOverride(Size size)
        {
            var r = base.ArrangeOverride(size);
            Clip = Rounded(new Rect(0, 0, r.Width, r.Height), CornerRadius);
            return r;
        }

        public static Geometry Rounded(Rect b, CornerRadius c)
        {
            double tl = Math.Min(c.TopLeft, Math.Min(b.Width, b.Height) / 2), tr = Math.Min(c.TopRight, Math.Min(b.Width, b.Height) / 2);
            double br = Math.Min(c.BottomRight, Math.Min(b.Width, b.Height) / 2), bl = Math.Min(c.BottomLeft, Math.Min(b.Width, b.Height) / 2);
            var g = new StreamGeometry();
            using (var x = g.Open())
            {
                x.BeginFigure(new Point(b.Left + tl, b.Top), true, true);
                x.LineTo(new Point(b.Right - tr, b.Top), false, false);
                if (tr > 0) x.ArcTo(new Point(b.Right, b.Top + tr), new Size(tr, tr), 0, false, SweepDirection.Clockwise, false, false);
                x.LineTo(new Point(b.Right, b.Bottom - br), false, false);
                if (br > 0) x.ArcTo(new Point(b.Right - br, b.Bottom), new Size(br, br), 0, false, SweepDirection.Clockwise, false, false);
                x.LineTo(new Point(b.Left + bl, b.Bottom), false, false);
                if (bl > 0) x.ArcTo(new Point(b.Left, b.Bottom - bl), new Size(bl, bl), 0, false, SweepDirection.Clockwise, false, false);
                x.LineTo(new Point(b.Left, b.Top + tl), false, false);
                if (tl > 0) x.ArcTo(new Point(b.Left + tl, b.Top), new Size(tl, tl), 0, false, SweepDirection.Clockwise, false, false);
            }
            g.Freeze();
            return g;
        }
    }
}
