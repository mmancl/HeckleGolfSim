using Godot;

namespace LaunchMonitors.Common;

public static class DebugLoggerBridge
{
    private static Node? _loggerNode;

    private static Node? GetLoggerNode()
    {
        if (_loggerNode != null && GodotObject.IsInstanceValid(_loggerNode))
        {
            return _loggerNode;
        }

        if (Engine.GetMainLoop() is SceneTree tree && tree.Root != null)
        {
            _loggerNode = tree.Root.GetNodeOrNull("DebugLogger");
            return _loggerNode;
        }
        return null;
    }

    public static void LogInfo(string message)
    {
        GD.Print(message);
        GetLoggerNode()?.Call("log_info", message);
    }

    public static void LogBluetooth(string message)
    {
        GD.Print(message);
        GetLoggerNode()?.Call("log_bluetooth", message);
    }

    public static void LogError(string message)
    {
        GD.PrintErr(message);
        GetLoggerNode()?.Call("log_error", message);
    }
}
