using System;

namespace LaunchMonitors.Common.Bluetooth;

public static class BluetoothDeviceFilter
{
    public static bool IsDeviceNameMatch(string? name, string? prefix)
    {
        if (string.IsNullOrWhiteSpace(prefix))
        {
            return true;
        }

        if (string.IsNullOrWhiteSpace(name) || string.Equals(name.Trim(), "Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var trimmedName = name.Trim();
        if (trimmedName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ||
            trimmedName.Contains(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var normalizedName = trimmedName.Replace(" ", "").Replace("-", "").Replace("_", "");
        var normalizedPrefix = prefix.Replace(" ", "").Replace("-", "").Replace("_", "");
        if (normalizedName.StartsWith(normalizedPrefix, StringComparison.OrdinalIgnoreCase) ||
            normalizedName.Contains(normalizedPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        // Special handling for Square Golf:
        // Square Golf devices may advertise as "SquareGolf", "Square Golf", "SquareGolf_xxxx",
        // or model codes starting with "SGO" (e.g. "SGO300A", "SGO300", "SGO-300", "SGO_300").
        if (normalizedPrefix.Contains("square", StringComparison.OrdinalIgnoreCase) &&
            (normalizedName.Contains("square", StringComparison.OrdinalIgnoreCase) ||
             normalizedName.StartsWith("sgo", StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        // Special handling for Garmin Approach:
        // Approach devices may advertise as "Approach R10", "Garmin Approach", or "R10 [xxxx]".
        if ((normalizedPrefix.Contains("approach", StringComparison.OrdinalIgnoreCase) ||
             normalizedPrefix.Contains("garmin", StringComparison.OrdinalIgnoreCase)) &&
            (normalizedName.Contains("approach", StringComparison.OrdinalIgnoreCase) ||
             normalizedName.Contains("garmin", StringComparison.OrdinalIgnoreCase) ||
             normalizedName.Contains("r10", StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        return false;
    }
}
