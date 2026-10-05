using System;
using System.Globalization;

namespace LaunchMonitors.Square;

public static class SquareCommandBuilder
{
    public const string DriverClubCode = "0204";

    public static byte[] Heartbeat(byte sequence)
    {
        return FromHex($"1183{sequence:X2}0000000000");
    }

    public static byte[] DetectBall(byte sequence, int mode = 1, int spinMode = 1)
    {
        // Byte 4 is the ball spin tracking mode:
        // 0x11 = Dotted / marked ball mode (hardware enables camera dot tracking for real spin axis and sidespin measurement)
        // 0x01 = Unmarked ball mode (hardware uses estimated spin with 0 spin axis)
        var spinHex = spinMode == 0 ? "01" : "11";
        return FromHex($"1181{sequence:X2}0{mode}{spinHex}00000000");
    }

    public static byte[] Club(byte sequence, string clubCode, int handedness)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(clubCode);
        return FromHex($"1182{sequence:X2}{clubCode}0{handedness}000000");
    }

    public static byte[] FromHex(string hex)
    {
        if (hex.Length % 2 != 0)
        {
            throw new ArgumentException("Hex values must have an even number of characters.", nameof(hex));
        }

        var bytes = new byte[hex.Length / 2];
        for (var i = 0; i < bytes.Length; i++)
        {
            bytes[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }

        return bytes;
    }
}
