using System;
using System.Threading.Tasks;
using Godot;
using LaunchMonitors.Common;
using LaunchMonitors.Common.Bluetooth;
using LaunchMonitors.Square;
using GodotDictionary = Godot.Collections.Dictionary;

[GlobalClass]
public partial class SquareLaunchMonitor : Node
{
    private const string LogPrefix = "[SquareLaunchMonitor]";

    private readonly SquareConnectionSession _session = new(
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
        LogInfo("Node exiting tree. Stopping scan and disconnecting.");
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

    public void SetClub(string clubCode)
    {
        _ = RunAsync(() => _session.SetClubAsync(clubCode));
    }

    public void SetHandedness(int handedness)
    {
        _session.SetHandedness(handedness);
    }

    public void SetReady()
    {
        _ = RunAsync(() => _session.SetReadyAsync());
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        EmitDeviceDiscovered(device.DeviceId, device.Name, device.Rssi);
    }

    private void OnShotReceived(SquareShotMetrics metrics)
    {
        LogInfo($"Dispatching shot to GDScript: Speed={metrics.BallSpeedMps * 2.23694f:F1}mph, TotalSpin={metrics.TotalSpinRpm}rpm, SpinAxis={metrics.SpinAxis:F1}°, BackSpin={metrics.BackSpinRpm}, SideSpin={metrics.SideSpinRpm}, ShotType={metrics.ShotType}");
        EmitShot(SquareGodotMapper.ToBallData(metrics));
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
        Callable.From(() => EmitSignal(SignalName.DeviceDiscovered, deviceId, name, rssi)).CallDeferred();
    }

    private void EmitStatus(string status)
    {
        Callable.From(() => EmitSignal(SignalName.StatusChanged, status)).CallDeferred();
    }

    private void EmitError(string message)
    {
        Callable.From(() => EmitSignal(SignalName.ErrorOccurred, message)).CallDeferred();
    }

    private void EmitBattery(int level)
    {
        Callable.From(() => EmitSignal(SignalName.BatteryChanged, level)).CallDeferred();
    }

    private void EmitFirmware(string firmware)
    {
        Callable.From(() => EmitSignal(SignalName.FirmwareChanged, firmware)).CallDeferred();
    }

    private void EmitReady(bool ready)
    {
        Callable.From(() => EmitSignal(SignalName.ReadyChanged, ready)).CallDeferred();
    }

    private void OnSensorDataReceived(SquareSensorData sensor)
    {
        Callable.From(() => EmitSignal(SignalName.SensorDataReceived, sensor.PositionX, sensor.PositionY, sensor.PositionZ, sensor.BallReady, sensor.BallDetected)).CallDeferred();
    }

    private void EmitShot(GodotDictionary shotData)
    {
        Callable.From(() => EmitSignal(SignalName.ShotReceived, shotData)).CallDeferred();
    }

    private static void LogInfo(string message)
    {
        DebugLoggerBridge.LogBluetooth($"{LogPrefix} {message}");
    }

    private static void LogError(string message)
    {
        DebugLoggerBridge.LogError($"{LogPrefix} {message}");
    }
}
