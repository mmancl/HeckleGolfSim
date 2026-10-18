using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.IO;
using System.Linq;
using LaunchMonitors.Common.Bluetooth;

namespace LaunchMonitors.R10;

internal sealed class R10ConnectionSession : IAsyncDisposable
{
    private readonly SemaphoreSlim _connectionLock = new(1, 1);
    private readonly IBluetoothGattClient _bluetoothClient;
    private readonly R10ConnectionOptions _options;
    private readonly Action<string> _logInfo;
    private readonly Action<string> _logError;
    private readonly Timer? _heartbeatTimer;
    private bool _isConnected;

    public R10ConnectionSession(
        IBluetoothGattClient bluetoothClient,
        R10ConnectionOptions? options = null,
        Action<string>? logInfo = null,
        Action<string>? logError = null)
    {
        _bluetoothClient = bluetoothClient;
        _options = options ?? R10ConnectionOptions.Default;
        _logInfo = logInfo ?? (_ => { });
        _logError = logError ?? (_ => { });

        _bluetoothClient.DeviceDiscovered += OnDeviceDiscovered;
        _bluetoothClient.CharacteristicValueChanged += OnCharacteristicValueChanged;
        _bluetoothClient.Disconnected += OnBluetoothDisconnected;

        _heartbeatTimer = new Timer(_ => _ = WriteKeepaliveAsync(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    public event Action<BluetoothDevice>? DeviceDiscovered;

    public event Action<string>? StatusChanged;

    public event Action<string>? ErrorOccurred;

    public event Action<int>? BatteryChanged;

    public event Action<string>? FirmwareChanged;

    public event Action<bool>? ReadyChanged;

    public event Action<R10ShotMetrics>? ShotReceived;

    public event Action<R10SensorData>? SensorDataReceived;

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
            EmitError("No Garmin Approach R10 device was selected.");
            return;
        }

        await _connectionLock.WaitAsync(cancellationToken);
        try
        {
            await StopScanAsync(cancellationToken);
            await DisconnectCoreAsync(cancellationToken);
            EmitStatus("Connecting");

            await _bluetoothClient.ConnectAsync(
            deviceId,
            new BluetoothConnectionOptions(
                RequiredCharacteristicUuids: new[]
                {
                    _options.BatteryCharacteristicUuid,
                    _options.FirmwareCharacteristicUuid,
                    _options.ModelCharacteristicUuid,
                    _options.ControlCharacteristicUuid,
                    _options.StatusCharacteristicUuid
                },
                OptionalCharacteristicUuids: new[] { _options.MeasurementCharacteristicUuid },
                ServiceDiscoveryMaxAttempts: _options.ServiceDiscoveryMaxAttempts,
                ServiceDiscoveryRetryDelay: _options.ServiceDiscoveryRetryDelay),
            cancellationToken);

            _isConnected = true;

            var battery = await _bluetoothClient.ReadCharacteristicAsync(_options.BatteryCharacteristicUuid, cancellationToken);
            if (battery.Length > 0)
            {
                EmitBattery(battery[0]);
            }

            var firmware = await _bluetoothClient.ReadCharacteristicAsync(_options.FirmwareCharacteristicUuid, cancellationToken);
            if (firmware.Length > 0)
            {
                EmitFirmware(EncodingAscii(firmware));
            }

            await _bluetoothClient.SubscribeToCharacteristicAsync(_options.MeasurementCharacteristicUuid, cancellationToken);
            await _bluetoothClient.SubscribeToCharacteristicAsync(_options.StatusCharacteristicUuid, cancellationToken);
            await _bluetoothClient.SubscribeToCharacteristicAsync(_options.ControlCharacteristicUuid, cancellationToken);

            EmitStatus("Connected");
            EmitReady(true);
            StartHeartbeat();
        }
        catch (OperationCanceledException)
        {
            EmitError("R10 connection timed out. Verify the device is powered on and paired.");
            EmitStatus("Disconnected");
            await DisconnectCoreAsync(CancellationToken.None);
        }
        catch (Exception ex)
        {
            EmitError($"R10 connection failed: {ex.Message}");
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
        var acquired = await _connectionLock.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false);
        try
        {
            await DisconnectCoreAsync(cancellationToken).ConfigureAwait(false);
            EmitStatus("Disconnected");
            EmitReady(false);
        }
        finally
        {
            if (acquired)
            {
                _connectionLock.Release();
            }
        }
    }

    public void SetHandedness(int handedness)
    {
        _ = handedness;
    }

    public async Task SetReadyAsync(CancellationToken cancellationToken = default)
    {
        _logInfo("SetReady requested.");
        if (!_isConnected)
        {
            return;
        }

        await WriteKeepaliveAsync(cancellationToken).ConfigureAwait(false);
        EmitReady(true);
    }

    public async ValueTask DisposeAsync()
    {
        _bluetoothClient.DeviceDiscovered -= OnDeviceDiscovered;
        _bluetoothClient.CharacteristicValueChanged -= OnCharacteristicValueChanged;
        _bluetoothClient.Disconnected -= OnBluetoothDisconnected;
        await DisconnectAsync();
        await _bluetoothClient.DisposeAsync();
        _connectionLock.Dispose();
        _heartbeatTimer?.Dispose();
    }

    private async Task DisconnectCoreAsync(CancellationToken cancellationToken)
    {
        StopHeartbeat();
        _isConnected = false;
        await _bluetoothClient.DisconnectAsync(cancellationToken).ConfigureAwait(false);
    }

    private void OnDeviceDiscovered(BluetoothDevice device)
    {
        DeviceDiscovered?.Invoke(device);
    }

    private void OnBluetoothDisconnected()
    {
        _isConnected = false;
        EmitStatus("Disconnected");
        EmitReady(false);
    }

    private void OnCharacteristicValueChanged(BluetoothCharacteristicValue value)
    {
        if (value.CharacteristicUuid == _options.MeasurementCharacteristicUuid)
        {
            var handled = false;
            if (R10Protocol.TryParseShot(value.Value, out var metrics))
            {
                ShotReceived?.Invoke(metrics);
                handled = true;

                // If speed is missing or zero, or diagnostics are enabled, capture detailed diagnostics for analysis.
                if (_options.EnableDiagnostics || metrics.BallSpeedMps <= 0.001f)
                {
                    try
                    {
                        var hex = BitConverter.ToString(value.Value);
                        var ascii = Encoding.ASCII.GetString(value.Value).Trim();
                        _logInfo($"Parsed shot (diagnostics) Hex={hex}; ASCII='{ascii}'; Len={value.Value.Length}");

                        // build LE and BE float lists for inspection
                        var leList = new System.Collections.Generic.List<float>();
                        var beList = new System.Collections.Generic.List<float>();
                        for (var i = 0; i + 3 < value.Value.Length; i += 4)
                        {
                            var chunk = new byte[4];
                            Array.Copy(value.Value, i, chunk, 0, 4);
                            var vLe = BitConverter.ToSingle(chunk, 0);
                            leList.Add(vLe);
                            var chunkBe = new byte[4] { chunk[3], chunk[2], chunk[1], chunk[0] };
                            var vBe = BitConverter.ToSingle(chunkBe, 0);
                            beList.Add(vBe);
                        }

                        int firstIntLe = 0; int firstIntBe = 0; long firstUIntLe = 0; long firstUIntBe = 0;
                        if (value.Value.Length >= 4)
                        {
                            firstIntLe = BitConverter.ToInt32(value.Value, 0);
                            var tmp = new byte[4] { value.Value[3], value.Value[2], value.Value[1], value.Value[0] };
                            firstIntBe = BitConverter.ToInt32(tmp, 0);
                            firstUIntLe = (uint)firstIntLe;
                            firstUIntBe = (uint)firstIntBe;
                        }

                        var logPath = Path.Combine(Path.GetTempPath(), "HeckleGolfSim_r10_payloads.log");
                        var line = new System.Text.StringBuilder();
                        line.AppendLine($"{DateTime.UtcNow:o} DIAG MEAS len={value.Value.Length} hex={hex} ascii={ascii}");
                        line.AppendLine($"RawHex={hex}");
                        line.AppendLine($"LE floats: {string.Join(",", leList)}");
                        line.AppendLine($"BE floats: {string.Join(",", beList)}");
                        line.AppendLine($"firstIntLe={firstIntLe} firstIntBe={firstIntBe} firstUIntLe={firstUIntLe} firstUIntBe={firstUIntBe}");
                        try
                        {
                            var bestOffset = R10Protocol.DetectBestOffset(value.Value);
                            line.AppendLine($"Detected best offset: {bestOffset}");
                        }
                        catch { }

                        // Attempt COBS framed decode + CRC/proto dump for correlation with gsp-r10
                        try
                        {
                            var decoded = COBS.Decode(value.Value).ToArray();
                            line.AppendLine($"COBS decoded len={decoded.Length} hex={BitConverter.ToString(decoded)}");

                            if (decoded.Length == 0)
                            {
                                try
                                {
                                    var withDelim = value.Value.Concat(new byte[] { 0x00 }).ToArray();
                                    var decoded2 = COBS.Decode(withDelim).ToArray();
                                    line.AppendLine($"COBS decode with appended 00 len={decoded2.Length} hex={BitConverter.ToString(decoded2)}");
                                    if (decoded2.Length > 0) decoded = decoded2;
                                }
                                catch (Exception ex3)
                                {
                                    line.AppendLine($"COBS decode with appended 00 failed: {ex3.Message}");
                                }
                            }
                            line.AppendLine($"COBS decoded len={decoded.Length} hex={BitConverter.ToString(decoded)}");

                            if (decoded.Length >= 2)
                            {
                                var dataWithoutCrc = decoded.Take(decoded.Length - 2).ToArray();
                                var crcInFrame = new byte[] { decoded[decoded.Length - 2], decoded[decoded.Length - 1] };
                                var computedCrc = Crc16.ComputeChecksum(dataWithoutCrc);
                                var crcMatch = crcInFrame.Length == computedCrc.Length && crcInFrame[0] == computedCrc[0] && crcInFrame[1] == computedCrc[1];
                                line.AppendLine($"Frame CRC inFrame={BitConverter.ToString(crcInFrame)} computed={BitConverter.ToString(computedCrc)} match={crcMatch}");

                                line.AppendLine($"Proto bytes len={dataWithoutCrc.Length} hex={BitConverter.ToString(dataWithoutCrc)}");
                                try
                                {
                                    var protoAscii = Encoding.ASCII.GetString(dataWithoutCrc).Trim('\0');
                                    line.AppendLine($"Proto ASCII (trimmed)='{protoAscii}'");
                                }
                                catch { }
                            }
                        }
                        catch (Exception ex2)
                        {
                            line.AppendLine($"Framed decode failed: {ex2.Message}");
                        }

                        line.AppendLine($"Metrics: Speed={metrics.BallSpeedMps} VLA={metrics.VerticalAngle} HLA={metrics.HorizontalAngle} Smash={metrics.SmashFactor}");
                        line.AppendLine("---");
                        File.AppendAllText(logPath, line.ToString());
                    }
                    catch (Exception ex)
                    {
                        _logError($"Failed to write diagnostics: {ex.Message}");
                    }
                }
            }

            if (R10Protocol.TryParseSensor(value.Value, out var sensor))
            {
                SensorDataReceived?.Invoke(sensor);
                handled = true;
            }

            if (!handled)
            {
                try
                {
                    var hex = BitConverter.ToString(value.Value);
                    var ascii = Encoding.ASCII.GetString(value.Value).Trim();
                    _logInfo($"Unrecognized R10 measurement payload. Hex={hex}; ASCII='{ascii}'; Len={value.Value.Length}");
                    try
                    {
                        var logPath = Path.Combine(Path.GetTempPath(), "HeckleGolfSim_r10_payloads.log");
                        var line = $"{DateTime.UtcNow:o} MEAS len={value.Value.Length} hex={hex} ascii={ascii}{Environment.NewLine}";
                        File.AppendAllText(logPath, line);
                    }
                    catch (Exception fex)
                    {
                        _logError($"Failed to write payload sample file: {fex.Message}");
                    }
                }
                catch (Exception ex)
                {
                    _logError($"Failed to log unknown measurement payload: {ex.Message}");
                }
            }
        }

        if (value.CharacteristicUuid == _options.StatusCharacteristicUuid)
        {
            if (R10Protocol.TryParseReady(value.Value, out var ready))
            {
                EmitReady(ready);
            }
            else
            {
                try
                {
                    var hex = BitConverter.ToString(value.Value);
                    var text = Encoding.ASCII.GetString(value.Value).Trim();
                    _logInfo($"Unrecognized R10 status payload. Hex={hex}; Text='{text}'; Len={value.Value.Length}");
                }
                catch (Exception ex)
                {
                    _logError($"Failed to log unknown status payload: {ex.Message}");
                }
            }
        }
    }

    private async Task WriteKeepaliveAsync(CancellationToken cancellationToken = default)
    {
        if (!_isConnected)
        {
            return;
        }

        try
        {
            await _bluetoothClient.WriteCharacteristicAsync(
                _options.ControlCharacteristicUuid,
                new byte[] { 0x00 },
                BluetoothWriteMode.WithResponse,
                cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logError($"Keepalive write failed: {ex.Message}");
        }
    }

    private void StartHeartbeat()
    {
        _heartbeatTimer?.Change(_options.HeartbeatInterval, _options.HeartbeatInterval);
    }

    private void StopHeartbeat()
    {
        _heartbeatTimer?.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    private void EmitStatus(string status)
    {
        StatusChanged?.Invoke(status);
    }

    private void EmitError(string message)
    {
        ErrorOccurred?.Invoke(message);
    }

    private void EmitBattery(int value)
    {
        BatteryChanged?.Invoke(value);
    }

    private void EmitFirmware(string firmware)
    {
        FirmwareChanged?.Invoke(firmware);
    }

    private void EmitReady(bool ready)
    {
        ReadyChanged?.Invoke(ready);
    }

    private static string EncodingAscii(byte[] data)
    {
        try
        {
            return Encoding.ASCII.GetString(data).Trim('\0', ' ', '\t', '\r', '\n');
        }
        catch
        {
            return string.Empty;
        }
    }
}
