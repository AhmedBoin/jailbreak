using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("MiniTool Partition Wizard 13.9 Patcher")]
[assembly: AssemblyDescription("Applies the four 13.9 license patches")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace MTPWPatcher
{
    public class MainForm : Form
    {
        private string dllPath;
        private Label lblTitle;
        private Label lblPath;
        private Label lblFooter;
        private TextBox txtLog;
        private Button btnBrowse;
        private Button btnCheck;
        private Button btnApply;
        private Button btnRestore;
        private Button btnExit;

        public MainForm()
        {
            Text = "MiniTool Partition Wizard 13.9 Patcher";
            ClientSize = new Size(724, 520);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Segoe UI", 9F);

            lblTitle = new Label();
            lblTitle.Text = "MiniTool Partition Wizard 13.9 Patcher";
            lblTitle.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
            lblTitle.AutoSize = true;
            lblTitle.Location = new Point(12, 9);
            Controls.Add(lblTitle);

            lblPath = new Label();
            lblPath.Text = "Looking for partitionwizard.dll...";
            lblPath.AutoEllipsis = true;
            lblPath.Location = new Point(12, 42);
            lblPath.Size = new Size(596, 20);
            Controls.Add(lblPath);

            btnBrowse = new Button();
            btnBrowse.Text = "Browse...";
            btnBrowse.Location = new Point(616, 38);
            btnBrowse.Size = new Size(96, 27);
            btnBrowse.Click += new EventHandler(btnBrowse_Click);
            Controls.Add(btnBrowse);

            txtLog = new TextBox();
            txtLog.Location = new Point(12, 72);
            txtLog.Size = new Size(700, 368);
            txtLog.Multiline = true;
            txtLog.ReadOnly = true;
            txtLog.WordWrap = false;
            txtLog.ScrollBars = ScrollBars.Both;
            txtLog.Font = new Font("Consolas", 9F);
            txtLog.BackColor = Color.White;
            Controls.Add(txtLog);

            btnCheck = new Button();
            btnCheck.Text = "Check";
            btnCheck.Location = new Point(12, 452);
            btnCheck.Size = new Size(90, 30);
            btnCheck.Click += new EventHandler(btnCheck_Click);
            Controls.Add(btnCheck);

            btnApply = new Button();
            btnApply.Text = "Apply 4 Patches";
            btnApply.Location = new Point(110, 452);
            btnApply.Size = new Size(150, 30);
            btnApply.Click += new EventHandler(btnApply_Click);
            Controls.Add(btnApply);

            btnRestore = new Button();
            btnRestore.Text = "Restore Original";
            btnRestore.Location = new Point(268, 452);
            btnRestore.Size = new Size(130, 30);
            btnRestore.Click += new EventHandler(btnRestore_Click);
            Controls.Add(btnRestore);

            btnExit = new Button();
            btnExit.Text = "Exit";
            btnExit.Location = new Point(612, 452);
            btnExit.Size = new Size(100, 30);
            btnExit.Click += new EventHandler(btnExit_Click);
            Controls.Add(btnExit);

            lblFooter = new Label();
            lblFooter.Text = "13.9 build only. Close MiniTool Partition Wizard before patching. Rebuild the bootable media after patching.";
            lblFooter.AutoSize = false;
            lblFooter.Location = new Point(12, 492);
            lblFooter.Size = new Size(700, 18);
            lblFooter.ForeColor = Color.Gray;
            lblFooter.Font = new Font("Segoe UI", 8.25F);
            Controls.Add(lblFooter);

            dllPath = PatcherCore.FindInstalledDll();
            CheckDll();
        }

        private void CheckDll()
        {
            if (string.IsNullOrEmpty(dllPath))
            {
                lblPath.Text = "partitionwizard.dll not found. Use Browse...";
                txtLog.Text = "MiniTool Partition Wizard 13.9 was not found in Program Files.\r\n\r\n" +
                    "Use Browse... to select partitionwizard.dll manually.";
                return;
            }

            lblPath.Text = dllPath;

            try
            {
                if (!File.Exists(dllPath))
                {
                    txtLog.Text = "File not found:\r\n" + dllPath;
                    return;
                }

                byte[] data = File.ReadAllBytes(dllPath);
                txtLog.Text = PatcherCore.CheckReport(dllPath, data);
            }
            catch (Exception ex)
            {
                txtLog.Text = "Error:\r\n" + ex.Message;
            }
        }

        private void btnBrowse_Click(object sender, EventArgs e)
        {
            using (OpenFileDialog dialog = new OpenFileDialog())
            {
                dialog.Title = "Select partitionwizard.dll";
                dialog.Filter = "partitionwizard.dll|partitionwizard.dll|DLL files (*.dll)|*.dll";
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    dllPath = dialog.FileName;
                    CheckDll();
                }
            }
        }

        private void btnCheck_Click(object sender, EventArgs e)
        {
            CheckDll();
        }

        private void btnApply_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(dllPath) || !File.Exists(dllPath))
            {
                MessageBox.Show(this, "Select partitionwizard.dll first.", "Patcher",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                string log;
                PatcherCore.Apply(dllPath, out log);
                txtLog.Text = log;
                MessageBox.Show(this,
                    "The four patches were applied and verified.\r\n\r\n" +
                    "If you use the bootable media, rebuild it now so the new DLL is embedded.",
                    "Patcher", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Patch failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            CheckDll();
        }

        private void btnRestore_Click(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(dllPath) || !File.Exists(dllPath))
            {
                MessageBox.Show(this, "Select partitionwizard.dll first.", "Patcher",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            DialogResult answer = MessageBox.Show(this,
                "Restore the pristine 13.9 DLL? This removes all four patches.",
                "Restore", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;

            string backup = PatcherCore.FindPristineBackup(dllPath);
            if (backup == null)
            {
                using (OpenFileDialog dialog = new OpenFileDialog())
                {
                    dialog.Title = "Select the pristine partitionwizard.dll backup";
                    dialog.Filter = "partitionwizard.dll|partitionwizard.dll|DLL files (*.dll)|*.dll";
                    if (dialog.ShowDialog(this) != DialogResult.OK) return;
                    backup = dialog.FileName;
                }
            }

            try
            {
                string log;
                PatcherCore.RestoreFrom(backup, dllPath, out log);
                txtLog.Text = log;
                MessageBox.Show(this, "Restore completed.", "Patcher",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Restore failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            CheckDll();
        }

        private void btnExit_Click(object sender, EventArgs e)
        {
            Close();
        }

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
