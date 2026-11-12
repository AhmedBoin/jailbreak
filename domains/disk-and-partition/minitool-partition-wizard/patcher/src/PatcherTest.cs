using System;
using System.IO;
using MTPWPatcher;

public static class PatcherTest
{
    public static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("usage: PatcherTest check|apply|restore <dll> [backup]");
            return 2;
        }

        string command = args[0].ToLowerInvariant();
        string path = args[1];

        try
        {
            if (command == "check")
            {
                Console.WriteLine(PatcherCore.CheckReport(path, File.ReadAllBytes(path)));
                return 0;
            }

            if (command == "apply")
            {
                string log;
                string hash = PatcherCore.Apply(path, out log);
                Console.WriteLine(log);
                Console.WriteLine("RESULT_HASH " + hash);
                return 0;
            }

            if (command == "restore")
            {
                if (args.Length < 3)
                {
                    Console.WriteLine("restore needs a backup path");
                    return 2;
                }
                string log;
                string hash = PatcherCore.RestoreFrom(args[2], path, out log);
                Console.WriteLine(log);
                Console.WriteLine("RESULT_HASH " + hash);
                return 0;
            }

            Console.WriteLine("unknown command");
            return 2;
        }
        catch (Exception ex)
        {
            Console.WriteLine("ERROR: " + ex.Message);
            return 1;
        }
    }
}
