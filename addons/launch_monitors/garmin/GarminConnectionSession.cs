using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Google.Protobuf;
using LaunchMonitor.Proto;
using LaunchMonitors.Common.Bluetooth;
using static LaunchMonitor.Proto.State.Types;

namespace LaunchMonitors.Garmin;

internal sealed class GarminConnectionSession : IAsyncDisposable
{
    internal static readonly Guid DeviceInterfaceServiceUuid = Guid.Parse("6A4E2800-667B-11E3-949A-0800200C9A66");
    internal static readonly Guid DeviceInterfaceNotifierUuid = Guid.Parse("6A4E2812-667B-11E3-949A-0800200C9A66");
    internal static readonly Guid DeviceInterfaceWriterUuid = Guid.Parse("6A4E2822-667B-11E3-949A-0800200C9A66");

    internal static readonly Guid MeasurementServiceUuid = Guid.Parse("6A4E3400-667B-11E3-949A-0800200C9A66");
    internal static readonly Guid MeasurementCharacteristicUuid = Guid.Parse("6A4E3401-667B-11E3-949A-0800200C9A66");
    internal static readonly Guid ControlPointCharacteristicUuid = Guid.Parse("6A4E3402-667B-11E3-949A-0800200C9A66");
    internal static readonly Guid StatusCharacteristicUuid = Guid.Parse("6A4E3403-667B-11E3-949A-0800200C9A66");

    internal static readonly Guid DeviceInfoServiceUuid = Guid.Parse("0000180a-0000-1000-8000-00805f9b34fb");
    internal static readonly Guid FirmwareCharacteristicUuid = Guid.Parse("00002a28-0000-1000-8000-00805f9b34fb");
    internal static readonly Guid ModelCharacteristicUuid = Guid.Parse("00002a24-0000-1000-8000-00805f9b34fb");
    internal static readonly Guid SerialCharacteristicUuid = Guid.Parse("00002a25-0000-1000-8000-00805f9b34fb");

    internal static readonly Guid BatteryServiceUuid = Guid.Parse("0000180f-0000-1000-8000-00805f9b34fb");
    internal static readonly Guid BatteryCharacteristicUuid = Guid.Parse("00002a19-0000-1000-8000-00805f9b34fb");

    private readonly SemaphoreSlim _connectionLock = new(1, 1);
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly SemaphoreSlim _protoLock = new(1, 1);
    private readonly IBluetoothGattClient _bluetoothClient;
    private readonly GarminConnectionOptions _options;
    private readonly Action<string> _logInfo;
    private readonly Action<string> _logError;

    private readonly HashSet<uint> _processedShotIds = [];
    private readonly List<byte> _readBuffer = [];
    private TaskCompletionSource<bool>? _handshakeTcs;
    private TaskCompletionSource<WrapperProto?>? _protoResponseTcs;

    private byte _header = 0x00;
    private bool _handshakeComplete;
    private bool _isConnected;
    private bool _isInitializing;
    private bool _isAutoWaking;
    private int _protoRequestCounter;
    private bool _isReady;

    private float _temperatureF;
    private float _altitudeFt;
    private float _teeDistanceFt;
    private float _humidity;

