using System;

namespace LaunchMonitors.R10;

internal sealed record R10ConnectionOptions(
    string DeviceNamePrefix,
    Guid BatteryCharacteristicUuid,
    Guid FirmwareCharacteristicUuid,
    Guid ModelCharacteristicUuid,
    Guid MeasurementCharacteristicUuid,
    Guid ControlCharacteristicUuid,
    Guid StatusCharacteristicUuid,
    int ServiceDiscoveryMaxAttempts,
    TimeSpan ServiceDiscoveryRetryDelay,
TimeSpan HeartbeatInterval,
bool EnableDiagnostics = false)
{
    public static R10ConnectionOptions Default { get; } = new(
    DeviceNamePrefix: "Approach R10",
    BatteryCharacteristicUuid: Guid.Parse("00002a19-0000-1000-8000-00805f9b34fb"),
    FirmwareCharacteristicUuid: Guid.Parse("00002a28-0000-1000-8000-00805f9b34fb"),
    ModelCharacteristicUuid: Guid.Parse("00002a24-0000-1000-8000-00805f9b34fb"),
    MeasurementCharacteristicUuid: Guid.Parse("6A4E3401-667B-11E3-949A-0800200C9A66"),
    ControlCharacteristicUuid: Guid.Parse("6A4E3402-667B-11E3-949A-0800200C9A66"),
    StatusCharacteristicUuid: Guid.Parse("6A4E3403-667B-11E3-949A-0800200C9A66"),
    ServiceDiscoveryMaxAttempts: 8,
    ServiceDiscoveryRetryDelay: TimeSpan.FromSeconds(1),
    HeartbeatInterval: TimeSpan.FromSeconds(5),
    EnableDiagnostics: true);
}
