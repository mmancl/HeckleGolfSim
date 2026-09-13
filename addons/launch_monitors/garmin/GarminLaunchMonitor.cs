using System;
using System.Threading.Tasks;
using Godot;
using LaunchMonitors.Common.Bluetooth;
using LaunchMonitors.Garmin;
using GodotDictionary = Godot.Collections.Dictionary;

[GlobalClass]
public partial class GarminLaunchMonitor : Node
{
    private const string LogPrefix = "[GarminLaunchMonitor]";

    private readonly GarminConnectionSession _session = new(
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
    public delegate void ShotReceivedEventHandler(GodotDictionary shotData);

    public override void _Ready()
    {
        _session.DeviceDiscovered += OnDeviceDiscovered;
        _session.StatusChanged += EmitStatus;
        _session.ErrorOccurred += EmitError;
        _session.BatteryChanged += EmitBattery;
        _session.FirmwareChanged += EmitFirmware;
        _session.ReadyChanged += EmitReady;
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
        if (!_session.IsConnected)
        {
            LogInfo("SetReady ignored: device is not connected.");
            return;
        }
        _ = RunAsync(() => _session.SetReadyAsync());
    }

    public void WakeDevice()
    {
        if (!_session.IsConnected)
        {
            LogInfo("WakeDevice ignored: device is not connected.");
            return;
        }
        _ = RunAsync(() => _session.WakeDeviceAsync());
    }

    public void CalibrateTilt()
    {
        if (!_session.IsConnected)
        {
            LogInfo("CalibrateTilt ignored: device is not connected.");
            return;
        }
        _ = RunAsync(() => _session.StartTiltCalibrationAsync());
    }

    public void SetShotConfig(float temperatureF, float altitudeFt, float teeDistanceFt)
    {
        _ = RunAsync(() => _session.SendShotConfigAsync(temperatureF, altitudeFt, teeDistanceFt));
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        EmitDeviceDiscovered(device.DeviceId, device.Name, device.Rssi);
    }

    private void OnShotReceived(GarminShotMetrics metrics)
    {
        EmitShot(GarminGodotMapper.ToBallData(metrics));
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

    private void EmitReady(bool isReady)
    {
        CallDeferred("emit_signal", SignalName.ReadyChanged, isReady);
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
