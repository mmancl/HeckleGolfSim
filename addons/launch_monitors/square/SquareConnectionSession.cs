using System;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using LaunchMonitors.Common.Bluetooth;

namespace LaunchMonitors.Square;

internal sealed class SquareConnectionSession : IAsyncDisposable
{
    private const string DeviceNotReadyMessage = "Square device was detected but is not ready yet. Wait a moment and try connecting again.";

    private readonly SemaphoreSlim _connectionLock = new(1, 1);
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly IBluetoothGattClient _bluetoothClient;
    private readonly SquareConnectionOptions _options;
    private readonly Func<TimeSpan, CancellationToken, Task> _delayAsync;
    private readonly Action<string> _logInfo;
    private readonly Action<string> _logError;
    private Timer? _heartbeatTimer;
    private Timer? _watchdogTimer;
    private byte _sequence;
    private string? _lastPayload;
    private string _clubCode = SquareCommandBuilder.DriverClubCode;
    private int _handedness;
    private bool _isConnected;
    private bool _isDetectBallActive;
    private bool _isReady;
    private DateTime _lastSensorPacketTime = DateTime.MinValue;
    private DateTime _lastRearmAttemptTime = DateTime.MinValue;

    public SquareConnectionSession(
        IBluetoothGattClient bluetoothClient,
        SquareConnectionOptions? options = null,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null,
        Action<string>? logInfo = null,
        Action<string>? logError = null)
    {
        _bluetoothClient = bluetoothClient;
        _options = options ?? SquareConnectionOptions.Default;
        _delayAsync = delayAsync ?? Task.Delay;
        _logInfo = logInfo ?? (_ => { });
        _logError = logError ?? (_ => { });

        _bluetoothClient.DeviceDiscovered += OnDeviceDiscovered;
        _bluetoothClient.CharacteristicValueChanged += OnCharacteristicValueChanged;
        _bluetoothClient.Disconnected += OnBluetoothDisconnected;
    }

    public event Action<BluetoothDevice>? DeviceDiscovered;

    public event Action<string>? StatusChanged;

    public event Action<string>? ErrorOccurred;

    public event Action<int>? BatteryChanged;

    public event Action<string>? FirmwareChanged;

    public event Action<bool>? ReadyChanged;

    public event Action<SquareSensorData>? SensorDataReceived;

    public event Action<SquareShotMetrics>? ShotReceived;

