using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;

namespace ASoftware.Views
{
    /// <summary>One system's device, drawn the way the app's logo draws its iPhone (as the Android app's DeviceView): a
    /// metal frame, a black front, and on its screen what the system last showed (Engine\Thumbs). iOS 26 is an iPhone
    /// with the island; iOS 16 the iPhone X its 1080x2400 screen belongs to (a notch); watchOS a watch with its crown,
    /// side button and band; visionOS the headset its QEMU window draws (its glass is its screen: the 1920x1080 picture
    /// fills it, the glass's outline cuts its corners). Without a picture the screen is a home screen in the logo's
    /// colours (the watch: its rings; the headset: icons in a dim room); not installed, an empty faint device with a
    /// plus; while it is installed, a black screen with a thin progress bar, as on an iPhone being restored. Its height
    /// sets its size.</summary>
    public class DeviceArt : FrameworkElement
    {
        static FrameworkPropertyMetadata Meta(object def, bool measure = false) =>
            new FrameworkPropertyMetadata(def, measure ? FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender : FrameworkPropertyMetadataOptions.AffectsRender);

        public static readonly DependencyProperty OsProperty = DependencyProperty.Register(nameof(Os), typeof(string), typeof(DeviceArt), Meta("", true));
        public static readonly DependencyProperty ShotProperty = DependencyProperty.Register(nameof(Shot), typeof(ImageSource), typeof(DeviceArt), Meta(null));
        public static readonly DependencyProperty PresentProperty = DependencyProperty.Register(nameof(Present), typeof(bool), typeof(DeviceArt), Meta(true));
        public static readonly DependencyProperty AwakeProperty = DependencyProperty.Register(nameof(Awake), typeof(bool), typeof(DeviceArt), Meta(false));
        public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(nameof(Progress), typeof(double), typeof(DeviceArt), Meta(-1.0));
        public static readonly DependencyProperty CommandProperty = DependencyProperty.Register(nameof(Command), typeof(ICommand), typeof(DeviceArt),
            new PropertyMetadata(null, (d, e) => ((DeviceArt)d).Cursor = e.NewValue != null ? Cursors.Hand : null));
        /// <summary>How much of a faint device shows (the theme's DeviceFaint: on the light page dark metal at the dark
        /// page's level reads as a grey block).</summary>
        public static readonly DependencyProperty FaintProperty = DependencyProperty.Register(nameof(Faint), typeof(double), typeof(DeviceArt), Meta(0.32));

        /// <summary>ios26, ios16, watch or vision.</summary>
        public string Os { get => (string)GetValue(OsProperty); set => SetValue(OsProperty, value); }
        /// <summary>The system's last screen, or null.</summary>
        public ImageSource Shot { get => (ImageSource)GetValue(ShotProperty); set => SetValue(ShotProperty, value); }
        /// <summary>Installed.</summary>
        public bool Present { get => (bool)GetValue(PresentProperty); set => SetValue(PresentProperty, value); }
        /// <summary>Running: the screen at full brightness.</summary>
        public bool Awake { get => (bool)GetValue(AwakeProperty); set => SetValue(AwakeProperty, value); }
        /// <summary>0..100 while it is installed; negative otherwise.</summary>
        public double Progress { get => (double)GetValue(ProgressProperty); set => SetValue(ProgressProperty, value); }
        /// <summary>What a click does; a device with one lifts a little under the pointer.</summary>
        public ICommand Command { get => (ICommand)GetValue(CommandProperty); set => SetValue(CommandProperty, value); }
        public double Faint { get => (double)GetValue(FaintProperty); set => SetValue(FaintProperty, value); }

        enum Kind { Island, Notch, Watch, Headset }
        Kind K => Os == "ios26" ? Kind.Island : Os == "ios16" ? Kind.Notch : Os == "watch" ? Kind.Watch : Kind.Headset;

        // width / height of the whole drawing: the body and the room for its buttons (the phones), the band (the watch),
        // the knobs on top and the strap's ends at the sides (the headset)
        static double Aspect(Kind k) => k == Kind.Island ? 0.512 : k == Kind.Notch ? 0.503 : k == Kind.Watch ? 0.606 : HsWide / HsHigh;

        static readonly Color[] MetalColors = { C(0x8A909D), C(0x3A3F4B), C(0x2A2E38), C(0x737986) };
        static readonly Color[] MetalLitColors = { C(0xA9AEB9), C(0x555A66), C(0x434753), C(0x8F95A1) };
        static readonly double[] MetalAt = { 0, 0.12, 0.88, 1 };
        static readonly Brush Front = Solid(0x0A0C11), Buttons = Solid(0x4B505C), Empty = Solid(0x0C0D11), Black = Solid(0x000000),
                              IslandInk = Solid(0x04050A), Scrim = Solid(0x000000, 0x3D), BarTrack = Solid(0xFFFFFF, 0x40), BarFill = Solid(0xFFFFFF),
                              PlusInk = Solid(0x5A5F6B);

