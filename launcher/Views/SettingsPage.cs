using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using ASoftware.Engine;

namespace ASoftware.Views
{
    /// <summary>The launcher's own settings: language, theme, the tray, update checks; and what it is.</summary>
    public class SettingsPage : UserControl, IRetext
    {
        readonly MainWindow main;
        public SettingsPage(MainWindow main) { this.main = main; Build(); }
        public void Retext() => Build();

        void Build()
        {
            var c = LauncherConfig.Current;
            var p = new StackPanel { MaxWidth = 900, Margin = new Thickness(30, 4, 30, 30), HorizontalAlignment = HorizontalAlignment.Left };
            var back = Ui.Btn(L.K("Back"), () => main.GoHome(), "BtnGhost", "\uE72B");
            back.HorizontalAlignment = HorizontalAlignment.Left;
            back.Margin = new Thickness(-8, 0, 0, 10);
            p.Children.Add(back);
            p.Children.Add(new TextBlock { Text = L.K("Settings"), Style = Ui.S("H1"), Margin = new Thickness(0, 0, 0, 20) });

            p.Children.Add(Ui.Group(L.T("Look", "Görünüm"),
                Ui.Row(L.K("Language"), L.T("The installers and messages follow it.", "Kurucular ve iletiler de ona uyar."),
                    Ui.Seg(new[] { ("auto", L.K("System")), ("en", "English"), ("tr", "Türkçe") }, c.Lang, v => { c.Lang = v; c.Save(); L.Set(v); })),
                Ui.Row(L.K("Theme"), null,
                    Ui.Seg(new[] { ("auto", L.K("System")), ("dark", L.K("Dark")), ("light", L.K("Light")) }, c.Theme, v => { c.Theme = v; c.Save(); Theme.Set(v); Build(); }))));

            p.Children.Add(Ui.Group(L.T("Behaviour", "Davranış"),
                Ui.Row(L.K("CloseToTray"), L.T("While a guest the launcher started or an install runs, closing the window keeps it in the notification area.", "Başlatıcının açtığı bir konuk ya da kurulum çalışırken pencereyi kapatmak onu bildirim alanında tutar."),
                    Ui.Switch(c.CloseToTray, v => { c.CloseToTray = v; c.Save(); })),
                Ui.Row(L.K("CheckUpdates"), L.T("At each start: the newest release of alpersamur3/asoft-ios (read only; nothing is downloaded).", "Her açılışta: alpersamur3/asoft-ios'un en yeni sürümü (yalnız okunur; hiçbir şey indirilmez)."),
                    Ui.Switch(c.CheckUpdates, v => { c.CheckUpdates = v; c.Save(); }))));

            var about = new StackPanel();
            about.Children.Add(Ui.Text("ASoftware " + Updates.AppVersion + (Updates.DevBuild ? L.T(" (development build)", " (geliştirme derlemesi)") : ""), "H3"));
            about.Children.Add(Ui.Text(L.T("App folder: ", "Uygulama klasörü: ") + AppPaths.Root, "Faint", 6));
            about.Children.Add(Ui.Text(L.T("Settings: ", "Ayarlar: ") + AppPaths.ConfigFile, "Faint", 2));
            about.Children.Add(Ui.Text(L.T("Imported: ", "İçe aktarılan: ") + c.Imported, "Faint", 2));
            // (four ways out of the launcher, none of them the page's main act: links, not capsules)
            var links = Ui.Hstack(
                Ui.Btn("GitHub", () => MainWindow.Open("https://github.com/" + Updates.Repo), "BtnLink"),
                Ui.Btn(L.T("Report a problem", "Sorun bildir"), () => main.OpenReport(), "BtnLink"),
                Ui.Btn(L.T("Open the settings folder", "Ayar klasörünü aç"), () => MainWindow.Open(AppPaths.LocalData), "BtnLink"),
                Ui.Btn(L.T("Launcher log", "Başlatıcı logu"), () => MainWindow.Open(Log.File), "BtnLink"));
            links.Margin = new Thickness(-2, 8, 0, -4);
            about.Children.Add(links);
            var box = new Border { Child = about, Padding = new Thickness(18, 16, 18, 16), CornerRadius = new CornerRadius(16), BorderThickness = new Thickness(1) };
            box.SetResourceReference(Border.BackgroundProperty, "Surface");
            box.SetResourceReference(Border.BorderBrushProperty, "Line");
            // (headed like the groups above it)
            p.Children.Add(Ui.Dyn(new TextBlock { Text = L.K("About"), Style = Ui.S("H3"), FontSize = 12.5, Margin = new Thickness(4, 0, 0, 8) }, TextBlock.ForegroundProperty, "Text2"));
            p.Children.Add(box);
            Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = p };
        }
    }
}
