using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>Report a problem: filled in here, sent by the person from GitHub's own page in their browser.</summary>
    public class ReportPage : UserControl, IRetext
    {
        // Chrome and Windows' shell hand over URLs up to about 2,048 characters for certain
        const int MaxUrl = 2000;

        readonly MainWindow main;
        string area, title, text;
        bool withPc = true;
        string pc = "";
        string zip;
        TextBox titleBox, textBox;
        TextBlock problem;

        public ReportPage(MainWindow main, string area = null, string title = null, string text = null)
        {
            this.main = main;
            this.area = area ?? "launcher";
            this.title = title ?? "";
            this.text = text ?? "";
            Build();
            Loaded += async (s, e) =>
            {
                if (pc != "") return;
                pc = await Task.Run(() => LogPack.PcInfo());
                Keep(); Build();
            };
        }

        public void Retext() { Keep(); Build(); }

        void Keep() { if (titleBox != null) { title = titleBox.Text; text = textBox.Text; } }

        static IEnumerable<(string value, string label)> Areas() => new[]
        {
            ("ios16", "iOS 16"), ("ios26", "iOS 26"), ("watch", "watchOS"),
            ("install", L.T("Install", "Kurulum")), ("phone", L.T("Phone", "Telefon")), ("launcher", L.T("Launcher", "Başlatıcı"))
        };

        static string AreaName(string a) { foreach (var x in Areas()) if (x.value == a) return x.label; return a; }

        void Build()
        {
            var p = new StackPanel { MaxWidth = 860, Margin = new Thickness(30, 4, 30, 30), HorizontalAlignment = HorizontalAlignment.Left };
            var back = Ui.Btn(L.K("Back"), () => main.GoHome(), "BtnGhost", "");
            back.HorizontalAlignment = HorizontalAlignment.Left;
            back.Margin = new Thickness(-8, 0, 0, 10);
            p.Children.Add(back);
            p.Children.Add(new TextBlock { Text = L.T("Report a problem", "Sorun bildir"), Style = Ui.S("H1") });
            p.Children.Add(Ui.Text(L.T("Nothing is sent from here: GitHub opens in your browser with this filled in, and you send it there (a GitHub account is needed).",
                "Buradan hiçbir şey gönderilmez: GitHub tarayıcınızda bunlar doldurulmuş olarak açılır, siz oradan gönderirsiniz (GitHub hesabı gerekir)."), "Sub", 4));
            p.Children.Add(new Border { Height = 18 });

            titleBox = Ui.Field(title, double.NaN);
            AutomationProperties.SetAutomationId(titleBox, "report-title");
            textBox = Ui.Field(text, double.NaN);
            textBox.AcceptsReturn = true; textBox.TextWrapping = TextWrapping.Wrap; textBox.Height = 150;
            textBox.VerticalContentAlignment = VerticalAlignment.Top;
            textBox.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            AutomationProperties.SetAutomationId(textBox, "report-text");
            problem = Ui.Text("", "Faint", 4);
            problem.SetResourceReference(TextBlock.ForegroundProperty, "Bad");
            problem.Visibility = Visibility.Collapsed;
            var titled = new StackPanel();
            titled.Children.Add(Ui.Text(L.T("A short title", "Kısa bir başlık"), "H3"));
            titled.Children.Add(Spaced(titleBox, 6));
            titled.Children.Add(problem);
            var told = new StackPanel();
            told.Children.Add(Ui.Text(L.T("What happened, and what you expected", "Ne oldu, ne bekliyordunuz"), "H3"));
            told.Children.Add(Ui.Text(L.T("What you did before it, and the exact text of an error if there was one.", "Öncesinde ne yaptınız; hata çıktıysa tam metni."), "Faint", 2));
            told.Children.Add(Spaced(textBox, 8));
            p.Children.Add(Ui.Group(null,
                Ui.Row(L.T("Where is it", "Nerede"), null, Ui.Seg(Areas(), area, v => area = v)),
                Ui.Row(null, null, titled),
                Ui.Row(null, null, told)));

            var info = new TextBox { Style = Ui.S("Field"), Text = pc, IsReadOnly = true, FontFamily = Ui.F("Mono"), FontSize = 11.5, AcceptsReturn = true, TextWrapping = TextWrapping.NoWrap, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalContentAlignment = VerticalAlignment.Top, MinHeight = 60 };
            var pack = Ui.Btn(L.K("PackLogs"), Pack, "Btn", "");
            var logsNote = zip == null
                ? L.T("A zip on your desktop, to drag onto the GitHub page. Your user name is taken out of the paths; other folder names and what the guest printed stay, so look through it first.",
                      "Masaüstüne bir zip; GitHub sayfasına sürükleyebilirsiniz. Yollardaki kullanıcı adınız çıkarılır; diğer klasör adları ve konuğun yazdıkları kalır, önce bir göz atın.")
                : L.T("Packed: ", "Paketlendi: ") + zip + "  " + L.T("Drag it onto the GitHub page.", "GitHub sayfasına sürükleyin.");
            p.Children.Add(Ui.Group(L.T("What goes with it", "Yanında ne gitsin"),
                Ui.Row(L.T("This PC's details", "Bu PC'nin bilgileri"), L.T("Exactly the text below; it has no file paths or names.", "Tam olarak aşağıdaki metin; içinde dosya yolu ya da isim yok."),
                    Ui.Switch(withPc, v => { withPc = v; info.Visibility = v ? Visibility.Visible : Visibility.Collapsed; })),
                Ui.Row(null, null, info),
                Ui.Row(L.T("Logs", "Loglar"), logsNote, pack)));
            info.Visibility = withPc ? Visibility.Visible : Visibility.Collapsed;

            var send = Ui.Btn(L.T("Open on GitHub", "GitHub'da aç"), Send, "BtnPrimary", "");
            AutomationProperties.SetAutomationId(send, "report-send");
            send.HorizontalAlignment = HorizontalAlignment.Left;
            p.Children.Add(send);
            Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = p };
        }

        static FrameworkElement Spaced(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }

        async void Pack()
        {
            try
            {
                var os = area == "ios16" || area == "ios26" || area == "watch" ? area : null;
                zip = await Task.Run(() => LogPack.Make(os));
                Keep(); Build();
                System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + zip + "\"");
            }
            catch (Exception e) { Dialog.Show(main, L.T("Not packed", "Paketlenmedi"), e.Message, L.K("OK")); }
        }

        string Body()
        {
            var sb = new StringBuilder();
            sb.Append(textBox.Text.Trim());
            if (withPc && pc != "") sb.Append("\n\n```\n").Append(pc.Replace("\r", "")).Append("\n```");
            return sb.ToString();
        }

        static string Url(string title, string body) =>
            "https://github.com/" + Updates.Repo + "/issues/new?title=" + Uri.EscapeDataString(title) + "&body=" + Uri.EscapeDataString(body);

        public string BuildUrl(out bool clipboard)
        {
            var t = "[" + AreaName(area) + "] " + titleBox.Text.Trim();
            var body = Body();
            var url = Url(t, body);
            clipboard = url.Length > MaxUrl;
            if (clipboard) url = Url(t, L.T("(The details are on the clipboard: paste them here with Ctrl+V.)", "(Ayrıntılar panoda: buraya Ctrl+V ile yapıştırın.)"));
            return url;
        }

        void Send()
        {
            if (titleBox.Text.Trim() == "")
            {
                problem.Text = L.T("Write a title first.", "Önce bir başlık yazın.");
                problem.Visibility = Visibility.Visible;
                titleBox.Focus();
                return;
            }
            problem.Visibility = Visibility.Collapsed;
            var url = BuildUrl(out var clipboard);
            if (clipboard)
            {
                try { Clipboard.SetText(Body()); }
                catch (Exception e) { Log.Write("clipboard: " + e.Message); }
                main.Snack(L.T("It is long for a link: the details are on the clipboard. Paste them on the GitHub page.", "Bağlantı için uzun: ayrıntılar panoda. GitHub sayfasına yapıştırın."), "info");
            }
            Log.Write($"report: opening an issue page ({url.Length} characters{(clipboard ? ", body on the clipboard" : "")})");
            MainWindow.Open(url);
        }
    }
}
