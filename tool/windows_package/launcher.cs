// Запускатель фоновых процессов для Windows (задача 5.7.1, ADR-011).
//
// `dart build cli` собирает консольные программы: когда задание
// Планировщика запускает их в сеансе пользователя, Windows создаёт окно
// консоли, и оно висит всё время работы агента бэкапа и хранителя. Этот
// файл собирается подсистемой WINDOWS (`/target:winexe`), поэтому окна у
// самого запускателя нет. Он запускает программу службы с
// CREATE_NO_WINDOW — окна нет, а stdin/stdout/stderr уходят в каналы
// запускателя (демоны пишут в stderr и журнал).
//
// Запускатель ждёт дочерний процесс и возвращает его код, поэтому задание
// Планировщика «работает», пока работает демон, а `schtasks /End`
// завершает задание вместе с ним. Дочерний процесс помещается в job
// object с JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: если запускатель завершат,
// дочерний процесс тоже завершится.
//
// Сборка — tool/windows_package/build.ps1 (csc.exe из .NET Framework,
// входит в Windows 10/11). Синтаксис — C# 5: компилятор в составе
// .NET Framework не знает более новых версий.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class QuietLauncher
{
    private const int JobObjectExtendedLimitInformation = 9;
    private const uint JobObjectLimitKillOnJobClose = 0x2000;

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation64
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr job,
        int infoClass,
        ref JobObjectExtendedLimitInformation64 info,
        uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            return 64;
        }

        string target = args[0];
        var childArgs = new StringBuilder();
        for (int i = 1; i < args.Length; i++)
        {
            if (i > 1)
            {
                childArgs.Append(' ');
            }
            childArgs.Append(Quote(args[i]));
        }

        var startInfo = new ProcessStartInfo();
        startInfo.FileName = target;
        startInfo.Arguments = childArgs.ToString();
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        // Потоки демона — в каналы запускателя: так у него всегда есть
        // рабочие stdin/stdout/stderr (демоны пишут в stderr при ошибках и
        // с `--log -`), а консоль не создаётся вовсе. Вывод никуда не
        // пишется, читатели только не дают каналу заполниться.
        startInfo.RedirectStandardInput = true;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        string workingDirectory = Path.GetDirectoryName(target);
        if (!string.IsNullOrEmpty(workingDirectory))
        {
            startInfo.WorkingDirectory = workingDirectory;
        }

        IntPtr job = CreateKillOnCloseJob();
        Process child;
        try
        {
            child = Process.Start(startInfo);
        }
        catch (Exception)
        {
            if (job != IntPtr.Zero)
            {
                CloseHandle(job);
            }
            return 1;
        }
        if (child == null)
        {
            if (job != IntPtr.Zero)
            {
                CloseHandle(job);
            }
            return 1;
        }

        try
        {
            child.StandardInput.Close();
            child.OutputDataReceived += delegate { };
            child.ErrorDataReceived += delegate { };
            child.BeginOutputReadLine();
            child.BeginErrorReadLine();
        }
        catch (Exception)
        {
            // Процесс уже завершился — читать нечего.
        }

        if (job != IntPtr.Zero)
        {
            try
            {
                // Не ошибка: дочерний процесс уже может быть в job задания
                // Планировщика, а вложенные job object есть с Windows 8.
                AssignProcessToJobObject(job, child.Handle);
            }
            catch (Exception)
            {
                // Процесс уже завершился — job всё равно закроется ниже.
            }
        }

        child.WaitForExit();
        int exitCode = child.ExitCode;
        child.Dispose();
        if (job != IntPtr.Zero)
        {
            CloseHandle(job);
        }
        return exitCode;
    }

    private static IntPtr CreateKillOnCloseJob()
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
        {
            return IntPtr.Zero;
        }
        var info = new JobObjectExtendedLimitInformation64();
        info.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
        bool ok = SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            ref info,
            (uint)Marshal.SizeOf(typeof(JobObjectExtendedLimitInformation64)));
        if (!ok)
        {
            CloseHandle(job);
            return IntPtr.Zero;
        }
        return job;
    }

    // Аргумент командной строки Windows: кавычки вокруг аргументов с
    // пробелами и кавычками, обратная косая черта перед кавычкой
    // удваивается (правила CommandLineToArgvW).
    private static string Quote(string arg)
    {
        if (arg.Length == 0)
        {
            return "\"\"";
        }
        bool needsQuotes = false;
        foreach (char c in arg)
        {
            if (c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '"')
            {
                needsQuotes = true;
                break;
            }
        }
        if (!needsQuotes)
        {
            return arg;
        }

        var result = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                result.Append('\\', backslashes * 2 + 1);
                result.Append('"');
                backslashes = 0;
                continue;
            }
            result.Append('\\', backslashes);
            result.Append(c);
            backslashes = 0;
        }
        result.Append('\\', backslashes * 2);
        result.Append('"');
        return result.ToString();
    }
}
