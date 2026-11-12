using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace MTPWPatcher
{
    public enum SiteState
    {
        Original,
        Patched,
        Unknown
    }

    public class PatchSite
    {
        public string Name;
        public long Offset;
        public byte[] Original;
        public byte[] Patched;

        public PatchSite(string name, long offset, string originalHex, string patchedHex)
        {
            Name = name;
            Offset = offset;
            Original = Hex.Parse(originalHex);
            Patched = Hex.Parse(patchedHex);
        }
    }

    public static class Hex
    {
        public static byte[] Parse(string text)
        {
            text = text.Replace(" ", "").Replace("-", "");
            byte[] result = new byte[text.Length / 2];
            for (int i = 0; i < result.Length; i++)
                result[i] = Convert.ToByte(text.Substring(i * 2, 2), 16);
            return result;
        }

        public static string Format(byte[] data, int count)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < count && i < data.Length; i++)
            {
                if (i > 0) sb.Append(' ');
                sb.Append(data[i].ToString("X2"));
            }
            return sb.ToString();
        }
    }

    public static class PatcherCore
    {
        public const long KnownSize = 8432880L;
        public const string PristineSha256 = "02ED32946FFA02F938107B9BFF233B1E063F38762A553BD209F698B4E07E650D";
        public const string FullyPatchedSha256 = "8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA";

        public static readonly PatchSite[] Sites = new PatchSite[]
        {
            new PatchSite("Desktop IsRegistered", 0x13DBA0L, "48 8B C4", "B0 01 C3"),
            new PatchSite("Desktop GetLicenseType", 0x13F8F0L, "48 8B C4 55 41 54", "B8 08 00 00 00 C3"),
            new PatchSite("WinPE IsRegistered", 0x13C860L, "40 55 53", "B0 01 C3"),
            new PatchSite("WinPE GetLicenseType", 0x13E590L, "40 55 53 57 48 8D", "B8 08 00 00 00 C3")
        };

        public static string BackupDir
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                    "MTPWPatcher", "backup");
            }
        }

        public static string OrigBackupPath
        {
            get { return Path.Combine(BackupDir, "partitionwizard.dll.orig"); }
        }

        public static string FindInstalledDll()
        {
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string direct = Path.Combine(programFiles, "MiniTool Partition Wizard 13", "partitionwizard.dll");
            if (File.Exists(direct)) return direct;

            try
            {
                string[] dirs = Directory.GetDirectories(programFiles, "MiniTool Partition Wizard*");
                foreach (string dir in dirs)
                {
                    string candidate = Path.Combine(dir, "partitionwizard.dll");
                    if (File.Exists(candidate)) return candidate;
                }
            }
            catch
            {
            }

            return null;
        }

        public static string Sha256(byte[] data)
        {
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "");
            }
        }

        public static SiteState GetState(byte[] data, PatchSite site)
        {
            if (site.Offset < 0 || site.Offset + site.Patched.Length > data.Length)
                return SiteState.Unknown;

            bool patched = true;
            for (int i = 0; i < site.Patched.Length; i++)
            {
                if (data[site.Offset + i] != site.Patched[i])
                {
                    patched = false;
                    break;
                }
            }
            if (patched) return SiteState.Patched;

            bool original = true;
            for (int i = 0; i < site.Original.Length; i++)
            {
                if (data[site.Offset + i] != site.Original[i])
                {
                    original = false;
                    break;
                }
            }
            if (original) return SiteState.Original;

            return SiteState.Unknown;
        }

        public static byte[] Slice(byte[] data, long offset, int count)
        {
            if (offset < 0 || offset + count > data.Length) return new byte[0];
            byte[] result = new byte[count];
            Buffer.BlockCopy(data, (int)offset, result, 0, count);
            return result;
        }

        public static string CheckReport(string path, byte[] data)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("File:   " + path);
            sb.AppendLine("Size:   " + data.Length.ToString("N0") + " bytes");
            sb.AppendLine("SHA256: " + Sha256(data));
            sb.AppendLine();

            bool allPatched = true;
            bool anyUnknown = false;

            foreach (PatchSite site in Sites)
            {
                SiteState state = GetState(data, site);
                if (state != SiteState.Patched) allPatched = false;
                if (state == SiteState.Unknown) anyUnknown = true;

                sb.AppendFormat("0x{0:X6}  {1,-24} {2}",
                    site.Offset, site.Name, state.ToString().ToUpperInvariant());

                if (state == SiteState.Unknown)
                    sb.Append("  first bytes: " + Hex.Format(Slice(data, site.Offset, 8), 8));

                sb.AppendLine();
            }

            sb.AppendLine();
            if (data.Length != KnownSize)
                sb.AppendLine("Unsupported size. This patcher is for 13.9, 8,432,880 bytes.");
            else if (anyUnknown)
                sb.AppendLine("Unsupported bytes. The DLL is not the known 13.9 build, or it is corrupted.");
            else if (allPatched)
                sb.AppendLine("Status: FULLY PATCHED");
            else
                sb.AppendLine("Status: READY TO PATCH");

            return sb.ToString();
        }

        public static string Apply(string path, out string log)
        {
            byte[] data = File.ReadAllBytes(path);
            if (data.Length != KnownSize)
                throw new Exception("Unsupported DLL size: " + data.Length + " bytes. Expected 8,432,880.");

            bool needPatch = false;
            foreach (PatchSite site in Sites)
            {
                SiteState state = GetState(data, site);
                if (state == SiteState.Unknown)
                {
                    throw new Exception(
                        "Unsupported bytes at " + site.Name + " (0x" + site.Offset.ToString("X6") + "). " +
                        "This patcher is for the known 13.9 build.");
                }
                if (state == SiteState.Original) needPatch = true;
            }

            if (!needPatch)
            {
                log = "All four sites are already patched. Nothing to do.\r\nSHA256: " + Sha256(data);
                return Sha256(data);
            }

            EnsureProcessClosed();
            SavePristineBackupIfNeeded(data);

            StringBuilder sb = new StringBuilder();
            foreach (PatchSite site in Sites)
            {
                SiteState state = GetState(data, site);
                if (state == SiteState.Original)
                {
                    Buffer.BlockCopy(site.Patched, 0, data, (int)site.Offset, site.Patched.Length);
                    sb.AppendLine("Patched " + site.Name + " at 0x" + site.Offset.ToString("X6"));
                }
                else
                {
                    sb.AppendLine("Already patched " + site.Name);
                }
            }

            ReplaceFile(path, data);

            byte[] after = File.ReadAllBytes(path);
            foreach (PatchSite site in Sites)
            {
                if (GetState(after, site) != SiteState.Patched)
                    throw new Exception("Verification failed at " + site.Name + ".");
            }

            sb.AppendLine();
            sb.AppendLine("Done. SHA256: " + Sha256(after));
            log = sb.ToString();
            return Sha256(after);
        }

        public static string RestoreFrom(string backupPath, string targetPath, out string log)
        {
            if (!File.Exists(backupPath))
                throw new Exception("Backup file not found: " + backupPath);

            byte[] backup = File.ReadAllBytes(backupPath);
            if (backup.Length != KnownSize || Sha256(backup) != PristineSha256)
                throw new Exception("The selected file is not the pristine 13.9 DLL.");

            EnsureProcessClosed();
            ReplaceFile(targetPath, backup);

            byte[] after = File.ReadAllBytes(targetPath);
            foreach (PatchSite site in Sites)
            {
                if (GetState(after, site) != SiteState.Original)
                    throw new Exception("Restore verification failed at " + site.Name + ".");
            }

            log = "Restored from: " + backupPath + "\r\nSHA256: " + Sha256(after);
            return Sha256(after);
        }

        public static string FindPristineBackup(string targetPath)
        {
            try
            {
                Directory.CreateDirectory(BackupDir);
            }
            catch
            {
            }

            if (IsPristine(OrigBackupPath))
                return OrigBackupPath;

            List<string> dirs = new List<string>();
            AddDir(dirs, Path.GetDirectoryName(targetPath));
            AddDir(dirs, AppDomain.CurrentDomain.BaseDirectory);

            foreach (string dir in dirs)
            {
                try
                {
                    if (!Directory.Exists(dir)) continue;
                    string[] files = Directory.GetFiles(dir, "partitionwizard.dll*", SearchOption.AllDirectories);
                    foreach (string file in files)
                    {
                        if (IsPristine(file))
                        {
                            try
                            {
                                File.Copy(file, OrigBackupPath, true);
                            }
                            catch
                            {
                            }
                            return file;
                        }
                    }
                }
                catch
                {
                }
            }

            return null;
        }

        private static void AddDir(List<string> dirs, string dir)
        {
            if (string.IsNullOrEmpty(dir)) return;
            foreach (string existing in dirs)
            {
                if (string.Equals(existing, dir, StringComparison.OrdinalIgnoreCase))
                    return;
            }
            dirs.Add(dir);
        }

        private static bool IsPristine(string path)
        {
            try
            {
                if (!File.Exists(path)) return false;
                FileInfo info = new FileInfo(path);
                if (info.Length != KnownSize) return false;
                return Sha256(File.ReadAllBytes(path)) == PristineSha256;
            }
            catch
            {
                return false;
            }
        }

        private static void SavePristineBackupIfNeeded(byte[] data)
        {
            bool allOriginal = true;
            foreach (PatchSite site in Sites)
            {
                if (GetState(data, site) != SiteState.Original)
                {
                    allOriginal = false;
                    break;
                }
            }

            if (!allOriginal) return;

            try
            {
                Directory.CreateDirectory(BackupDir);
                if (!IsPristine(OrigBackupPath))
                    File.WriteAllBytes(OrigBackupPath, data);
            }
            catch
            {
            }
        }

        private static void EnsureProcessClosed()
        {
            Process[] running = Process.GetProcessesByName("partitionwizard");
            if (running.Length > 0)
                throw new Exception("Close MiniTool Partition Wizard first. It is currently running.");
        }

        private static void ReplaceFile(string path, byte[] data)
        {
            try
            {
                File.SetAttributes(path, FileAttributes.Normal);
            }
            catch
            {
            }

            string temp = path + ".mtpw_new";
            File.WriteAllBytes(temp, data);

            try
            {
                File.Replace(temp, path, null);
            }
            catch
            {
                File.Copy(temp, path, true);
                try
                {
                    File.Delete(temp);
                }
                catch
                {
                }
            }
        }
    }
}
