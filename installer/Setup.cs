using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

class SetupProgram {
    [STAThread]
    static int Main(string[] args) {
        bool silent = false;
        bool noLaunch = false;
        string customDir = null;
        string defaultRepo = null;

        foreach (string a in args) {
            if (a.Equals("--silent", StringComparison.OrdinalIgnoreCase) || a.Equals("/S", StringComparison.OrdinalIgnoreCase))
                silent = true;
            else if (a.Equals("--no-launch", StringComparison.OrdinalIgnoreCase))
                noLaunch = true;
            else if (a.StartsWith("--install-dir=", StringComparison.OrdinalIgnoreCase))
                customDir = a.Substring("--install-dir=".Length).Trim('"');
            else if (a.StartsWith("--repo=", StringComparison.OrdinalIgnoreCase))
                defaultRepo = a.Substring("--repo=".Length).Trim('"');
        }

        string installDir = customDir;
        if (string.IsNullOrEmpty(installDir)) {
            installDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                @"Programs\RobloxAfkMonitor"
            );
        }

        try {
            // Stop any running instance inside the target installDir before overwriting binaries
            StopRunningInstances(installDir);

            if (!Directory.Exists(installDir))
                Directory.CreateDirectory(installDir);

            // Preserve user's existing settings.ini and state.ini across reinstalls
            string settingsPath = Path.Combine(installDir, "settings.ini");
            string statePath = Path.Combine(installDir, "state.ini");
            byte[] savedSettings = File.Exists(settingsPath) ? File.ReadAllBytes(settingsPath) : null;
            byte[] savedState = File.Exists(statePath) ? File.ReadAllBytes(statePath) : null;

            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream res = asm.GetManifestResourceStream("payload.zip")) {
                if (res == null)
                    throw new Exception("Embedded payload.zip resource is missing.");

                using (ZipArchive archive = new ZipArchive(res, ZipArchiveMode.Read)) {
                    foreach (ZipArchiveEntry entry in archive.Entries) {
                        if (string.IsNullOrEmpty(entry.Name))
                            continue;
                        string destPath = Path.Combine(installDir, entry.FullName.Replace('/', '\\'));
                        string parent = Path.GetDirectoryName(destPath);
                        if (!string.IsNullOrEmpty(parent) && !Directory.Exists(parent))
                            Directory.CreateDirectory(parent);
                        entry.ExtractToFile(destPath, true);
                    }
                }
            }

            if (savedSettings != null)
                File.WriteAllBytes(settingsPath, savedSettings);
            if (savedState != null)
                File.WriteAllBytes(statePath, savedState);

            string exePath = Path.Combine(installDir, "RobloxAfkMonitor.exe");

            // Create Desktop and Start Menu shortcuts (unless custom test dir in --silent mode)
            if (string.IsNullOrEmpty(customDir)) {
                string desktopLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Roblox AFK Monitor.lnk");
                string startMenuLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Roblox AFK Monitor.lnk");
                CreateShortcut(desktopLnk, exePath, installDir, "Roblox Multi-Instance AFK Monitor");
                CreateShortcut(startMenuLnk, exePath, installDir, "Roblox Multi-Instance AFK Monitor");
            }

            WriteUninstaller(installDir);

            if (!noLaunch && File.Exists(exePath)) {
                ProcessStartInfo psi = new ProcessStartInfo(exePath);
                psi.WorkingDirectory = installDir;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }

            if (!silent) {
                MessageBox.Show(
                    "Roblox AFK Monitor has been installed to:\n" + installDir + "\n\n" +
                    "• Desktop & Start Menu shortcuts created ('Roblox AFK Monitor')\n" +
                    "• Bundled AutoHotkey v2 runtime included (no extra installs needed)\n" +
                    "• Automatic updates enabled\n\n" +
                    (noLaunch ? "" : "Roblox AFK Monitor is now running in your system tray!"),
                    "Roblox AFK Monitor Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information
                );
            }
            return 0;
        } catch (Exception ex) {
            if (!silent) {
                MessageBox.Show("Installation failed:\n" + ex.Message,
                    "Roblox AFK Monitor Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            } else {
                Console.Error.WriteLine(ex.ToString());
            }
            return 1;
        }
    }

    static void StopRunningInstances(string installDir) {
        try {
            string normDir = Path.GetFullPath(installDir).TrimEnd('\\').ToLowerInvariant();
            foreach (Process p in Process.GetProcessesByName("AutoHotkey64")) {
                try {
                    string path = p.MainModule.FileName.ToLowerInvariant();
                    if (path.StartsWith(normDir)) {
                        p.Kill();
                        p.WaitForExit(2000);
                    }
                } catch { }
            }
        } catch { }
    }

    static void CreateShortcut(string lnkPath, string targetPath, string workDir, string description) {
        try {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(shellType);
            dynamic shortcut = shell.CreateShortcut(lnkPath);
            shortcut.TargetPath = targetPath;
            shortcut.WorkingDirectory = workDir;
            shortcut.Description = description;
            shortcut.Save();
        } catch { }
    }

    static void WriteUninstaller(string installDir) {
        string batPath = Path.Combine(installDir, "Uninstall.bat");
        string content =
            "@echo off\r\n" +
            "echo Uninstalling Roblox AFK Monitor...\r\n" +
            "taskkill /F /IM AutoHotkey64.exe >nul 2>&1\r\n" +
            "del /F /Q \"%USERPROFILE%\\Desktop\\Roblox AFK Monitor.lnk\" >nul 2>&1\r\n" +
            "del /F /Q \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Roblox AFK Monitor.lnk\" >nul 2>&1\r\n" +
            "del /F /Q \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\Roblox AFK Monitor.lnk\" >nul 2>&1\r\n" +
            "cd /d \"%TEMP%\"\r\n" +
            "rmdir /S /Q \"" + installDir + "\"\r\n" +
            "echo Done.\r\n";
        File.WriteAllText(batPath, content);
    }
}
