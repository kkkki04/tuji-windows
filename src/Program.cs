// 序集 XUJI · 图片与文档整理 —— Windows 原生窗口宿主（WebView2）
// 编译：见 build.ps1（使用系统自带 csc.exe，无需 .NET SDK）
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

[assembly: AssemblyTitle("序集 XUJI")]
[assembly: AssemblyProduct("序集 XUJI · 图片与文档整理")]
[assembly: AssemblyDescription("让每一份灵感，都有序可循。")]
[assembly: AssemblyCompany("XUJI")]
[assembly: AssemblyCopyright("Copyright © 2026 XUJI")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace TuJi
{
    internal static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr LoadLibrary(string lpFileName);

        private static string _appRoot;
        private static Mutex _mutex;

        [STAThread]
        private static void Main()
        {
            bool isFirstInstance;
            _mutex = new Mutex(true, "TuJiApp.SingleInstance", out isFirstInstance);
            if (!isFirstInstance)
            {
                MessageBox.Show("「序集」已经在运行了。", "序集",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // 内嵌的 WebView2 程序集在运行时按需加载（保持 exe 单文件）
            AppDomain.CurrentDomain.AssemblyResolve += ResolveEmbedded;

            try
            {
                _appRoot = ResolveAppRoot();
                Start();
            }
            catch (Exception ex)
            {
                MessageBox.Show("启动失败：\n\n" + ex.Message, "序集",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static Assembly ResolveEmbedded(object sender, ResolveEventArgs args)
        {
            string name = new AssemblyName(args.Name).Name;
            if (name != "Microsoft.Web.WebView2.Core" && name != "Microsoft.Web.WebView2.WinForms")
                return null;

            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name + ".dll"))
            {
                if (stream == null) return null;
                using (MemoryStream buffer = new MemoryStream())
                {
                    stream.CopyTo(buffer);
                    return Assembly.Load(buffer.ToArray());
                }
            }
        }

        // 优先把数据放在 exe 同级目录（便携），不可写时回退到用户目录
        private static string ResolveAppRoot()
        {
            try
            {
                string exeDir = Path.GetDirectoryName(Application.ExecutablePath);
                if (!string.IsNullOrEmpty(exeDir))
                {
                    string portable = Path.Combine(exeDir, "图记数据");
                    Directory.CreateDirectory(portable);
                    string probe = Path.Combine(portable, ".write-test");
                    File.WriteAllText(probe, "ok");
                    File.Delete(probe);
                    return portable;
                }
            }
            catch { }

            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TuJiApp");
        }

        private static void Start()
        {
            string binDir = Path.Combine(_appRoot, "bin");
            string webDir = Path.Combine(_appRoot, "web");
            string dataDir = Path.Combine(_appRoot, "userdata");
            Directory.CreateDirectory(binDir);
            Directory.CreateDirectory(webDir);
            Directory.CreateDirectory(dataDir);

            // 1) 释放并预加载 WebView2Loader.dll（让单文件 exe 也能跑）
            string loaderPath = Path.Combine(binDir, "WebView2Loader.dll");
            Extract("WebView2Loader.dll", loaderPath);
            LoadLibrary(loaderPath);

            // 2) 释放页面文件（内容变化时才覆盖，保留用户数据）
            string htmlPath = Path.Combine(webDir, "index.html");
            Extract("index.html", htmlPath);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Form form = new Form();
            form.Text = "序集·让每一份灵感，都有序可循";
            form.ClientSize = new Size(1280, 860);
            form.MinimumSize = new Size(720, 520);
            form.StartPosition = FormStartPosition.CenterScreen;
            form.BackColor = Color.FromArgb(247, 245, 240);
            try { form.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            WebView2 web = new WebView2();
            web.Dock = DockStyle.Fill;
            form.Controls.Add(web);

            form.Shown += delegate
            {
                InitAsync(web, webDir, dataDir, htmlPath);
            };

            Application.Run(form);
        }

        private static async void InitAsync(WebView2 web, string webDir, string dataDir, string htmlPath)
        {
            try
            {
                CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(null, dataDir, null);
                await web.EnsureCoreWebView2Async(env);

                CoreWebView2 core = web.CoreWebView2;
                core.Settings.AreDefaultContextMenusEnabled = true;
                core.Settings.IsStatusBarEnabled = false;
                core.Settings.AreDevToolsEnabled = true;
                core.Settings.IsZoomControlEnabled = true;

                // 用虚拟域名提供服务：origin 固定为 https://tuji.local，剪贴板与本地存储都稳定可用
                core.SetVirtualHostNameToFolderMapping(
                    "tuji.local", webDir, CoreWebView2HostResourceAccessKind.Allow);
                // 页面更新后带版本参数，避免 WebView2 继续使用旧页面缓存
                string pageVersion = File.GetLastWriteTimeUtc(htmlPath).Ticks.ToString();
                core.Navigate("https://tuji.local/index.html?v=" + pageVersion);
            }
            catch (Exception ex)
            {
                // WebView2 不可用时，退回默认浏览器打开同一页面
                try { System.Diagnostics.Process.Start(htmlPath); } catch { }
                MessageBox.Show(
                    "无法初始化 WebView2 窗口：\n\n" + ex.Message +
                    "\n\n已尝试用默认浏览器打开同一页面。",
                    "序集", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                Application.Exit();
            }
        }

        // 把内嵌资源写到目标路径（内容相同则跳过）
        private static void Extract(string resourceName, string targetPath)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream input = asm.GetManifestResourceStream(resourceName))
            {
                if (input == null) throw new IOException("找不到内嵌资源：" + resourceName);

                byte[] data;
                using (MemoryStream buffer = new MemoryStream())
                {
                    input.CopyTo(buffer);
                    data = buffer.ToArray();
                }

                if (File.Exists(targetPath) && SameBytes(targetPath, data)) return;
                File.WriteAllBytes(targetPath, data);
            }
        }

        private static bool SameBytes(string path, byte[] data)
        {
            FileInfo info = new FileInfo(path);
            if (info.Length != data.Length) return false;

            byte[] existing;
            try { existing = File.ReadAllBytes(path); }
            catch { return false; }

            for (int i = 0; i < data.Length; i++)
            {
                if (existing[i] != data[i]) return false;
            }
            return true;
        }
    }
}
