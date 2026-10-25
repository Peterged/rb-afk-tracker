using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

class Program {
    [STAThread]
    static int Main(string[] args) {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDir, "RobloxAfkMonitor.ahk");
        if (!File.Exists(scriptPath)) {
            MessageBox.Show("Could not find RobloxAfkMonitor.ahk in:\n" + baseDir,
                "Roblox AFK Monitor", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // Priority 1: Bundled standalone runtime in bin\AutoHotkey64.exe (no AHK installation needed)
        // Priority 2: Standard per-machine or per-user AutoHotkey v2 installation
        string[] candidates = new string[] {
            Path.Combine(baseDir, @"bin\AutoHotkey64.exe"),
            @"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
            @"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\AutoHotkey\v2\AutoHotkey64.exe")
        };

        string ahkExe = null;
        foreach (string c in candidates) {
            if (File.Exists(c)) {
                ahkExe = c;
                break;
            }
        }

        if (ahkExe == null) {
            MessageBox.Show("AutoHotkey v2 runtime was not found in bin\\AutoHotkey64.exe or C:\\Program Files\\AutoHotkey\\v2.",
                "Roblox AFK Monitor", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        string argStr = "\"" + scriptPath + "\"";
        foreach (string a in args) {
            argStr += " \"" + a.Replace("\"", "\\\"") + "\"";
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = ahkExe;
        psi.Arguments = argStr;
        psi.WorkingDirectory = baseDir;
        psi.UseShellExecute = false;
        Process.Start(psi);
        return 0;
    }
}