    public GarminConnectionSession(
        IBluetoothGattClient bluetoothClient,
        GarminConnectionOptions? options = null,
        Action<string>? logInfo = null,
        Action<string>? logError = null)
    {
        _bluetoothClient = bluetoothClient;
        _options = options ?? GarminConnectionOptions.Default;
        _logInfo = logInfo ?? (_ => { });
        _logError = logError ?? (_ => { });

        _temperatureF = _options.TemperatureF;
        _altitudeFt = _options.AltitudeFt;
        _teeDistanceFt = _options.TeeDistanceFt;
        _humidity = _options.Humidity;

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
    public event Action<GarminShotMetrics>? ShotReceived;

    public bool IsConnected => _isConnected;
    public bool IsReady => _isReady;

    public async Task StartScanAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("StartScan requested for Garmin Approach R10.");
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
            EmitError("No Garmin R10 device was selected.");
            return;
        }

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(20));
        var timeoutToken = timeoutCts.Token;

        await _connectionLock.WaitAsync(timeoutToken);
        try
        {
            await StopScanAsync(timeoutToken);
            await DisconnectCoreAsync(timeoutToken);
            EmitStatus("Connecting");

            var connOptions = new BluetoothConnectionOptions(
                RequiredCharacteristicUuids: [DeviceInterfaceNotifierUuid, DeviceInterfaceWriterUuid],
                OptionalCharacteristicUuids:
                [
                    MeasurementCharacteristicUuid,
                    ControlPointCharacteristicUuid,
                    StatusCharacteristicUuid,
                    BatteryCharacteristicUuid,
                    FirmwareCharacteristicUuid,
                    ModelCharacteristicUuid,
                    SerialCharacteristicUuid
                ],
                ServiceDiscoveryMaxAttempts: 4,
                ServiceDiscoveryRetryDelay: TimeSpan.FromMilliseconds(700));

            await _bluetoothClient.ConnectAsync(deviceId, connOptions, timeoutToken);
            _isConnected = true;

            await ReadDeviceInfoAsync(timeoutToken);
            await SubscribeToNotificationsAsync(timeoutToken);

            _protoRequestCounter = 0;
            _isInitializing = true;
            try
            {
                _logInfo("Starting Garmin R10 handshake...");
                var handshakeSuccess = await PerformHandshakeAsync(timeoutToken);
                if (!handshakeSuccess)
                {
                    throw new InvalidOperationException("Failed to complete Garmin R10 handshake protocol.");
                }

                _logInfo("Handshake complete. Initializing device services...");

                // 1. Wake device
                await WakeDeviceAsync(timeoutToken);
                await Task.Delay(300, timeoutToken);

                // 2. Request device status
                var initialState = await RequestStatusAsync(timeoutToken);

                // If device is in InterferenceTest, wait for it to settle
                if (initialState == StateType.InterferenceTest)
                {
                    _logInfo("Device is in InterferenceTest. Waiting for test to complete...");
                    for (int i = 0; i < 12; i++)
                    {
                        await Task.Delay(500, timeoutToken);
                        var st = await RequestStatusAsync(timeoutToken);
                        if (st != StateType.InterferenceTest)
                        {
                            _logInfo($"InterferenceTest completed. State: {st}");
                            break;
                        }
                    }
                }

                // 3. Subscribe to launch monitor radar alerts (with retry)
                var subscribed = await SubscribeToAlertsAsync(timeoutToken);
                if (!subscribed)
                {
                    throw new InvalidOperationException("Failed to subscribe to Garmin R10 radar alerts. Shot tracking will not function.");
                }

                if (_options.CalibrateTiltOnConnect)
                {
                    await StartTiltCalibrationAsync(timeoutToken);
                }

                // 4. Complete initialization and ensure device is active (Waiting)
                _isInitializing = false;

                var finalState = await RequestStatusAsync(timeoutToken);
                if (finalState == StateType.Standby)
                {
                    _logInfo("Device in Standby at end of setup. Sending WakeUp call...");
                    await WakeDeviceAsync(timeoutToken);
                    await Task.Delay(300, timeoutToken);
                    await RequestStatusAsync(timeoutToken);
                }

                await SetReadyAsync(timeoutToken);
            }
            finally
            {
                _isInitializing = false;
            }

            _logInfo("Garmin Approach R10 setup complete and ready.");
            EmitStatus("Connected");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            EmitError("Garmin R10 connection timed out. Ensure device is powered on and in pairing mode.");
            EmitStatus("Disconnected");
            _logError("ConnectToDeviceAsync timed out.");
            await DisconnectCoreAsync(CancellationToken.None);
        }
        catch (Exception ex)
        {
            var errorMsg = ex.Message;
            if (string.IsNullOrWhiteSpace(errorMsg))
            {
                if (ex is System.Runtime.InteropServices.COMException comEx && (uint)comEx.HResult == 0x80650005)
                {
                    errorMsg = "Garmin Approach R10 requires Bluetooth pairing. Please pair your Approach R10 in Windows Settings (Bluetooth & devices -> Add device), then connect again.";
                }
                else
                {
                    errorMsg = $"{ex.GetType().Name} (0x{ex.HResult:X8})";
                }
            }

            EmitError($"Garmin R10 connection failed: {errorMsg}");
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

    public async Task SetReadyAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("SetReady requested.");
        if (!_isConnected || !_handshakeComplete)
        {
            _logInfo("SetReady ignored: device is not connected or handshake not complete.");
            return;
        }
        await WakeDeviceAsync(cancellationToken);
        await Task.Delay(200, cancellationToken);
        await RequestStatusAsync(cancellationToken);
    }

    public async Task WakeDeviceAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("Sending WakeUp request to Garmin R10...");
        if (!_isConnected || !_handshakeComplete)
        {
            _logInfo("WakeUp request ignored: device is not connected or handshake not complete.");
            return;
        }
        var request = new WrapperProto
        {
            Service = new LaunchMonitorService
            {
                WakeUpRequest = new WakeUpRequest()
            }
        };

        var response = await SendProtobufRequestAsync(request, cancellationToken);
        var status = response?.Service?.WakeUpResponse?.Status;
        if (status != null)
        {
            _logInfo($"WakeUp response received: status={status}");
        }
    }

    public async Task<StateType?> RequestStatusAsync(CancellationToken cancellationToken = default)
    {
        if (!_isConnected || !_handshakeComplete)
        {
            return null;
        }
        var request = new WrapperProto
        {
            Service = new LaunchMonitorService
            {
                StatusRequest = new StatusRequest()
            }
        };

        var response = await SendProtobufRequestAsync(request, cancellationToken);
        if (response?.Service?.StatusResponse?.State != null)
        {
            var st = response.Service.StatusResponse.State.State_;
            _logInfo($"Status response received: state={st}");
            HandleState(st);
            return st;
        }
        return null;
    }

    public async Task StartTiltCalibrationAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("Requesting Tilt Calibration...");
        if (!_isConnected || !_handshakeComplete)
        {
            _logInfo("Tilt calibration ignored: device is not connected or handshake not complete.");
            return;
        }
        var request = new WrapperProto
        {
            Service = new LaunchMonitorService
            {
                StartTiltCalRequest = new StartTiltCalibrationRequest()
            }
        };

        await SendProtobufRequestAsync(request, cancellationToken);
    }

    public async Task SendShotConfigAsync(float temperatureF, float altitudeFt, float teeDistanceFt, CancellationToken cancellationToken = default)
    {
        _temperatureF = temperatureF;
        _altitudeFt = altitudeFt;
        _teeDistanceFt = teeDistanceFt;

        if (!_isConnected || !_handshakeComplete)
        {
            _logInfo($"Cached Garmin shot config (Temp={temperatureF:F1} F, Alt={altitudeFt:F1} ft, Tee={teeDistanceFt:F1} ft) until connection completes.");
            return;
        }

        float teeDistanceMeters = teeDistanceFt / 3.28084f;
        var request = new WrapperProto
        {
            Service = new LaunchMonitorService
            {
                ShotConfigRequest = new ShotConfigRequest
                {
                    Temperature = temperatureF,
                    Humidity = _humidity,
                    Altitude = altitudeFt,
                    AirDensity = 1.0f,
                    TeeRange = teeDistanceMeters
                }
            }
        };

        await SendProtobufRequestAsync(request, cancellationToken);
    }

    private async Task<bool> SubscribeToAlertsAsync(CancellationToken cancellationToken)
    {
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            _logInfo($"Subscribing to Launch Monitor radar alerts (attempt {attempt}/3)...");
            var request = new WrapperProto
            {
                Event = new EventSharing
                {
                    SubscribeRequest = new SubscribeRequest
                    {
                        Alerts =
                        {
                            new AlertMessage
                            {
                                Type = AlertNotification.Types.AlertType.LaunchMonitor
                            }
                        }
                    }
                }
            };

            var response = await SendProtobufRequestAsync(request, cancellationToken);
            if (response?.Event?.SubscribeRespose != null && response.Event.SubscribeRespose.AlertStatus.Count > 0)
            {
                _logInfo($"[Garmin] Subscribed to alerts successfully ({response.Event.SubscribeRespose.AlertStatus.Count} alert statuses received).");
                return true;
            }

            _logInfo($"[Garmin] Subscribe to alerts attempt {attempt} failed or timed out. Retrying in 1s...");
            await Task.Delay(1000, cancellationToken);
        }

        _logError("[Garmin] Failed to subscribe to radar alerts after 3 attempts.");
        return false;
    }

    private async Task<bool> PerformHandshakeAsync(CancellationToken cancellationToken)
    {
        _handshakeComplete = false;
        _header = 0x00;
        _handshakeTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        // Handshake init packet: 000000000000000000010000 (prefixed with 0x00 header)
        byte[] handshakeBytes = GarminByteExtensions.HexStringToBytes("000000000000000000010000");
        await WriteRawBytesAsync(handshakeBytes, cancellationToken);

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(_options.HandshakeTimeout);

        try
        {
            using (cts.Token.Register(() => _handshakeTcs.TrySetCanceled()))
            {
                return await _handshakeTcs.Task;
            }
        }
        catch (OperationCanceledException)
        {
            _logError("Handshake timed out waiting for response from Garmin R10.");
            return false;
        }
    }

    private void OnCharacteristicValueChanged(BluetoothCharacteristicValue value)
    {
        if (value.CharacteristicUuid == BatteryCharacteristicUuid)
        {
            if (value.Value.Length > 0)
            {
                var level = value.Value[0];
                EmitBattery(level);
            }
            return;
        }

        if (value.CharacteristicUuid == StatusCharacteristicUuid)
        {
            _logInfo($"[Garmin] Status characteristic data: len={value.Value.Length}, bytes={value.Value.ToHexString()}");
            return;
        }

        if (value.CharacteristicUuid == MeasurementCharacteristicUuid)
        {
            _logInfo($"[Garmin] Measurement characteristic data: len={value.Value.Length}, bytes={value.Value.ToHexString()}");
            return;
        }

        if (value.CharacteristicUuid != DeviceInterfaceNotifierUuid)
        {
            return;
        }

        var data = value.Value;
        if (data.Length == 0)
        {
            return;
        }

        byte header = data[0];
        byte[] payload = data.Skip(1).ToArray();

        if (!_handshakeComplete)
        {
            var hex = payload.ToHexString();
            if (hex.StartsWith("010000000000000000010000", StringComparison.OrdinalIgnoreCase))
            {
                if (payload.Length > 12)
                {
                    _header = payload[12];
                }

                _ = Task.Run(async () =>
                {
                    // Respond with 00 to complete handshake
                    await WriteRawBytesAsync([0x00], CancellationToken.None);
                    _handshakeComplete = true;
                    _handshakeTcs?.TrySetResult(true);
                });
            }
            return;
        }

        // Process framed bytes
        lock (_readBuffer)
        {
            var readComplete = false;
            IEnumerable<byte> msgBytes = payload;

            if (msgBytes.Any() && msgBytes.Last() == 0x00)
            {
                readComplete = true;
                msgBytes = msgBytes.SkipLast(1);
            }

            if (msgBytes.Any() && msgBytes.First() == 0x00)
            {
                _readBuffer.Clear();
                msgBytes = msgBytes.Skip(1);
            }

            _readBuffer.AddRange(msgBytes);

            if (readComplete && _readBuffer.Count > 0)
            {
                var decoded = GarminCobs.Decode(_readBuffer).ToArray();
                _readBuffer.Clear();

                if (decoded.Length >= 4)
                {
                    var expectedCrc = BitConverter.ToUInt16(decoded[^2..]);
                    var actualCrc = BitConverter.ToUInt16(decoded[..^2].Checksum());
                    if (expectedCrc == actualCrc)
                    {
                        var innerMsg = decoded.Skip(2).SkipLast(2).ToArray();
                        ProcessInnerMessage(innerMsg);
                    }
                    else
                    {
                        _logError("CRC verification failed for Garmin R10 packet.");
                    }
                }
            }
        }
    }

    private void ProcessInnerMessage(byte[] msg)
    {
        if (msg.Length < 2)
        {
            return;
        }

        var hex = msg.ToHexString();
        var ackBody = new List<byte> { 0x00 };

        // 0xB313 = Protobuf Request / Notification from R10 device
        if (hex.StartsWith("B313", StringComparison.OrdinalIgnoreCase))
        {
            if (msg.Length >= 4)
            {
                ackBody.AddRange(msg[2..4]);
                ackBody.AddRange(GarminByteExtensions.HexStringToBytes("00000000000000"));
            }

            var ack = GarminByteExtensions.HexStringToBytes("8813").Concat(msg[..2]).Concat(ackBody).ToArray();
            _ = WriteFramedMessageAsync(ack, CancellationToken.None);

            _logInfo($"[Garmin] Received B313 notification/request: len={msg.Length}");

            if (msg.Length > 16)
            {
                try
                {
                    var protoData = msg.Skip(16).ToArray();
                    var wrapper = WrapperProto.Parser.ParseFrom(protoData);
                    HandleProtobufMessage(wrapper);
                }
                catch (Exception ex)
                {
                    _logError($"Failed to parse protobuf request: {ex.Message}");
                }
            }
        }
        // 0xB413 = Protobuf Response to host request
        else if (hex.StartsWith("B413", StringComparison.OrdinalIgnoreCase))
        {
            ushort counter = msg.Length >= 4 ? BitConverter.ToUInt16(msg[2..4]) : (ushort)0;
            if (msg.Length >= 4)
            {
                ackBody.AddRange(msg[2..4]);
                ackBody.AddRange(GarminByteExtensions.HexStringToBytes("00000000000000"));
            }

            var ack = GarminByteExtensions.HexStringToBytes("8813").Concat(msg[..2]).Concat(ackBody).ToArray();
            _ = WriteFramedMessageAsync(ack, CancellationToken.None);

            _logInfo($"[Garmin] Received B413 response: counter={counter}, expected={_protoRequestCounter}, len={msg.Length}");

            if (counter == (ushort)(_protoRequestCounter & 0xFFFF) && msg.Length > 16)
            {
                try
                {
                    var protoData = msg.Skip(16).ToArray();
                    var wrapper = WrapperProto.Parser.ParseFrom(protoData);
                    _protoResponseTcs?.TrySetResult(wrapper);
                }
                catch (Exception ex)
                {
                    _logError($"Failed to parse protobuf response: {ex.Message}");
                }
            }
        }
        else
        {
            // Acknowledge other messages (A013, BA13, etc.) per BaseDevice.cs
            var ack = GarminByteExtensions.HexStringToBytes("8813").Concat(msg[..2]).Concat(ackBody).ToArray();
            _ = WriteFramedMessageAsync(ack, CancellationToken.None);
        }
    }

    private void HandleProtobufMessage(WrapperProto wrapper)
    {
        _logInfo($"[Garmin] Protobuf message received: {wrapper}");
        var notification = wrapper.Event?.Notification?.AlertNotification_;
        if (notification == null)
        {
            return;
        }

        if (notification.State != null)
        {
            HandleState(notification.State.State_);
        }

        if (notification.Error != null && notification.Error.HasCode)
        {
            EmitError($"Garmin R10 Error: {notification.Error.Code} {notification.Error.Severity}");
        }

        if (notification.Metrics != null)
        {
            var shotId = notification.Metrics.ShotId;
            if (shotId > 0)
            {
                if (_processedShotIds.Contains(shotId))
                {
                    _logInfo($"Ignoring duplicate shot id {shotId}");
                    return;
                }

                _processedShotIds.Add(shotId);
                if (_processedShotIds.Count > 100)
                {
                    _processedShotIds.Clear();
                    _processedShotIds.Add(shotId);
                }
            }

            var ball = notification.Metrics.BallMetrics;
            var club = notification.Metrics.ClubMetrics;
            var ballSpeed = ball?.BallSpeed ?? 0.0f;

            // If the ball didn't move (no ball metrics or negligible ball speed), do not count as a shot
            if (ball == null || ballSpeed <= 0.1f)
            {
                _logInfo($"Practice swing or unhit ball detected for shot {shotId} (ballSpeed={ballSpeed * 2.23694f:F1} mph). Swing ignored (not counting as shot).");
                return;
            }

            var shotMetrics = new GarminShotMetrics(
                ShotId: shotId,
                BallSpeedMps: ballSpeed,
                VerticalLaunchAngle: ball?.LaunchAngle ?? 0.0f,
                HorizontalLaunchAngle: ball?.LaunchDirection ?? 0.0f,
                TotalSpinRpm: ball?.TotalSpin ?? 0.0f,
                SpinAxisDeg: (ball?.SpinAxis ?? 0.0f) * -1.0f, // Negate spin axis per Garmin R10 spec
                ClubSpeedMps: club?.ClubHeadSpeed ?? 0.0f,
                ClubPathDeg: club?.ClubAnglePath ?? 0.0f,
                FaceAngleDeg: club?.ClubAngleFace ?? 0.0f,
                AttackAngleDeg: club?.AttackAngle ?? 0.0f);

            _logInfo($"Shot {shotId} captured: Speed={shotMetrics.BallSpeedMps * 2.23694f:F1} mph, VLA={shotMetrics.VerticalLaunchAngle:F1}°, Spin={shotMetrics.TotalSpinRpm:F0} rpm");
            ShotReceived?.Invoke(shotMetrics);
        }
    }

    private void HandleState(StateType state)
    {
        _logInfo($"Garmin R10 State: {state}");
        if (state == StateType.Waiting)
        {
            EmitReady(true);
        }
        else
        {
            EmitReady(false);
            if (state == StateType.Standby && _options.AutoWake && !_isInitializing && !_isAutoWaking)
            {
                _isAutoWaking = true;
                _ = Task.Run(async () =>
                {
                    try
                    {
                        _logInfo("Device in Standby. Sending WakeUp call...");
                        await WakeDeviceAsync(CancellationToken.None);
                        await Task.Delay(300);
                        await RequestStatusAsync(CancellationToken.None);
                    }
                    catch (Exception ex)
                    {
                        _logInfo($"AutoWake error: {ex.Message}");
                    }
                    finally
                    {
                        _isAutoWaking = false;
                    }
                });
            }
        }
    }

    private async Task<WrapperProto?> SendProtobufRequestAsync(WrapperProto proto, CancellationToken cancellationToken)
    {
        await _protoLock.WaitAsync(cancellationToken);
        try
        {
            _protoResponseTcs = new TaskCompletionSource<WrapperProto?>(TaskCreationOptions.RunContinuationsAsynchronously);

            byte[] protoBytes = proto.ToByteArray();
            int len = protoBytes.Length;

            // B313 + requestCounter (4B) + 00 00 (2B) + len (4B) + len (4B) + protoBytes (16 bytes header)
            List<byte> msgBuilder = new();
            msgBuilder.AddRange(GarminByteExtensions.HexStringToBytes("B313"));
            msgBuilder.AddRange(BitConverter.GetBytes(_protoRequestCounter));
            msgBuilder.AddRange(new byte[] { 0x00, 0x00 });
            msgBuilder.AddRange(BitConverter.GetBytes(len));
            msgBuilder.AddRange(BitConverter.GetBytes(len));
            msgBuilder.AddRange(protoBytes);
            byte[] fullMsg = msgBuilder.ToArray();

            _logInfo($"[Garmin] Sending proto request {_protoRequestCounter} ({len} bytes payload, {fullMsg.Length} bytes total)");
            await WriteFramedMessageAsync(fullMsg, cancellationToken);

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(8));

            try
            {
                using (cts.Token.Register(() => _protoResponseTcs.TrySetCanceled()))
                {
                    var response = await _protoResponseTcs.Task;
                    _protoRequestCounter++;
                    await Task.Delay(150, cancellationToken);
                    return response;
                }
            }
            catch (OperationCanceledException)
            {
                _logError($"No response received for Garmin protobuf request {_protoRequestCounter}");
                _protoRequestCounter++;
                return null;
            }
        }
        finally
        {
            _protoLock.Release();
        }
    }

    private async Task WriteFramedMessageAsync(byte[] bytes, CancellationToken cancellationToken)
    {
        // Framed message = [length (2B)] + bytes + [crc16 (2B)]
        ushort length = (ushort)(2 + bytes.Length + 2);
        List<byte> frameBuilder = new();
        frameBuilder.AddRange(BitConverter.GetBytes(length));
        frameBuilder.AddRange(bytes);
        frameBuilder.AddRange(GarminCrc16.ComputeChecksum(frameBuilder));

        // COBS encode bounded by 0x00 delimiters
        List<byte> encoded = GarminCobs.Encode(frameBuilder).Prepend((byte)0x00).Append((byte)0x00).ToList();

        // Write in chunks of up to 19 bytes, each prefixed with _header
        while (encoded.Count > 19)
        {
            var chunk = encoded.Take(19).ToArray();
            encoded = encoded.Skip(19).ToList();
            await WriteRawBytesAsync(chunk, cancellationToken);
        }

        if (encoded.Count > 0)
        {
            await WriteRawBytesAsync(encoded.ToArray(), cancellationToken);
        }
    }

    private async Task WriteRawBytesAsync(byte[] bytes, CancellationToken cancellationToken)
    {
        if (!_isConnected)
        {
            _logInfo("WriteRawBytesAsync ignored: Bluetooth client is not connected.");
            return;
        }

        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            byte[] packet = [.. bytes.Prepend(_header)];
            await _bluetoothClient.WriteCharacteristicAsync(
                DeviceInterfaceWriterUuid,
                packet,
                BluetoothWriteMode.WithResponse,
                cancellationToken);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private async Task ReadDeviceInfoAsync(CancellationToken cancellationToken)
    {
        try
        {
            var firmwareBytes = await _bluetoothClient.ReadCharacteristicAsync(FirmwareCharacteristicUuid, cancellationToken);
            if (firmwareBytes.Length > 0)
            {
                var firmware = Encoding.ASCII.GetString(firmwareBytes).Trim();
                _logInfo($"Garmin R10 Firmware: {firmware}");
                EmitFirmware(firmware);
            }
        }
        catch (Exception ex)
        {
            _logInfo($"Device info read non-critical error: {ex.Message}");
        }
    }

    private async Task SubscribeToNotificationsAsync(CancellationToken cancellationToken)
    {
        await _bluetoothClient.SubscribeToCharacteristicAsync(DeviceInterfaceNotifierUuid, cancellationToken);

        try
        {
            await _bluetoothClient.SubscribeToCharacteristicAsync(MeasurementCharacteristicUuid, cancellationToken);
            _logInfo("Subscribed to Garmin Measurement characteristic.");
        }
        catch (Exception ex)
        {
            _logInfo($"Garmin Measurement characteristic subscription optional/failed: {ex.Message}");
        }

        try
        {
            await _bluetoothClient.SubscribeToCharacteristicAsync(ControlPointCharacteristicUuid, cancellationToken);
            _logInfo("Subscribed to Garmin Control Point characteristic.");
        }
        catch (Exception ex)
        {
            _logInfo($"Garmin Control Point characteristic subscription optional/failed: {ex.Message}");
        }

        try
        {
            await _bluetoothClient.SubscribeToCharacteristicAsync(BatteryCharacteristicUuid, cancellationToken);
        }
        catch
        {
            // Battery subscription optional
        }

        try
        {
            await _bluetoothClient.SubscribeToCharacteristicAsync(StatusCharacteristicUuid, cancellationToken);
        }
        catch
        {
            // Status characteristic optional
        }
    }

    private async Task DisconnectCoreAsync(CancellationToken cancellationToken)
    {
        _isConnected = false;
        _handshakeComplete = false;
        _isReady = false;
        _header = 0x00;
        _protoRequestCounter = 0;
        _readBuffer.Clear();
        _processedShotIds.Clear();

        await _bluetoothClient.DisconnectAsync(cancellationToken);
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        DeviceDiscovered?.Invoke(device);
    }

    private void OnBluetoothDisconnected()
    {
        _isConnected = false;
        _handshakeComplete = false;
        _isReady = false;
        EmitStatus("Disconnected");
        EmitReady(false);
    }

    private void EmitStatus(string status) => StatusChanged?.Invoke(status);
    private void EmitError(string message) => ErrorOccurred?.Invoke(message);
    private void EmitBattery(int level) => BatteryChanged?.Invoke(level);
    private void EmitFirmware(string firmware) => FirmwareChanged?.Invoke(firmware);
    private void EmitReady(bool ready)
    {
        _isReady = ready;
        ReadyChanged?.Invoke(ready);
    }

    public async ValueTask DisposeAsync()
    {
        _bluetoothClient.DeviceDiscovered -= OnDeviceDiscovered;
        _bluetoothClient.CharacteristicValueChanged -= OnCharacteristicValueChanged;
        _bluetoothClient.Disconnected -= OnBluetoothDisconnected;

        await DisconnectAsync();
        await _bluetoothClient.DisposeAsync();
        _connectionLock.Dispose();
        _writeLock.Dispose();
    }
}
