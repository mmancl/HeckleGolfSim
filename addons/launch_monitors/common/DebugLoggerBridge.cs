using Godot;

namespace LaunchMonitors.Common;

public static class DebugLoggerBridge
{
    public static void LogInfo(string message)
    {
        GD.Print(message);
    }

    public static void LogBluetooth(string message)
    {
        GD.Print(message);
    }

    public static void LogError(string message)
    {
        GD.PrintErr(message);
    }
}
