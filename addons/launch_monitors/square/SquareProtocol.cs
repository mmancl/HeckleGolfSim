using System;
using System.Buffers.Binary;

namespace LaunchMonitors.Square;

public static class SquareProtocol
{
    public static bool IsSensorPacket(ReadOnlySpan<byte> data)
    {
        return data.Length >= 17 && data[0] == 0x11 && data[1] == 0x01;
    }

    public static bool IsShotPacket(ReadOnlySpan<byte> data)
    {
        return data.Length >= 17 && data[0] == 0x11 && data[1] == 0x02;
    }

    public static bool TryParseSensor(ReadOnlySpan<byte> data, out SquareSensorData sensor)
    {
        sensor = default;
        if (!IsSensorPacket(data))
        {
            return false;
        }

        var posX = BinaryPrimitives.ReadInt32LittleEndian(data[5..9]);
        var posY = BinaryPrimitives.ReadInt32LittleEndian(data[9..13]);
        var posZ = BinaryPrimitives.ReadInt32LittleEndian(data[13..17]);
        var ballDetected = data[2] != 0x00 || data[4] != 0x00 || posX != 0 || posY != 0 || posZ != 0;
        var ballReady = data[3] != 0x00 && ballDetected;

        sensor = new SquareSensorData(
            ballReady,
            ballDetected,
            posX,
            posY,
            posZ);

        return true;
    }

    public static bool TryParseShot(ReadOnlySpan<byte> data, out SquareShotMetrics metrics)
    {
        metrics = default;
        if (!IsShotPacket(data))
        {
            return false;
        }

        var rawSpeed = BinaryPrimitives.ReadInt16LittleEndian(data[3..5]);
        var rawVla = BinaryPrimitives.ReadInt16LittleEndian(data[5..7]);
        var rawHla = BinaryPrimitives.ReadInt16LittleEndian(data[7..9]);
        var rawTotalSpin = BinaryPrimitives.ReadInt16LittleEndian(data[9..11]);
        var rawSpinAxis = BinaryPrimitives.ReadInt16LittleEndian(data[11..13]);
        var rawBackSpin = BinaryPrimitives.ReadInt16LittleEndian(data[13..15]);
        var rawSideSpin = BinaryPrimitives.ReadInt16LittleEndian(data[15..17]);

        var speedDivisor = 100.0f;
        var speed = rawSpeed == -32768 ? 0.0f : rawSpeed / speedDivisor;
        var vla = rawVla == -32768 ? 0.0f : rawVla / 100.0f;
        var hla = rawHla == -32768 ? 0.0f : rawHla / 100.0f;
        var totalSpin = rawTotalSpin == -32768 ? 0 : (int)rawTotalSpin;
        var spinAxis = rawSpinAxis == -32768 ? 0.0f : rawSpinAxis / -100.0f;
        var backSpin = rawBackSpin == -32768 ? 0 : (int)rawBackSpin;
        var sideSpin = rawSideSpin == -32768 ? 0 : (int)rawSideSpin;

        var shotType = data[2] switch
        {
            0x37 => "full",
            0x13 => speed > 20.0f ? "full" : "putt",
            _ => "unknown"
        };

        metrics = new SquareShotMetrics(
            speed,
            vla,
            hla,
            totalSpin,
            spinAxis,
            backSpin,
            sideSpin,
            shotType);

        return IsPlausible(metrics);
    }

    private static bool IsPlausible(SquareShotMetrics metrics)
    {
        var isPutt = metrics.ShotType == "putt";
        return metrics.BallSpeedMps > 0
            && metrics.BallSpeedMps < 250
            && metrics.TotalSpinRpm >= 0
            && metrics.TotalSpinRpm < 30_000
            && (isPutt ? metrics.VerticalAngle >= -15.0f : metrics.VerticalAngle >= 0);
    }
}