        readonly TranslateTransform lift = new TranslateTransform();
        ImageBrush shotBrush; ImageSource shotFor; double shotAspect;

        public DeviceArt()
        {
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
            RenderTransform = lift;
            SetResourceReference(FaintProperty, "DeviceFaint");
            Shade();
        }

        bool IsFaint => !Present && Progress < 0;

        /// <summary>A soft shadow on the light page (none on the dark one); a faint device casts none.</summary>
        void Shade()
        {
            if (IsFaint) Effect = null;
            else SetResourceReference(EffectProperty, "DeviceShadow");
        }

        protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
        {
            base.OnPropertyChanged(e);
            if (e.Property == OsProperty || e.Property == PresentProperty || e.Property == ProgressProperty) Shade();
        }

        static Color C(int rgb, byte a = 0xFF) => Color.FromArgb(a, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        static Brush Solid(int rgb, byte a = 0xFF) { var b = new SolidColorBrush(C(rgb, a)); b.Freeze(); return b; }

        static Brush Metal(double x0, double x1, bool lit = false)
        {
            var g = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(x0, 0), EndPoint = new Point(x1, 0) };
            for (int i = 0; i < 4; i++) g.GradientStops.Add(new GradientStop((lit ? MetalLitColors : MetalColors)[i], MetalAt[i]));
            g.Freeze();
            return g;
        }

