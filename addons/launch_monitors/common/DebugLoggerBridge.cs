using System;
using Godot;

namespace LaunchMonitors.Common;

public static class DebugLoggerBridge
{
    public static void LogInfo(string message)
    {
        GD.Print(message);
        CallDebugLogger("log_info", message);
    }

    public static void LogBluetooth(string message)
    {
        GD.Print(message);
        CallDebugLogger("log_bluetooth", message);
    }

    public static void LogError(string message)
    {
        GD.PrintErr(message);
        CallDebugLogger("log_error", message);
    }

    private static void CallDebugLogger(string method, string message)
    {
        try
        {
            if (Engine.GetMainLoop() is SceneTree tree && tree.Root != null)
            {
                var logger = tree.Root.GetNodeOrNull("DebugLogger");
                if (logger != null && logger.HasMethod(method))
                {
                    logger.Call(method, message);
                }
            }
        }
        catch
        {
        }
    }
}