    public async Task StartScanAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("StartScan requested.");
        await StopScanAsync(cancellationToken);
        EmitStatus("Scanning");
        await _bluetoothClient.StartScanAsync(new BluetoothScanOptions(_options.DeviceNamePrefix), cancellationToken);
    }

    public async Task StopScanAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("StopScan requested.");
        await _bluetoothClient.StopScanAsync(cancellationToken);
    }

    public async Task ConnectToDeviceAsync(string deviceId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            EmitError("No Square device was selected.");
            return;
        }

        await _connectionLock.WaitAsync(cancellationToken);
        try
        {
            await StopScanAsync(cancellationToken);
            await DisconnectCoreAsync(cancellationToken);
            EmitStatus("Connecting");

            await _bluetoothClient.ConnectAsync(deviceId, CreateBluetoothConnectionOptions(), cancellationToken);
            _isConnected = true;

            await ReadDeviceInfoAsync(cancellationToken);
            await SubscribeToNotificationsAsync(cancellationToken);
            EmitStatus("Connected");
            await WriteCommandAsync(SquareCommandBuilder.Heartbeat(NextSequence()), cancellationToken);
            await _delayAsync(_options.ConnectionClubDelay, cancellationToken);
            await WriteCommandAsync(SquareCommandBuilder.Club(NextSequence(), _clubCode, _handedness), cancellationToken);
            await _delayAsync(_options.ConnectionReadyDelay, cancellationToken);
            await SetReadyAsync(cancellationToken);
            StartHeartbeat();
            StartWatchdog();
            _logInfo("Connection sequence complete.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            EmitError("Square connection timed out. Please verify device is powered on and in pairing mode.");
            EmitStatus("Disconnected");
            _logError("ConnectToDeviceAsync timed out.");
            await DisconnectCoreAsync(CancellationToken.None);
        }
        catch (Exception ex) when (IsTransientConnectFailure(ex))
        {
            EmitError(DeviceNotReadyMessage);
            EmitStatus("Disconnected");
            _logInfo($"ConnectToDeviceAsync deferred: {ex.Message}");
            await DisconnectCoreAsync(CancellationToken.None);
        }
        catch (Exception ex)
        {
            EmitError($"Square connection failed: {ex.Message}");
            EmitStatus("Disconnected");
            _logError($"ConnectToDeviceAsync failed: {ex}");
            await DisconnectCoreAsync(CancellationToken.None);
        }
        finally
        {
            _connectionLock.Release();
        }
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("DisconnectAsync requested.");
        var lockAcquired = false;
        try
        {
            lockAcquired = await _connectionLock.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
            await DisconnectCoreAsync(cancellationToken);
            EmitStatus("Disconnected");
            EmitReady(false);
        }
        finally
        {
            if (lockAcquired)
            {
                _connectionLock.Release();
            }
        }
    }

    public async Task SetClubAsync(string clubCode, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(clubCode))
        {
            clubCode = SquareCommandBuilder.DriverClubCode;
        }

        var forceUpdate = !_clubCode.Equals(clubCode, StringComparison.OrdinalIgnoreCase);
        _clubCode = clubCode;
        _logInfo($"SetClub requested. clubCode={_clubCode}, forceUpdate={forceUpdate}");

        if (_isConnected)
        {
            if (forceUpdate)
            {
                await WriteCommandAsync(SquareCommandBuilder.Club(NextSequence(), _clubCode, _handedness), cancellationToken);
                await _delayAsync(_options.ConnectionReadyDelay, cancellationToken);
            }
            await SetReadyAsync(cancellationToken);
        }
    }

    public void SetHandedness(int handedness)
    {
        _handedness = handedness == 1 ? 1 : 0;
        _logInfo($"SetHandedness requested. handedness={_handedness}");
    }

    public async Task SetReadyAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("Sending DetectBall ready command.");
        await WriteCommandAsync(SquareCommandBuilder.DetectBall(NextSequence(), mode: 1, spinMode: 1), cancellationToken);
        _isDetectBallActive = true;
        _lastSensorPacketTime = DateTime.UtcNow;
        EmitStatus("Ready");
    }

    public async ValueTask DisposeAsync()
    {
        _bluetoothClient.DeviceDiscovered -= OnDeviceDiscovered;
        _bluetoothClient.CharacteristicValueChanged -= OnCharacteristicValueChanged;
        _bluetoothClient.Disconnected -= OnBluetoothDisconnected;
        _watchdogTimer?.Dispose();
        _watchdogTimer = null;
        await DisconnectAsync();
        await _bluetoothClient.DisposeAsync();
        _connectionLock.Dispose();
        _writeLock.Dispose();
    }

    private async Task ReadDeviceInfoAsync(CancellationToken cancellationToken)
    {
        var battery = await _bluetoothClient.ReadCharacteristicAsync(_options.BatteryCharacteristicUuid, cancellationToken);
        if (battery.Length > 0)
        {
            EmitBattery(battery[0]);
        }

        var firmware = await _bluetoothClient.ReadCharacteristicAsync(_options.FirmwareCharacteristicUuid, cancellationToken);
        if (firmware.Length > 0)
        {
            EmitFirmware(ParseFirmware(firmware));
        }
    }

    private BluetoothConnectionOptions CreateBluetoothConnectionOptions()
    {
        return new BluetoothConnectionOptions(
            RequiredCharacteristicUuids:
            [
                _options.CommandCharacteristicUuid,
                _options.EventCharacteristicUuid
            ],
            OptionalCharacteristicUuids:
            [
                _options.BatteryCharacteristicUuid,
                _options.FirmwareCharacteristicUuid
            ],
            ServiceDiscoveryMaxAttempts: _options.ServiceDiscoveryMaxAttempts,
            ServiceDiscoveryRetryDelay: _options.ServiceDiscoveryRetryDelay);
    }

    private async Task SubscribeToNotificationsAsync(CancellationToken cancellationToken)
    {
        await _bluetoothClient.SubscribeToCharacteristicAsync(_options.EventCharacteristicUuid, cancellationToken);

        try
        {
            await _bluetoothClient.SubscribeToCharacteristicAsync(_options.BatteryCharacteristicUuid, cancellationToken);
        }
        catch (InvalidOperationException)
        {
        }
    }

    private async Task WriteCommandAsync(
        byte[] command,
        CancellationToken cancellationToken,
        BluetoothWriteMode writeMode = BluetoothWriteMode.WithResponse)
    {
        if (!_isConnected)
        {
            throw new InvalidOperationException("Square command channel is not available.");
        }

        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            await _bluetoothClient.WriteCharacteristicAsync(
                _options.CommandCharacteristicUuid,
                command,
                writeMode,
                cancellationToken);
            _logInfo($"Wrote command ({command.Length} bytes, mode={writeMode}).");
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private async Task DisconnectCoreAsync(CancellationToken cancellationToken)
    {
        _heartbeatTimer?.Dispose();
        _heartbeatTimer = null;
        _watchdogTimer?.Dispose();
        _watchdogTimer = null;
        _lastPayload = null;
        _isConnected = false;
        _isDetectBallActive = false;
        _isReady = false;
        _lastSensorPacketTime = DateTime.MinValue;
        _lastRearmAttemptTime = DateTime.MinValue;
        await _bluetoothClient.DisconnectAsync(cancellationToken);
    }

    private void StartHeartbeat()
    {
        if (_options.HeartbeatInterval <= TimeSpan.Zero || _options.HeartbeatInterval == Timeout.InfiniteTimeSpan)
        {
            return;
        }

        _heartbeatTimer = new Timer(OnHeartbeatTimer, null, _options.HeartbeatInterval, _options.HeartbeatInterval);
    }

    private void StartWatchdog()
    {
        _watchdogTimer?.Dispose();
        if (_options.WatchdogInterval <= TimeSpan.Zero || _options.WatchdogInterval == Timeout.InfiniteTimeSpan)
        {
            return;
        }

        _watchdogTimer = new Timer(OnWatchdogTimer, null, _options.WatchdogInterval, _options.WatchdogInterval);
    }

    private void OnWatchdogTimer(object? state)
    {
        if (!_isConnected)
        {
            return;
        }

        var now = DateTime.UtcNow;

        // 1. Check for stale sensor packets while marked ready:
        // If the hardware timed out/went idle while unattended, the optical stream halts.
        // Drop the ready state so the UI and game never freeze in "Ball Ready".
        if (_isReady && _lastSensorPacketTime != DateTime.MinValue && (now - _lastSensorPacketTime) > _options.SensorPacketTimeout)
        {
            _logInfo($"Sensor stream timed out ({(now - _lastSensorPacketTime).TotalSeconds:F1}s since last packet). Resetting ready state.");
            EmitReady(false);
            SensorDataReceived?.Invoke(new SquareSensorData(false, false, 0, 0, 0));
        }

        // 2. Auto-rearm if in active detect mode and sensor has gone idle/silent:
        // When golfer is addressing ball or talking, hardware powers down camera after timeout.
        // Send DetectBall to seamlessly wake the camera back up so the user does not need to disconnect/reconnect.
        if (_isDetectBallActive && !_isReady && _lastSensorPacketTime != DateTime.MinValue && (now - _lastSensorPacketTime) > TimeSpan.FromSeconds(6))
        {
            if ((now - _lastRearmAttemptTime) > TimeSpan.FromSeconds(8))
            {
                _lastRearmAttemptTime = now;
                _logInfo("Auto-rearming launch monitor detect mode after sensor silence...");
                _ = RunAsync(async () =>
                {
                    await SetReadyAsync();
                });
            }
        }
    }

    private void OnHeartbeatTimer(object? state)
    {
        _ = RunAsync(async () =>
        {
            if (!_isConnected)
            {
                return;
            }

            try
            {
                await WriteCommandAsync(
                    SquareCommandBuilder.Heartbeat(NextSequence()),
                    CancellationToken.None,
                    BluetoothWriteMode.WithoutResponse);
            }
            catch (Exception ex)
            {
                _logError($"Heartbeat write failed: {ex.Message}");
            }
        });
    }

    private void OnBluetoothDisconnected()
    {
        if (!_isConnected)
        {
            return;
        }

        _logInfo("Bluetooth client reported disconnection.");
        _ = RunAsync(async () =>
        {
            await DisconnectAsync();
        });
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        DeviceDiscovered?.Invoke(device);
    }

    private void OnCharacteristicValueChanged(BluetoothCharacteristicValue value)
    {
        if (value.CharacteristicUuid == _options.EventCharacteristicUuid)
        {
            _ = RunAsync(() => HandleNotificationAsync(value.Value));
            return;
        }

        if (value.CharacteristicUuid == _options.BatteryCharacteristicUuid && value.Value.Length > 0)
        {
            EmitBattery(value.Value[0]);
        }
    }

    private async Task HandleNotificationAsync(byte[] data)
    {
        if (SquareProtocol.TryParseStatus(data, out var statusCode))
        {
            _logInfo($"Square status packet received: 0x{statusCode:X2}");
            if (statusCode == SquareProtocol.StatusIdle || statusCode == SquareProtocol.StatusNone)
            {
                _logInfo("Square reported Idle/Standby status. Resetting ready state.");
                EmitReady(false);
                SensorDataReceived?.Invoke(new SquareSensorData(false, false, 0, 0, 0));

                if (_isDetectBallActive && _isConnected)
                {
                    _logInfo("Auto-rearming launch monitor detect mode after hardware reported idle.");
                    await _delayAsync(TimeSpan.FromSeconds(1), CancellationToken.None);
                    await SetReadyAsync();
                }
            }
            else if (statusCode == SquareProtocol.StatusReady)
            {
                EmitStatus("Ready");
            }
            return;
        }

        if (SquareProtocol.TryParseSensor(data, out var sensor))
        {
            _lastSensorPacketTime = DateTime.UtcNow;
            var ready = sensor.BallReady && sensor.BallDetected;
            EmitReady(ready);
            SensorDataReceived?.Invoke(sensor);
            _logInfo($"Sensor packet parsed. ready={ready}, pos=({sensor.PositionX}, {sensor.PositionY}, {sensor.PositionZ})");
            return;
        }

        if (!SquareProtocol.TryParseShot(data, out var metrics))
        {
            return;
        }

        var payload = Convert.ToHexString(data);
        if (payload == _lastPayload)
        {
            return;
        }

        _lastPayload = payload;
        _isDetectBallActive = false;
        EmitReady(false);
        ShotReceived?.Invoke(metrics);
        _logInfo($"Shot packet parsed. speed={metrics.BallSpeedMps} m/s, spin={metrics.TotalSpinRpm} rpm");
        await _delayAsync(_options.ConnectionReadyDelay, CancellationToken.None);
        await SetReadyAsync();
    }

    private byte NextSequence()
    {
        var sequence = _sequence;
        unchecked
        {
            _sequence++;
        }

        return sequence;
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
            _logError($"RunAsync failed: {ex}");
        }
    }

    private void EmitStatus(string status)
    {
        StatusChanged?.Invoke(status);
    }

    private void EmitError(string message)
    {
        ErrorOccurred?.Invoke(message);
    }

    private void EmitBattery(int level)
    {
        BatteryChanged?.Invoke(level);
    }

    private void EmitFirmware(string firmware)
    {
        FirmwareChanged?.Invoke(firmware);
    }

    private void EmitReady(bool ready)
    {
        if (_isReady == ready)
        {
            return;
        }

        _isReady = ready;
        ReadyChanged?.Invoke(ready);
    }

    private static string ParseFirmware(byte[] bytes)
    {
        var text = Encoding.UTF8.GetString(bytes);
        try
        {
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.TryGetProperty("lm", out var launchMonitorVersion))
            {
                return launchMonitorVersion.GetString() ?? text;
            }
        }
        catch (JsonException)
        {
            return text;
        }

        return text;
    }

    private static bool IsTransientConnectFailure(Exception ex)
    {
        if (ex is TimeoutException)
        {
            return true;
        }

        return ex is InvalidOperationException invalidOperationException
            && invalidOperationException.Message.Contains(
                "Could not open the selected Bluetooth device.",
                StringComparison.OrdinalIgnoreCase);
    }
}
