using System;
using System.Threading.Tasks;
using Godot;
using LaunchMonitors.Common.Bluetooth;
using GodotDictionary = Godot.Collections.Dictionary;

namespace LaunchMonitors.R10;

[GlobalClass]
public partial class R10LaunchMonitor : Node
{
    private const string LogPrefix = "[R10LaunchMonitor]";

    private readonly R10ConnectionSession _session = new(
        BluetoothGattClientFactory.Create(),
        logInfo: LogInfo,
        logError: LogError);

    [Signal]
    public delegate void DeviceDiscoveredEventHandler(string deviceId, string name, int rssi);

    [Signal]
    public delegate void StatusChangedEventHandler(string status);

    [Signal]
    public delegate void ErrorOccurredEventHandler(string message);

    [Signal]
    public delegate void BatteryChangedEventHandler(int level);

    [Signal]
    public delegate void FirmwareChangedEventHandler(string firmware);

    [Signal]
    public delegate void ReadyChangedEventHandler(bool isReady);

    [Signal]
    public delegate void SensorDataReceivedEventHandler(int posX, int posY, int posZ, bool isReady, bool isDetected);

    [Signal]
    public delegate void ShotReceivedEventHandler(GodotDictionary shotData);

    public override void _Ready()
    {
        _session.DeviceDiscovered += OnDeviceDiscovered;
        _session.StatusChanged += EmitStatus;
        _session.ErrorOccurred += EmitError;
        _session.BatteryChanged += EmitBattery;
        _session.FirmwareChanged += EmitFirmware;
        _session.ReadyChanged += EmitReady;
        _session.SensorDataReceived += OnSensorDataReceived;
        _session.ShotReceived += OnShotReceived;
        LogInfo("Node ready.");
    }

    public override void _ExitTree()
    {
        _session.DeviceDiscovered -= OnDeviceDiscovered;
        _session.StatusChanged -= EmitStatus;
        _session.ErrorOccurred -= EmitError;
        _session.BatteryChanged -= EmitBattery;
        _session.FirmwareChanged -= EmitFirmware;
        _session.ReadyChanged -= EmitReady;
        _session.SensorDataReceived -= OnSensorDataReceived;
        _session.ShotReceived -= OnShotReceived;
        _ = _session.DisposeAsync();
    }

    public void StartScan()
    {
        _ = RunAsync(() => _session.StartScanAsync());
    }

    public void StopScan()
    {
        _ = RunAsync(() => _session.StopScanAsync());
    }

    public void ConnectToDevice(string deviceId)
    {
        LogInfo($"ConnectToDevice requested for deviceId={deviceId}");
        _ = RunAsync(() => _session.ConnectToDeviceAsync(deviceId));
    }

    public void DisconnectFromDevice()
    {
        _ = RunAsync(() => _session.DisconnectAsync());
    }

    public void SetReady()
    {
        _ = RunAsync(() => _session.SetReadyAsync());
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        EmitDeviceDiscovered(device.DeviceId, device.Name, device.Rssi);
    }

    private void OnShotReceived(R10ShotMetrics metrics)
    {
        EmitShot(ToBallData(metrics));
    }

    private void OnSensorDataReceived(R10SensorData sensor)
    {
        CallDeferred("emit_signal", SignalName.SensorDataReceived, sensor.PositionX, sensor.PositionY, sensor.PositionZ, sensor.BallReady, sensor.BallDetected);
    }

    private static GodotDictionary ToBallData(R10ShotMetrics metrics)
    {
        var result = new GodotDictionary
        {
            ["Speed"] = metrics.BallSpeedMps * 2.23694f,
            ["VLA"] = metrics.VerticalAngle,
            ["HLA"] = metrics.HorizontalAngle,
            ["TotalSpin"] = Math.Max(0, metrics.TotalSpinRpm),
            ["SpinAxis"] = metrics.SpinAxis,
            ["BackSpin"] = Math.Max(0, metrics.BackSpinRpm),
            ["SideSpin"] = Math.Max(0, metrics.SideSpinRpm),
            ["ShotType"] = metrics.ShotType,
            ["ClubPath"] = metrics.ClubPath,
            ["FaceAngle"] = metrics.FaceAngle,
            ["AttackAngle"] = metrics.AttackAngle,
            ["DynamicLoft"] = metrics.DynamicLoft,
            ["ClubSpeed"] = metrics.ClubSpeedMps * 2.23694f,
            ["SmashFactor"] = metrics.SmashFactor > 0.0f ? metrics.SmashFactor : 1.45f,
            ["FaceToPath"] = metrics.FaceAngle - metrics.ClubPath
        };
        return result;
    }

    private async Task RunAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            EmitError(ex.Message);
            LogError($"RunAsync failed: {ex}");
        }
    }

    private void EmitDeviceDiscovered(string deviceId, string name, int rssi)
    {
        CallDeferred("emit_signal", SignalName.DeviceDiscovered, deviceId, name, rssi);
    }

    private void EmitStatus(string status)
    {
        CallDeferred("emit_signal", SignalName.StatusChanged, status);
    }

    private void EmitError(string message)
    {
        CallDeferred("emit_signal", SignalName.ErrorOccurred, message);
    }

    private void EmitBattery(int level)
    {
        CallDeferred("emit_signal", SignalName.BatteryChanged, level);
    }

    private void EmitFirmware(string firmware)
    {
        CallDeferred("emit_signal", SignalName.FirmwareChanged, firmware);
    }

    private void EmitReady(bool ready)
    {
        CallDeferred("emit_signal", SignalName.ReadyChanged, ready);
    }

    private void EmitShot(GodotDictionary shotData)
    {
        CallDeferred("emit_signal", SignalName.ShotReceived, shotData);
    }

    private static void LogInfo(string message)
    {
        GD.Print($"{LogPrefix} {message}");
    }

    private static void LogError(string message)
    {
        GD.PrintErr($"{LogPrefix} {message}");
    }
}
