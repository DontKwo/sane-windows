using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SaneWindowsHost
{
    internal static class Program
    {
        private static readonly Dictionary<string, byte[]> Assets = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        private static readonly object FileLock = new object();
        private static string _workspaceDir;

        [STAThread]
        private static int Main(string[] args)
        {
            bool selfTest = false;
            bool headless = false;
            int requestedPort = 0;
            _workspaceDir = ResolveWorkspaceDir();

            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i] ?? string.Empty;
                if (arg == "--self-test")
                {
                    selfTest = true;
                }
                else if (arg == "--headless-server")
                {
                    headless = true;
                    if (i + 1 < args.Length)
                    {
                        int parsedPort;
                        if (int.TryParse(args[i + 1], out parsedPort))
                        {
                            requestedPort = parsedPort;
                            i++;
                        }
                    }
                }
                else if (arg.StartsWith("--workspace=", StringComparison.OrdinalIgnoreCase))
                {
                    _workspaceDir = arg.Substring("--workspace=".Length).Trim();
                }
            }

            LoadEmbeddedAssets();
            TcpListener listener = new TcpListener(IPAddress.Loopback, requestedPort);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;

            CancellationTokenSource cts = new CancellationTokenSource();
            Task.Run(() => RunServerLoop(listener, cts.Token));

            string baseUrl = "http://127.0.0.1:" + port + "/";
            if (selfTest)
            {
                using (var http = new HttpClient())
                {
                    http.Timeout = TimeSpan.FromSeconds(5);
                    string html = http.GetStringAsync(baseUrl).GetAwaiter().GetResult();
                    if (string.IsNullOrEmpty(html) || !html.Contains("Sane Windows"))
                    {
                        throw new InvalidOperationException("Self-test failed: HTML shell missing.");
                    }
                    string health = http.GetStringAsync(baseUrl + "api/health").GetAwaiter().GetResult();
                    if (!health.Contains("\"ok\":true"))
                    {
                        throw new InvalidOperationException("Self-test failed: health endpoint failed.");
                    }
                    string cfg = http.GetStringAsync(baseUrl + "api/config").GetAwaiter().GetResult();
                    if (!cfg.Contains("\"ok\":true"))
                    {
                        throw new InvalidOperationException("Self-test failed: config endpoint failed.");
                    }
                }
                Console.WriteLine("SELF_TEST_OK " + baseUrl);
                Console.Out.Flush();
                cts.Cancel();
                try { listener.Stop(); } catch { }
                return 0;
            }

            if (headless)
            {
                Console.WriteLine("READY " + baseUrl);
                Console.Out.Flush();
                try
                {
                    while (!cts.IsCancellationRequested)
                    {
                        Thread.Sleep(200);
                    }
                }
                catch
                {
                    // Exit headless loop cleanly
                }
                listener.Stop();
                return 0;
            }

            LaunchDesktopWindow(baseUrl);
            cts.Cancel();
            try { listener.Stop(); } catch { }
            return 0;
        }

        private static string ResolveWorkspaceDir()
        {
            string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) ?? Environment.CurrentDirectory;
            string[] candidates = new[] { Environment.CurrentDirectory, exeDir, Path.GetFullPath(Path.Combine(exeDir, "..")) };
            foreach (string dir in candidates)
            {
                if (!string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "config.yaml")))
                {
                    return dir;
                }
            }
            return Environment.CurrentDirectory;
        }

        private static void LoadEmbeddedAssets()
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream stream = asm.GetManifestResourceStream("app-assets.zip"))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Embedded app-assets.zip missing.");
                }
                using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        if (string.IsNullOrEmpty(entry.Name)) continue;
                        string key = entry.FullName.Replace('\\', '/').TrimStart('/');
                        using (Stream entryStream = entry.Open())
                        using (MemoryStream ms = new MemoryStream())
                        {
                            entryStream.CopyTo(ms);
                            Assets[key] = ms.ToArray();
                        }
                    }
                }
            }
        }

        private static void LaunchDesktopWindow(string baseUrl)
        {
            string browserExe = FindAppShellBrowser();
            string profileDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SaneWindows",
                "WindowProfile"
            );
            Directory.CreateDirectory(profileDir);

            if (!string.IsNullOrEmpty(browserExe))
            {
                var psi = new ProcessStartInfo
                {
                    FileName = browserExe,
                    Arguments = "--app=" + baseUrl + " --user-data-dir=\"" + profileDir + "\" --new-window --window-size=1280,820 --no-first-run --no-default-browser-check",
                    UseShellExecute = false
                };
                using (Process proc = Process.Start(psi))
                {
                    if (proc != null)
                    {
                        proc.WaitForExit();
                        return;
                    }
                }
            }
            Process.Start(new ProcessStartInfo { FileName = baseUrl, UseShellExecute = true });
            Thread.Sleep(60000);
        }

        private static string FindAppShellBrowser()
        {
            string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string[] candidates = new[]
            {
                Path.Combine(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
                Path.Combine(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
                Path.Combine(pf, "Google", "Chrome", "Application", "chrome.exe"),
                Path.Combine(pf86, "Google", "Chrome", "Application", "chrome.exe"),
                Path.Combine(local, "Google", "Chrome", "Application", "chrome.exe")
            };
            foreach (string path in candidates)
            {
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) return path;
            }
            return string.Empty;
        }

        private static void RunServerLoop(TcpListener listener, CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    Task.Run(() => HandleClient(client));
                }
                catch
                {
                    if (token.IsCancellationRequested) break;
                }
            }
        }

        private static void HandleClient(TcpClient client)
        {
            using (client)
            using (NetworkStream stream = client.GetStream())
            {
                try
                {
                    var reader = new StreamReader(stream, Encoding.UTF8, false, 4096, true);
                    string requestLine = reader.ReadLine();
                    if (string.IsNullOrEmpty(requestLine)) return;

                    int contentLength = 0;
                    string line;
                    while (!string.IsNullOrEmpty(line = reader.ReadLine()))
                    {
                        if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                        {
                            int.TryParse(line.Substring("Content-Length:".Length).Trim(), out contentLength);
                        }
                    }

                    string bodyText = string.Empty;
                    if (contentLength > 0)
                    {
                        char[] buf = new char[contentLength];
                        int totalRead = 0;
                        while (totalRead < contentLength)
                        {
                            int n = reader.Read(buf, totalRead, contentLength - totalRead);
                            if (n <= 0) break;
                            totalRead += n;
                        }
                        bodyText = new string(buf, 0, totalRead);
                    }

                    string[] parts = requestLine.Split(' ');
                    string method = parts.Length >= 1 ? parts[0] : "GET";
                    string rawTarget = parts.Length >= 2 ? parts[1] : "/";
                    int qIdx = rawTarget.IndexOf('?');
                    string reqPath = Uri.UnescapeDataString(qIdx >= 0 ? rawTarget.Substring(0, qIdx) : rawTarget);

                    if (reqPath.StartsWith("/api/", StringComparison.OrdinalIgnoreCase))
                    {
                        byte[] jsonBytes = Encoding.UTF8.GetBytes(HandleApi(method, reqPath, bodyText));
                        WriteHttpResponse(stream, 200, "application/json; charset=utf-8", jsonBytes);
                        return;
                    }

                    string key = reqPath == "/" ? "index.html" : reqPath.TrimStart('/');
                    byte[] body;
                    if (!Assets.TryGetValue(key, out body))
                    {
                        key = "index.html";
                        if (!Assets.TryGetValue(key, out body))
                        {
                            WriteHttpResponse(stream, 404, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes("Not Found"));
                            return;
                        }
                    }
                    WriteHttpResponse(stream, 200, GetMimeType(key), body);
                }
                catch
                {
                    // Ignore closed browser socket
                }
            }
        }

        private static string HandleApi(string method, string reqPath, string bodyText)
        {
            var ser = new JavaScriptSerializer();
            if (reqPath == "/api/health")
            {
                return ser.Serialize(new Dictionary<string, object> { { "ok", true }, { "workspace", _workspaceDir } });
            }
            if (reqPath == "/api/config" && method == "GET")
            {
                return ser.Serialize(new Dictionary<string, object> { { "ok", true }, { "sections", ParseConfigYaml() } });
            }
            if (reqPath == "/api/config" && method == "POST")
            {
                var req = ser.Deserialize<Dictionary<string, object>>(bodyText) ?? new Dictionary<string, object>();
                SaveConfigYaml(req);
                return ser.Serialize(new Dictionary<string, object> { { "ok", true }, { "output", "Updated config.yaml" } });
            }
            if (reqPath == "/api/snapshots")
            {
                return ser.Serialize(new Dictionary<string, object> { { "ok", true }, { "snapshots", ListSnapshots() } });
            }
            if (reqPath == "/api/setup/preview")
            {
                return ser.Serialize(RunPowerShell("setup.ps1", "-WhatIf"));
            }
            if (reqPath == "/api/setup/apply")
            {
                return ser.Serialize(RunPowerShell("setup.ps1", "-Yes -NoExplorerRestart"));
            }
            if (reqPath == "/api/setup/revert")
            {
                var req = ser.Deserialize<Dictionary<string, object>>(bodyText) ?? new Dictionary<string, object>();
                string snap = req.ContainsKey("snapshot") && req["snapshot"] != null ? req["snapshot"].ToString() : string.Empty;
                string safeName = Path.GetFileName(snap);
                string snapPath = Path.Combine(_workspaceDir, "snapshots", safeName);
                return ser.Serialize(RunPowerShell("setup.ps1", "-Revert -NoExplorerRestart -SnapshotPath \"" + snapPath + "\""));
            }
            if (reqPath == "/api/cleanup/scan")
            {
                var req = ser.Deserialize<Dictionary<string, object>>(bodyText) ?? new Dictionary<string, object>();
                int days = req.ContainsKey("minAgeDays") ? Convert.ToInt32(req["minAgeDays"]) : 0;
                return ser.Serialize(RunPowerShell("clean-storage.ps1", "-WhatIf -MinAgeDays " + days));
            }
            if (reqPath == "/api/cleanup/run")
            {
                var req = ser.Deserialize<Dictionary<string, object>>(bodyText) ?? new Dictionary<string, object>();
                int days = req.ContainsKey("minAgeDays") ? Convert.ToInt32(req["minAgeDays"]) : 0;
                return ser.Serialize(RunPowerShell("clean-storage.ps1", "-Yes -MinAgeDays " + days));
            }
            if (reqPath == "/api/tooling/status")
            {
                return ser.Serialize(RunPowerShell("check-tooling.ps1", ""));
            }
            if (reqPath == "/api/tooling/action")
            {
                var req = ser.Deserialize<Dictionary<string, object>>(bodyText) ?? new Dictionary<string, object>();
                string mode = req.ContainsKey("mode") && req["mode"] != null ? req["mode"].ToString() : "status";
                string flag = mode == "install" ? "-Install" : (mode == "update" ? "-Update" : "");
                return ser.Serialize(RunPowerShell("check-tooling.ps1", flag));
            }
            return ser.Serialize(new Dictionary<string, object> { { "ok", false }, { "error", "Unknown endpoint" } });
        }

        private static List<Dictionary<string, object>> ParseConfigYaml()
        {
            var sections = new List<Dictionary<string, object>>();
            string cfgPath = Path.Combine(_workspaceDir, "config.yaml");
            if (!File.Exists(cfgPath)) return sections;

            Dictionary<string, object> current = null;
            List<Dictionary<string, object>> items = null;
            foreach (string rawLine in File.ReadAllLines(cfgPath, Encoding.UTF8))
            {
                string trimmed = rawLine.Trim();
                if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith("#")) continue;
                var secMatch = Regex.Match(rawLine, @"^([a-zA-Z0-9_]+):\s*$");
                if (secMatch.Success)
                {
                    current = new Dictionary<string, object>();
                    items = new List<Dictionary<string, object>>();
                    current["name"] = secMatch.Groups[1].Value;
                    current["items"] = items;
                    sections.Add(current);
                    continue;
                }
                var boolMatch = Regex.Match(rawLine, @"^\s{2}([a-zA-Z0-9_]+):\s*(true|false)\s*$", RegexOptions.IgnoreCase);
                if (boolMatch.Success && items != null)
                {
                    items.Add(new Dictionary<string, object>
                    {
                        { "key", boolMatch.Groups[1].Value },
                        { "enabled", string.Equals(boolMatch.Groups[2].Value, "true", StringComparison.OrdinalIgnoreCase) }
                    });
                }
            }
            return sections;
        }

        private static void SaveConfigYaml(Dictionary<string, object> req)
        {
            string cfgPath = Path.Combine(_workspaceDir, "config.yaml");
            if (!File.Exists(cfgPath) || !req.ContainsKey("sections")) return;
            var updates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var secList = req["sections"] as object[];
            if (secList == null)
            {
                var arrList = req["sections"] as System.Collections.ArrayList;
                if (arrList != null) secList = arrList.ToArray();
            }
            if (secList != null)
            {
                foreach (object secObj in secList)
                {
                    var secDict = secObj as Dictionary<string, object>;
                    if (secDict == null || !secDict.ContainsKey("items")) continue;
                    var itemArr = secDict["items"] as System.Collections.ArrayList;
                    if (itemArr == null) continue;
                    foreach (object itemObj in itemArr)
                    {
                        var itemDict = itemObj as Dictionary<string, object>;
                        if (itemDict == null) continue;
                        string key = itemDict["key"].ToString();
                        bool enabled = Convert.ToBoolean(itemDict["enabled"]);
                        updates[key] = enabled ? "true" : "false";
                    }
                }
            }

            lock (FileLock)
            {
                string[] lines = File.ReadAllLines(cfgPath, Encoding.UTF8);
                for (int i = 0; i < lines.Length; i++)
                {
                    var m = Regex.Match(lines[i], @"^(\s{2})([a-zA-Z0-9_]+):\s*(true|false)(\s*)$", RegexOptions.IgnoreCase);
                    if (m.Success && updates.ContainsKey(m.Groups[2].Value))
                    {
                        lines[i] = m.Groups[1].Value + m.Groups[2].Value + ": " + updates[m.Groups[2].Value] + m.Groups[4].Value;
                    }
                }
                File.WriteAllLines(cfgPath, lines, Encoding.UTF8);
            }
        }

        private static List<string> ListSnapshots()
        {
            var result = new List<string>();
            string snapDir = Path.Combine(_workspaceDir, "snapshots");
            if (!Directory.Exists(snapDir)) return result;
            foreach (string file in Directory.GetFiles(snapDir, "*.json"))
            {
                result.Add(Path.GetFileName(file));
            }
            result.Sort(StringComparer.OrdinalIgnoreCase);
            result.Reverse();
            return result;
        }

        private static Dictionary<string, object> RunPowerShell(string scriptName, string extraArgs)
        {
            string scriptPath = Path.Combine(_workspaceDir, scriptName);
            if (!File.Exists(scriptPath))
            {
                return new Dictionary<string, object> { { "ok", false }, { "output", scriptName + " not found in workspace." } };
            }
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" " + extraArgs,
                WorkingDirectory = _workspaceDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process proc = Process.Start(psi))
            {
                string stdout = proc.StandardOutput.ReadToEnd();
                string stderr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(120000);
                string combined = (stdout + "\n" + stderr).Trim();
                return new Dictionary<string, object> { { "ok", proc.ExitCode == 0 }, { "output", combined } };
            }
        }

        private static void WriteHttpResponse(NetworkStream stream, int status, string contentType, byte[] body)
        {
            string statusText = status == 200 ? "OK" : "Not Found";
            string headers =
                "HTTP/1.1 " + status + " " + statusText + "\r\n" +
                "Content-Type: " + contentType + "\r\n" +
                "Content-Length: " + body.Length + "\r\n" +
                "Cache-Control: no-store\r\n" +
                "Connection: close\r\n\r\n";
            byte[] headerBytes = Encoding.ASCII.GetBytes(headers);
            stream.Write(headerBytes, 0, headerBytes.Length);
            stream.Write(body, 0, body.Length);
            stream.Flush();
        }

        private static string GetMimeType(string assetPath)
        {
            string lower = assetPath.ToLowerInvariant();
            if (lower.EndsWith(".html")) return "text/html; charset=utf-8";
            if (lower.EndsWith(".js")) return "application/javascript; charset=utf-8";
            if (lower.EndsWith(".css")) return "text/css; charset=utf-8";
            if (lower.EndsWith(".png")) return "image/png";
            if (lower.EndsWith(".ico")) return "image/x-icon";
            return "application/octet-stream";
        }
    }
}
