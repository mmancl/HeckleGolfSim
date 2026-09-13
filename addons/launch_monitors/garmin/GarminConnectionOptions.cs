using System;

namespace LaunchMonitors.Garmin;

internal sealed record GarminConnectionOptions(
    string DeviceNamePrefix = "Approach",
    TimeSpan ConnectionTimeout = default,
    TimeSpan HandshakeTimeout = default,
    bool AutoWake = true,
    bool CalibrateTiltOnConnect = false,
    float TemperatureF = 68.0f,
    float AltitudeFt = 0.0f,
    float TeeDistanceFt = 7.0f,
    float Humidity = 1.0f)
{
    public static GarminConnectionOptions Default { get; } = new(
        ConnectionTimeout: TimeSpan.FromSeconds(15),
        HandshakeTimeout: TimeSpan.FromSeconds(10));
}