        /// <summary>A fade at both ends (a band that goes on past what is drawn).</summary>
        static Brush Fade(Point from, Point to, double edge)
        {
            var g = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = from, EndPoint = to };
            g.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 0));
            g.GradientStops.Add(new GradientStop(Colors.Black, edge));
            g.GradientStops.Add(new GradientStop(Colors.Black, 1 - edge));
            g.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 1));
            g.Freeze();
            return g;
        }

        static void Round(DrawingContext dc, Brush b, double l, double t, double r, double bottom, double rad) =>
            dc.DrawRoundedRectangle(b, null, new Rect(l, t, Math.Max(0, r - l), Math.Max(0, bottom - t)), rad, rad);

        protected override Size MeasureOverride(Size a)
        {
            double asp = Aspect(K);
            double h = double.IsInfinity(a.Height) ? 150 : a.Height, w = h * asp;
            if (!double.IsInfinity(a.Width) && w > a.Width) { w = a.Width; h = w / asp; }
            return new Size(w, h);
        }

        // --- drawing ------------------------------------------------------------------------------------
        Rect plusAt = Rect.Empty;
        double plusPen;

        protected override void OnRender(DrawingContext dc)
        {
            double w = RenderSize.Width, h = RenderSize.Height;
            if (w <= 0 || h <= 0) return;
            // (the whole box takes the pointer, so the lift does not flicker at the device's edge)
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, h));
            var k = K;
            bool dim = IsFaint;
            plusAt = Rect.Empty;
            if (dim) dc.PushOpacity(Faint);
            switch (k)
            {
                case Kind.Watch: Watch(dc, w, h); break;
                case Kind.Headset: Headset(dc, w, h); break;
                default: Phone(dc, w, h, k); break;
            }
            if (dim) dc.Pop();
            // the plus of a device that is not there yet, a little clearer than the device
            if (!plusAt.IsEmpty)
            {
                var pen = new Pen(PlusInk, plusPen) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                double c = plusAt.Width * 0.13, cx = plusAt.Left + plusAt.Width / 2, cy = plusAt.Top + plusAt.Height / 2;
                dc.PushOpacity(0.8);
                dc.DrawLine(pen, new Point(cx - c, cy), new Point(cx + c, cy));
                dc.DrawLine(pen, new Point(cx, cy - c), new Point(cx, cy + c));
                dc.Pop();
            }
        }

        void Phone(DrawingContext dc, double w, double h, Kind kind)
        {
            double d = h / 164;                                  // DeviceView's dp at its 164 dp height
            // iOS 26's screen is 1179x2556; iOS 16's 1080x2400 (an iPhone X: its body a little narrower for that screen)
            double ratio = kind == Kind.Notch ? 0.4784 : 0.488;
            double side = 2 * d;                                 // room for the buttons on the edges
            double bw = w - 2 * side, bh = bw / ratio;
            if (bh > h) { bh = h; bw = bh * ratio; }
            double x = (w - bw) / 2, y = (h - bh) / 2;
            double rad = bw * 0.19;
            // the buttons: volume on the left, the side button on the right
            double t = 1.5 * d;
            Round(dc, Buttons, x - t * 0.6, y + bh * 0.21, x + t, y + bh * 0.275, t);
            Round(dc, Buttons, x - t * 0.6, y + bh * 0.30, x + t, y + bh * 0.365, t);
            Round(dc, Buttons, x + bw - t, y + bh * 0.25, x + bw + t * 0.6, y + bh * 0.35, t);
            // the frame and the front
            var r = new Rect(x, y, bw, bh);
            dc.DrawRoundedRectangle(Metal(x, x + bw), null, r, rad, rad);
            double f = Math.Max(1.2 * d, bw * 0.02);
            r.Inflate(-f, -f);
            dc.DrawRoundedRectangle(Front, null, r, rad - f, rad - f);
            double b = Math.Max(2 * d, bw * 0.034);
            var s = r;
            s.Inflate(-b, -b);
            Screen(dc, s, Math.Max(0, rad - f - b), kind, 1.6 * d);
        }

        void Watch(DrawingContext dc, double w, double h)
        {
            double d = h / 132;                                  // DeviceView's dp at its 132 dp height
            double cw = w * 0.80, ch = cw / 0.83;
            if (ch > h * 0.66) { ch = h * 0.66; cw = ch * 0.83; }
            double x = (w - cw) / 2 - 2 * d, y = (h - ch) / 2;
            // the band, above and below, fading out at the ends: a sport band a little lighter than the case's front, with
            // a faint lit edge, so that it reads on the dark page as well as on the light one
            double bw = cw * 0.76, bx = x + (cw - bw) / 2;
            var band = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(bx, 0), EndPoint = new Point(bx + bw, 0) };
            band.GradientStops.Add(new GradientStop(C(0x24262D), 0));
            band.GradientStops.Add(new GradientStop(C(0x3B3E47), 0.5));
            band.GradientStops.Add(new GradientStop(C(0x24262D), 1));
            band.Freeze();
            var edge = new Pen(Solid(0xFFFFFF, 0x1C), Math.Max(0.8, 0.6 * d));
            edge.Freeze();
            dc.PushOpacityMask(Fade(new Point(0, 0), new Point(0, h), 0.16));
            double half = edge.Thickness / 2;
            foreach (var part in new[] { new Rect(bx, 0, bw, y + ch * 0.2), new Rect(bx, y + ch * 0.8, bw, h - (y + ch * 0.8)) })
            {
                dc.DrawRoundedRectangle(band, null, part, 5 * d, 5 * d);
                var lit = part; lit.Inflate(-half, -half);
                dc.DrawRoundedRectangle(null, edge, lit, 5 * d - half, 5 * d - half);
            }
            dc.Pop();
            // the crown and the side button
            var m = Metal(x + cw - 2 * d, x + cw + 5 * d);
            Round(dc, m, x + cw - 2 * d, y + ch * 0.20, x + cw + 4.2 * d, y + ch * 0.40, 1.8 * d);
            Round(dc, m, x + cw - 2 * d, y + ch * 0.52, x + cw + 2 * d, y + ch * 0.72, 1.4 * d);
            // the case and its front
            double rad = cw * 0.27;
            var r = new Rect(x, y, cw, ch);
            dc.DrawRoundedRectangle(Metal(x, x + cw), null, r, rad, rad);
            double f = Math.Max(1.2 * d, cw * 0.022);
            r.Inflate(-f, -f);
            dc.DrawRoundedRectangle(Front, null, r, rad - f, rad - f);
            double b = Math.Max(2.2 * d, cw * 0.05);
            var s = r;
            s.Inflate(-b, -b);
            Screen(dc, s, Math.Max(0, rad - f - b), Kind.Watch, 1.6 * d);
        }

        // --- the headset ----------------------------------------------------------------------------------
        // Apple Vision Pro from the front, as visionOS's QEMU window draws it (ui/gtk-visor.c.inc): one piece of dark
        // glass shaped like ski goggles (round ends, a lobe under each eye, the nose bridge between them) in a thin
        // frame, the Digital Crown on the frame's top at the right, the top button at the left. Lengths are in units
        // of a hundredth of the picture's height; the picture is 16:9 and fills the glass, whose outline cuts its
        // corners. The frame and the knobs are thicker than the window's, as they are drawn small here.
        const double PicW = 177.8, GlassMT = 4.6, GlassMB = 11.5, GlassML = 2.4;
        const double HsFrame = 2.8, HsStrap = 9, HsTop = 4.6, HsBottom = 1.0;
        const double HsHalf = PicW / 2 + GlassML, HsGlass = 100 + GlassMT + GlassMB;
        const double HsWide = 2 * (HsHalf + HsFrame + HsStrap), HsHigh = HsTop + 2 * HsFrame + HsGlass + HsBottom;
        // the outline in its own box: x -1..1 about the centre line, y 0 (top) .. 1 (the lobes), as in the window
        const double VTx = 0.640, VSy = 0.105, VMy = 0.470, VLy = 0.800, VLx1 = 0.860, VLx = 0.560, VAx1 = 0.300, VAx2 = 0.170;
        static readonly double[] TopCurve = { 0, 0, VTx, 0, 1, VSy, 1, VMy };

        /// <summary>The glass's geometry: its centre line and half width, its top and height, the unit.</summary>
        struct Visor { public double Cx, Hw, Top, High, U, Frame, Bridge; }

        static Visor VisorIn(double w, double h)
        {
            double u = Math.Min(w / HsWide, h / HsHigh);
            var v = new Visor { U = u, Cx = w / 2, Hw = HsHalf * u, High = HsGlass * u, Frame = Math.Max(1.4, HsFrame * u) };
            v.Top = (h - HsHigh * u) / 2 + (HsTop + HsFrame) * u;
            // the bridge's top stays clear of the picture
            v.Bridge = (GlassMT + 100 + 2.4) / HsGlass;
            return v;
        }

        static Point VP(Visor v, double x, double y) => new Point(v.Cx + x * v.Hw, v.Top + y * v.High);

        /// <summary>The glass's outline, clockwise from the top of the centre line.</summary>
        static Geometry Outline(Visor v)
        {
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(VP(v, 0, 0), true, true);
                c.BezierTo(VP(v, VTx, 0), VP(v, 1, VSy), VP(v, 1, VMy), true, true);
                c.BezierTo(VP(v, 1, VLy), VP(v, VLx1, 1), VP(v, VLx, 1), true, true);
                c.BezierTo(VP(v, VAx1, 1), VP(v, VAx2, v.Bridge), VP(v, 0, v.Bridge), true, true);
                c.BezierTo(VP(v, -VAx2, v.Bridge), VP(v, -VAx1, 1), VP(v, -VLx, 1), true, true);
                c.BezierTo(VP(v, -VLx1, 1), VP(v, -1, VLy), VP(v, -1, VMy), true, true);
                c.BezierTo(VP(v, -1, VSy), VP(v, -VTx, 0), VP(v, 0, 0), true, true);
            }
            g.Freeze();
            return g;
        }

        static void Bez(double[] p, double t, out double x, out double y, out double dx, out double dy)
        {
            double m = 1 - t;
            x = m * m * m * p[0] + 3 * m * m * t * p[2] + 3 * m * t * t * p[4] + t * t * t * p[6];
            y = m * m * m * p[1] + 3 * m * m * t * p[3] + 3 * m * t * t * p[5] + t * t * t * p[7];
            dx = 3 * m * m * (p[2] - p[0]) + 6 * m * t * (p[4] - p[2]) + 3 * t * t * (p[6] - p[4]);
            dy = 3 * m * m * (p[3] - p[1]) + 6 * m * t * (p[5] - p[3]) + 3 * t * t * (p[7] - p[5]);
        }

        /// <summary>A knob standing on the frame's top edge at @t of the way out to the widest point, on @side (1 the
        /// right): a rounded bar @kw x @kh units, tilted with the edge.</summary>
        static void Knob(DrawingContext dc, Visor v, double t, int side, double kw, double kh, Brush fill, Brush cap)
        {
            Bez(TopCurve, t, out var x, out var y, out var dx, out var dy);
            double tx = dx * v.Hw, ty = dy * v.High * side, len = Math.Sqrt(tx * tx + ty * ty);
            // out to the frame's outer edge: the outward normal of a left-to-right tangent points up
            double px = v.Cx + side * x * v.Hw + ty / len * v.Frame, py = v.Top + y * v.High - tx / len * v.Frame;
            double w = kw * v.U, h = Math.Max(1.4, kh * v.U);
            dc.PushTransform(new RotateTransform(Math.Atan2(ty, tx) * 180 / Math.PI, px, py));
            // (a little into the frame, so no gap shows under it)
            dc.DrawRoundedRectangle(fill, null, new Rect(px - w / 2, py - h, w, h + v.Frame * 0.5), Math.Min(h, w) * 0.45, Math.Min(h, w) * 0.45);
            if (cap != null) dc.DrawRectangle(cap, null, new Rect(px - w / 2 + h * 0.4, py - h, w - h * 0.8, Math.Max(0.6, h * 0.22)));
            dc.Pop();
        }

        /// <summary>The frame's polished metal: the device metal's colours in the light and dark bands a room leaves on
        /// aluminium, slanting across the frame as in the window's drawing; @lit a little brighter (the chamfer).</summary>
        static Brush Polished(Visor v, double lit)
        {
            var g = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(v.Cx - v.Hw * 0.35, v.Top - v.Frame), EndPoint = new Point(v.Cx + v.Hw * 0.35, v.Top + v.High + v.Frame) };
            double[] at = { 0, 0.10, 0.26, 0.42, 0.58, 0.76, 0.90, 1 }, level = { 1.0, 0.68, 0.10, 0.45, 0.0, 0.32, 0.80, 0.18 };
            Color dark = C(0x2E323C), light = C(0xA9AEB9);
            for (int i = 0; i < at.Length; i++)
            {
                double k = Math.Min(1, level[i] + lit);
                g.GradientStops.Add(new GradientStop(Color.FromRgb((byte)(dark.R + (light.R - dark.R) * k), (byte)(dark.G + (light.G - dark.G) * k), (byte)(dark.B + (light.B - dark.B) * k)), at[i]));
            }
            g.Freeze();
            return g;
        }

        void Headset(DrawingContext dc, double w, double h)
        {
            var v = VisorIn(w, h);
            double u = v.U, l = v.Cx - v.Hw, r = v.Cx + v.Hw;
            var outline = Outline(v);
            // the strap's ends at the sides, behind the frame, going back out of sight
            var strap = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(0, v.Top + v.High * 0.30), EndPoint = new Point(0, v.Top + v.High * 0.64) };
            strap.GradientStops.Add(new GradientStop(C(0x4A4E58), 0));
            strap.GradientStops.Add(new GradientStop(C(0x2A2D34), 1));
            strap.Freeze();
            double reach = (HsStrap + HsFrame) * u, sy0 = v.Top + v.High * 0.31, sy1 = v.Top + v.High * 0.63;
            dc.PushOpacityMask(Fade(new Point(l - reach, 0), new Point(r + reach, 0), 0.06));
            Round(dc, strap, l - reach, sy0, l + 6 * u, sy1, 7 * u);
            Round(dc, strap, r - 6 * u, sy0, r + reach, sy1, 7 * u);
            dc.Pop();
            // the knobs: the crown on the right, the top button on the left
            Knob(dc, v, 0.335, 1, 10, 3.6, Metal(v.Cx + v.Hw * 0.52, v.Cx + v.Hw * 0.78, true), Solid(0xFFFFFF, 0x66));
            Knob(dc, v, 0.300, -1, 15, 1.9, Metal(v.Cx - v.Hw * 0.78, v.Cx - v.Hw * 0.42, true), Solid(0xFFFFFF, 0x40));
            // the frame: the outer half of a stroke along the outline, its chamfer towards the glass a little brighter
            dc.DrawGeometry(null, new Pen(Polished(v, 0), 2 * v.Frame) { LineJoin = PenLineJoin.Round }, outline);
            dc.DrawGeometry(null, new Pen(Polished(v, 0.18), 2 * v.Frame * 0.42) { LineJoin = PenLineJoin.Round }, outline);
            // the glass, and what is behind it: the cameras under each eye, the picture
            var glass = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(0, v.Top), EndPoint = new Point(0, v.Top + v.High) };
            glass.GradientStops.Add(new GradientStop(C(0x161A23), 0));
            glass.GradientStops.Add(new GradientStop(C(0x030407), 0.55));
            glass.GradientStops.Add(new GradientStop(C(0x0A0C12), 1));
            glass.Freeze();
            dc.DrawGeometry(glass, null, outline);
            // a broad soft sheen from the upper left, as glass catches a room's light
            var sheen = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(l, v.Top), EndPoint = new Point(v.Cx + v.Hw * 0.2, v.Top + v.High) };
            sheen.GradientStops.Add(new GradientStop(Color.FromArgb(0x22, 0xC8, 0xD4, 0xEE), 0));
            sheen.GradientStops.Add(new GradientStop(Color.FromArgb(0x00, 0xC8, 0xD4, 0xEE), 0.5));
            sheen.Freeze();
            dc.DrawGeometry(sheen, null, outline);
            for (int side = -1; side <= 1; side += 2)
            {
                Lens(dc, new Point(v.Cx + side * 0.290 * v.Hw, v.Top + 108.5 * u), 2.25 * u);
                Lens(dc, new Point(v.Cx + side * 0.392 * v.Hw, v.Top + 110.7 * u), 1.95 * u);
            }
            var pic = new Rect(v.Cx - PicW / 2 * u, v.Top + GlassMT * u, PicW * u, 100 * u);
            dc.PushClip(outline);
            Glass(dc, v, pic);
            Sheen(dc, v);
            dc.Pop();
        }

        /// <summary>A camera behind the glass: a dark barrel and a ring of the lens's coating.</summary>
        static void Lens(DrawingContext dc, Point c, double r)
        {
            dc.DrawEllipse(Solid(0x171A21), new Pen(Solid(0xA8BCE0, 0x2C), Math.Max(0.5, r * 0.14)), c, r, r);
            dc.DrawEllipse(Solid(0x050710), null, c, r * 0.55, r * 0.55);
        }

        /// <summary>What the glass shows in the picture's place @s: the restore bar, the plus, the picture fading into the
        /// glass at its edges, else visionOS's home view; dimmed while the system does not run.</summary>
        void Glass(DrawingContext dc, Visor v, Rect s)
        {
            double u = v.U;
            bool installing = Progress >= 0;
            if (installing)
            {
                double bw = s.Width * 0.36, bh = Math.Max(2, s.Width * 0.012);
                var bar = new Rect(s.Left + (s.Width - bw) / 2, s.Top + (s.Height - bh) / 2, bw, bh);
                dc.DrawRoundedRectangle(BarTrack, null, bar, bh / 2, bh / 2);
                var done = new Rect(bar.Left, bar.Top, bw * Math.Min(1, Progress / 100), bh);
                if (done.Width > 0) dc.DrawRoundedRectangle(BarFill, null, done, bh / 2, bh / 2);
                return;
            }
            if (!Present)
            {
                plusAt = new Rect(v.Cx - s.Height / 2, s.Top, s.Height, s.Height);
                plusPen = Math.Max(1.4, 1.6 * u);
                return;
            }
            if (Shot != null)
            {
                dc.DrawRectangle(ShotBrush(s), null, s);
                // the picture ends in the glass, not at a ruled line
                double fade = 2.2 * u;
                var ink = C(0x020305);
                void Edge(Rect at, Point from, Point to)
                {
                    var g = new LinearGradientBrush(ink, Color.FromArgb(0, ink.R, ink.G, ink.B), from, to) { MappingMode = BrushMappingMode.Absolute };
                    g.Freeze();
                    dc.DrawRectangle(g, null, at);
                }
                Edge(new Rect(s.Left, s.Bottom - fade, s.Width, fade + 0.5), new Point(0, s.Bottom), new Point(0, s.Bottom - fade));
                Edge(new Rect(s.Left, s.Top, s.Width, fade * 0.7), new Point(0, s.Top), new Point(0, s.Top + fade * 0.7));
                Edge(new Rect(s.Left - 0.5, s.Top, fade + 0.5, s.Height), new Point(s.Left, 0), new Point(s.Left + fade, 0));
                Edge(new Rect(s.Right - fade, s.Top, fade + 0.5, s.Height), new Point(s.Right, 0), new Point(s.Right - fade, 0));
            }
            else Home(dc, s);
            if (!Awake) dc.DrawGeometry(Scrim, null, Outline(v));
        }

        /// <summary>visionOS's home view without a picture: the app icons floating in a dim room.</summary>
        static void Home(DrawingContext dc, Rect s)
        {
            var room = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(0, s.Top), EndPoint = new Point(0, s.Bottom) };
            room.GradientStops.Add(new GradientStop(C(0x5D626E), 0));
            room.GradientStops.Add(new GradientStop(C(0x3A3E48), 0.62));
            room.GradientStops.Add(new GradientStop(C(0x2A2C33), 1));
            room.Freeze();
            dc.DrawRectangle(room, null, s);
            double r = s.Height * 0.075, gap = r * 2.9, cx = s.Left + s.Width / 2, cy = s.Top + s.Height * 0.46;
            var icon = Solid(0xFFFFFF, 0x5A);
            int[] rows = { 4, 5, 4 };
            for (int row = 0; row < 3; row++)
                for (int i = 0; i < rows[row]; i++)
                    dc.DrawEllipse(icon, null, new Point(cx + (i - (rows[row] - 1) / 2.0) * gap, cy + (row - 1) * gap * 0.86), r, r);
        }

        /// <summary>The glass's soft reflection: a pale crescent along its top and a thin cool line round its rim.</summary>
        static void Sheen(DrawingContext dc, Visor v)
        {
            double u = v.U;
            const int n = 32;
            const double span = 0.56;
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                // its upper edge follows the glass's, a rim's width in; its lower edge is the flatter arc of a lens
                for (int i = -n; i <= n; i++)
                {
                    double s = (double)i / n;
                    Bez(TopCurve, Math.Abs(s) * span, out var x, out var y, out _, out _);
                    var p = new Point(v.Cx + (s < 0 ? -x : x) * v.Hw, v.Top + y * v.High + (1.0 + 0.4 * s * s) * u);
                    if (i == -n) c.BeginFigure(p, true, true); else c.LineTo(p, false, false);
                }
                for (int i = n; i >= -n; i--)
                {
                    double s = (double)i / n, thick = 5.5 * u * Math.Pow(1 - s * s, 0.8);
                    Bez(TopCurve, Math.Abs(s) * span, out var x, out var y, out _, out _);
                    c.LineTo(new Point(v.Cx + (s < 0 ? -x : x) * v.Hw, v.Top + y * v.High + (1.0 + 0.4 * s * s) * u + thick), false, false);
                }
            }
            g.Freeze();
            var light = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(0, v.Top + u), EndPoint = new Point(0, v.Top + 6.5 * u) };
            light.GradientStops.Add(new GradientStop(Color.FromArgb(0xB4, 0xCC, 0xDE, 0xFA), 0));
            light.GradientStops.Add(new GradientStop(Color.FromArgb(0x30, 0x94, 0xAB, 0xD6), 1));
            light.Freeze();
            dc.DrawGeometry(light, null, g);
            // (twice as wide as it shows: the glass's clip takes its outer half)
            var rim = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(0, v.Top), EndPoint = new Point(0, v.Top + v.High) };
            rim.GradientStops.Add(new GradientStop(Color.FromArgb(0x90, 0xA8, 0xBF, 0xEB), 0));
            rim.GradientStops.Add(new GradientStop(Color.FromArgb(0x30, 0x85, 0x9E, 0xD1), 0.45));
            rim.GradientStops.Add(new GradientStop(Color.FromArgb(0x80, 0xA8, 0xC2, 0xF0), 1));
            rim.Freeze();
            dc.DrawGeometry(null, new Pen(rim, Math.Max(1.6, 1.4 * u)), Outline(v));
        }

        /// <summary>The screen @s: the restore bar while installing, the plus when not there, the picture, else the
        /// placeholder; dimmed while the system does not run.</summary>
        void Screen(DrawingContext dc, Rect s, double radius, Kind kind, double pen)
        {
            if (s.Width <= 0 || s.Height <= 0) return;
            dc.PushClip(new RectangleGeometry(s, radius, radius));
            bool installing = Progress >= 0;
            if (installing)
            {
                dc.DrawRectangle(Black, null, s);
                double bw = s.Width * (kind == Kind.Watch ? 0.5 : 0.42), bh = Math.Max(2, s.Width * 0.018);
                var bar = new Rect(s.Left + (s.Width - bw) / 2, s.Top + (s.Height - bh) / 2, bw, bh);
                dc.DrawRoundedRectangle(BarTrack, null, bar, bh / 2, bh / 2);
                var done = new Rect(bar.Left, bar.Top, bw * Math.Min(1, Progress / 100), bh);
                if (done.Width > 0) dc.DrawRoundedRectangle(BarFill, null, done, bh / 2, bh / 2);
            }
            else if (!Present)
            {
                dc.DrawRectangle(Empty, null, s);
                plusAt = s; plusPen = pen;
            }
            else if (Shot != null) dc.DrawRectangle(ShotBrush(s), null, s);
            else if (kind == Kind.Watch) Rings(dc, s);
            else HomeScreen(dc, s, kind);
            if (Present && !Awake && !installing) dc.DrawRectangle(Scrim, null, s);
            if (Present || installing)
            {
                double sw = s.Width;
                if (kind == Kind.Island)
                {
                    // where iOS 26 draws it in its own frames
                    double iw = sw * 0.31, ih = sw * 0.088, top = s.Top + sw * 0.034, cx = s.Left + sw / 2;
                    dc.DrawRoundedRectangle(IslandInk, null, new Rect(cx - iw / 2, top, iw, ih), ih / 2, ih / 2);
                }
                else if (kind == Kind.Notch)
                {
                    double nw = sw * 0.52, nh = sw * 0.075, cx = s.Left + sw / 2;
                    dc.DrawRoundedRectangle(IslandInk, null, new Rect(cx - nw / 2, s.Top - nh, nw, nh * 2), nh * 0.5, nh * 0.5);
                }
            }
            dc.Pop();
        }

        /// <summary>The picture, centre-cropped to the screen's shape.</summary>
        Brush ShotBrush(Rect s)
        {
            double want = s.Width / s.Height;
            if (shotBrush != null && shotFor == Shot && Math.Abs(shotAspect - want) < 0.002) return shotBrush;
            var img = Shot;
            var bs = img as BitmapSource;
            double iw = bs != null ? bs.PixelWidth : img.Width, ih = bs != null ? bs.PixelHeight : img.Height;
            double have = iw / Math.Max(1, ih);
            var box = have > want ? new Rect((1 - want / have) / 2, 0, want / have, 1) : new Rect(0, (1 - have / want) / 2, 1, have / want);
            var b = new ImageBrush(img) { Viewbox = box, ViewboxUnits = BrushMappingMode.RelativeToBoundingBox, Stretch = Stretch.Fill };
            b.Freeze();
            shotBrush = b; shotFor = img; shotAspect = want;
            return b;
        }

        /// <summary>A home screen in the logo's colours: rows of icons and a dock.</summary>
        static void HomeScreen(DrawingContext dc, Rect s, Kind kind)
        {
            int[] tint = kind == Kind.Island ? new[] { 0x5A9BFF, 0x4A5DF0, 0x5B36CF } : new[] { 0x5AD1C8, 0x2F8FE0, 0x3A56C9 };
            var g = new LinearGradientBrush { MappingMode = BrushMappingMode.Absolute, StartPoint = new Point(s.Left, s.Top), EndPoint = new Point(s.Left + s.Width * 0.35, s.Bottom) };
            g.GradientStops.Add(new GradientStop(C(tint[0]), 0));
            g.GradientStops.Add(new GradientStop(C(tint[1]), 0.6));
            g.GradientStops.Add(new GradientStop(C(tint[2]), 1));
            g.Freeze();
            dc.DrawRectangle(g, null, s);
            double sw = s.Width, icon = sw * 0.155, gap = (sw - 4 * icon) / 5, ir = icon * 0.27;
            double top = s.Top + sw * (kind == Kind.Island ? 0.27 : 0.22);
            const int rows = 5;
            var tile = Solid(0xFFFFFF, 0x40);
            for (int row = 0; row < rows; row++)
                for (int col = 0; col < 4; col++)
                {
                    if (row == rows - 1 && col > 1) break;      // the last row is not full
                    double ix = s.Left + gap + col * (icon + gap), iy = top + row * (icon + gap * 1.25);
                    dc.DrawRoundedRectangle(tile, null, new Rect(ix, iy, icon, icon), ir, ir);
                }
            // the dock
            double dh = icon + gap * 0.9, dy = s.Bottom - dh - gap * 0.7;
            dc.DrawRoundedRectangle(Solid(0xFFFFFF, 0x2E), null, new Rect(s.Left + gap * 0.45, dy, sw - gap * 0.9, dh), icon * 0.42, icon * 0.42);
            var dockTile = Solid(0xFFFFFF, 0x52);
            for (int col = 0; col < 4; col++)
                dc.DrawRoundedRectangle(dockTile, null, new Rect(s.Left + gap + col * (icon + gap), dy + (dh - icon) / 2, icon, icon), ir, ir);
        }

        /// <summary>The watch without a picture: its three rings on black.</summary>
        static void Rings(DrawingContext dc, Rect s)
        {
            dc.DrawRectangle(Black, null, s);
            int[] colors = { 0xFF375F, 0x9BF542, 0x40D4E6 };
            double[] sweep = { 285, 220, 150 };
            double cx = s.Left + s.Width / 2, cy = s.Top + s.Height / 2, stroke = s.Width * 0.085;
            for (int i = 0; i < 3; i++)
            {
                double rr = s.Width * 0.33 - i * stroke * 1.22;
                var under = new Pen(Solid(colors[i], 60), stroke);
                dc.DrawEllipse(null, under, new Point(cx, cy), rr, rr);
                var pen = new Pen(Solid(colors[i]), stroke) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                double a0 = -Math.PI / 2, a1 = a0 + sweep[i] * Math.PI / 180;
                var arc = new StreamGeometry();
                using (var c = arc.Open())
                {
                    c.BeginFigure(new Point(cx + rr * Math.Cos(a0), cy + rr * Math.Sin(a0)), false, false);
                    c.ArcTo(new Point(cx + rr * Math.Cos(a1), cy + rr * Math.Sin(a1)), new Size(rr, rr), 0, sweep[i] > 180, SweepDirection.Clockwise, true, false);
                }
                arc.Freeze();
                dc.DrawGeometry(null, pen, arc);
            }
        }

        // --- the pointer --------------------------------------------------------------------------------
        void Lift(double to) =>
            lift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(170)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });

        protected override void OnMouseEnter(MouseEventArgs e) { base.OnMouseEnter(e); if (Command != null) Lift(-3); }
        protected override void OnMouseLeave(MouseEventArgs e) { base.OnMouseLeave(e); Lift(0); }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonUp(e);
            if (Command != null && Command.CanExecute(null)) { Command.Execute(null); e.Handled = true; }
        }
    }
}
