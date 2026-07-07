using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace LaunchMonitors.Common.Bluetooth.Android;

internal sealed partial class AndroidBluetoothGattClient : IBluetoothGattClient
{
    private static readonly string LogPrefix = "[AndroidBLE]";
    
    public event Action<BluetoothDevice>? DeviceDiscovered;
    public event Action<BluetoothCharacteristicValue>? CharacteristicValueChanged;
    
    private JavaObject? _bluetoothAdapter;
    private JavaObject? _bluetoothScanner;
    private JavaObject? _bluetoothGatt;
    private JavaObject? _scanCallback;
    private JavaObject? _gattCallback;
    
    private AndroidScanListener? _scanListener;
    private AndroidGattListener? _gattListener;
    
    private TaskCompletionSource<bool>? _connectTcs;
    private TaskCompletionSource<bool>? _servicesTcs;
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<byte[]>> _readTcsMap = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<bool>> _writeTcsMap = new();
    
    public AndroidBluetoothGattClient()
    {
        InitializeAndroidBle();
    }
    
    private void InitializeAndroidBle()
    {
        try
        {
            var activity = Engine.GetSingleton("GodotAndroid") as JavaObject;
            if (activity == null)
            {
                GD.PrintErr($"{LogPrefix} GodotAndroid singleton not found.");
                return;
            }
            
            var context = activity.Call("getApplicationContext").As<JavaObject>();
            var bluetoothManager = context.Call("getSystemService", "bluetooth").As<JavaObject>();
            if (bluetoothManager != null)
            {
                _bluetoothAdapter = bluetoothManager.Call("getAdapter").As<JavaObject>();
            }
            
            if (_bluetoothAdapter != null)
            {
                _bluetoothScanner = _bluetoothAdapter.Call("getBluetoothLeScanner").As<JavaObject>();
                GD.Print($"{LogPrefix} Android Bluetooth Adapter and LeScanner initialized successfully.");
            }
            else
            {
                GD.PrintErr($"{LogPrefix} Bluetooth Adapter not available.");
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to initialize Android BLE: {ex}");
        }
    }
    
    public Task StartScanAsync(BluetoothScanOptions options, CancellationToken cancellationToken)
    {
        if (_bluetoothScanner == null)
        {
            throw new InvalidOperationException("Bluetooth LE Scanner not available.");
        }
        
        var javaClassWrapper = Engine.GetSingleton("JavaClassWrapper");
        _scanListener = new AndroidScanListener(this);
        var proxy = javaClassWrapper.Call("create_proxy", _scanListener, new string[] { "com.godot.game.GodotBleHelper$ScanListener" }).As<JavaObject>();
        
        var helperClass = javaClassWrapper.Call("wrap", "com.godot.game.GodotBleHelper").As<JavaObject>();
        _scanCallback = helperClass.Call("createScanCallback", proxy).As<JavaObject>();
        
        _bluetoothScanner.Call("startScan", _scanCallback);
        GD.Print($"{LogPrefix} Started BLE scan.");
        return Task.CompletedTask;
    }
    
    public Task StopScanAsync(CancellationToken cancellationToken)
    {
        if (_bluetoothScanner != null && _scanCallback != null)
        {
            _bluetoothScanner.Call("stopScan", _scanCallback);
            GD.Print($"{LogPrefix} Stopped BLE scan.");
        }
        _scanCallback = null;
        _scanListener = null;
        return Task.CompletedTask;
    }
    
    public async Task ConnectAsync(string deviceId, BluetoothConnectionOptions options, CancellationToken cancellationToken)
    {
        if (_bluetoothAdapter == null)
        {
            throw new InvalidOperationException("Bluetooth Adapter not available.");
        }
        
        var javaClassWrapper = Engine.GetSingleton("JavaClassWrapper");
        var device = _bluetoothAdapter.Call("getRemoteDevice", deviceId).As<JavaObject>();
        if (device == null)
        {
            throw new InvalidOperationException($"Could not find device with ID: {deviceId}");
        }
        
        _connectTcs = new TaskCompletionSource<bool>();
        _servicesTcs = new TaskCompletionSource<bool>();
        
        _gattListener = new AndroidGattListener(this);
        var proxy = javaClassWrapper.Call("create_proxy", _gattListener, new string[] { "com.godot.game.GodotBleHelper$GattListener" }).As<JavaObject>();
        
        var helperClass = javaClassWrapper.Call("wrap", "com.godot.game.GodotBleHelper").As<JavaObject>();
        _gattCallback = helperClass.Call("createGattCallback", proxy).As<JavaObject>();
        
        var activity = Engine.GetSingleton("GodotAndroid") as JavaObject;
        var context = activity.Call("getApplicationContext").As<JavaObject>();
        
        _bluetoothGatt = device.Call("connectGatt", context, false, _gattCallback).As<JavaObject>();
        if (_bluetoothGatt == null)
        {
            throw new InvalidOperationException("Failed to initiate connectGatt.");
        }
        
        using (cancellationToken.Register(() => _connectTcs.TrySetCanceled()))
        {
            await _connectTcs.Task;
        }
        
        _bluetoothGatt.Call("discoverServices");
        using (cancellationToken.Register(() => _servicesTcs.TrySetCanceled()))
        {
            await _servicesTcs.Task;
        }
    }
    
    public Task DisconnectAsync(CancellationToken cancellationToken)
    {
        if (_bluetoothGatt != null)
        {
            _bluetoothGatt.Call("disconnect");
            _bluetoothGatt.Call("close");
            _bluetoothGatt = null;
            GD.Print($"{LogPrefix} Disconnected and closed GATT client.");
        }
        return Task.CompletedTask;
    }
    
    public ValueTask DisposeAsync()
    {
        _ = DisconnectAsync(CancellationToken.None);
        return ValueTask.CompletedTask;
    }
    
    public async Task<byte[]> ReadCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        if (_bluetoothGatt == null)
        {
            throw new InvalidOperationException("Not connected to GATT server.");
        }
        
        var characteristic = GetCharacteristic(characteristicUuid);
        if (characteristic == null)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found.");
        }
        
        var tcs = new TaskCompletionSource<byte[]>();
        _readTcsMap[characteristicUuid] = tcs;
        
        _bluetoothGatt.Call("readCharacteristic", characteristic);
        
        using (cancellationToken.Register(() => tcs.TrySetCanceled()))
        {
            return await tcs.Task;
        }
    }
    
    public Task SubscribeToCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        if (_bluetoothGatt == null)
        {
            throw new InvalidOperationException("Not connected to GATT server.");
        }
        
        var characteristic = GetCharacteristic(characteristicUuid);
        if (characteristic == null)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found.");
        }
        
        _bluetoothGatt.Call("setCharacteristicNotification", characteristic, true);
        
        var clientConfigDescriptorUuid = Guid.Parse("00002902-0000-1000-8000-00805f9b34fb");
        var javaClassWrapper = Engine.GetSingleton("JavaClassWrapper");
        var uuidClass = javaClassWrapper.Call("wrap", "java.util.UUID").As<JavaObject>();
        var descriptor = characteristic.Call("getDescriptor", uuidClass.Call("fromString", clientConfigDescriptorUuid.ToString())).As<JavaObject>();
        if (descriptor != null)
        {
            byte[] enableNotificationValue = new byte[] { 0x01, 0x00 };
            descriptor.Call("setValue", enableNotificationValue);
            _bluetoothGatt.Call("writeDescriptor", descriptor);
            GD.Print($"{LogPrefix} Subscribed and enabled notifications for characteristic: {characteristicUuid}");
        }
        
        return Task.CompletedTask;
    }
    
    public async Task WriteCharacteristicAsync(Guid characteristicUuid, byte[] value, BluetoothWriteMode writeMode, CancellationToken cancellationToken)
    {
        if (_bluetoothGatt == null)
        {
            throw new InvalidOperationException("Not connected to GATT server.");
        }
        
        var characteristic = GetCharacteristic(characteristicUuid);
        if (characteristic == null)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found.");
        }
        
        characteristic.Call("setValue", value);
        
        int writeType = writeMode == BluetoothWriteMode.WithoutResponse ? 1 : 2;
        characteristic.Call("setWriteType", writeType);
        
        var tcs = new TaskCompletionSource<bool>();
        _writeTcsMap[characteristicUuid] = tcs;
        
        _bluetoothGatt.Call("writeCharacteristic", characteristic);
        
        if (writeMode == BluetoothWriteMode.WithResponse)
        {
            using (cancellationToken.Register(() => tcs.TrySetCanceled()))
            {
                await tcs.Task;
            }
        }
    }
    
    private JavaObject? GetCharacteristic(Guid uuid)
    {
        if (_bluetoothGatt == null) return null;
        
        var services = _bluetoothGatt.Call("getServices").As<JavaObject>();
        if (services == null) return null;
        
        int servicesCount = (int)services.Call("size");
        for (int i = 0; i < servicesCount; i++)
        {
            var service = services.Call("get", i).As<JavaObject>();
            if (service == null) continue;
            
            var characteristics = service.Call("getCharacteristics").As<JavaObject>();
            if (characteristics == null) continue;
            
            int charCount = (int)characteristics.Call("size");
            for (int j = 0; j < charCount; j++)
            {
                var characteristic = characteristics.Call("get", j).As<JavaObject>();
                if (characteristic == null) continue;
                
                var charUuidStr = characteristic.Call("getUuid").As<JavaObject>().Call("toString").As<string>();
                if (Guid.TryParse(charUuidStr, out var charUuid) && charUuid == uuid)
                {
                    return characteristic;
                }
            }
        }
        return null;
    }
    
    internal void OnDeviceDiscovered(string deviceId, string name, int rssi)
    {
        DeviceDiscovered?.Invoke(new BluetoothDevice(deviceId, name, rssi));
    }
    
    internal void OnConnectionStateChange(int status, int newState)
    {
        if (status == 0) // GATT_SUCCESS
        {
            if (newState == 2) // STATE_CONNECTED
            {
                GD.Print($"{LogPrefix} Connected to GATT server.");
                _connectTcs?.TrySetResult(true);
            }
            else if (newState == 0) // STATE_DISCONNECTED
            {
                GD.Print($"{LogPrefix} Disconnected from GATT server.");
                _connectTcs?.TrySetResult(false);
            }
        }
        else
        {
            GD.PrintErr($"{LogPrefix} GATT error: status={status}, newState={newState}");
            _connectTcs?.TrySetException(new Exception($"GATT connection failed with status: {status}"));
        }
    }
    
    internal void OnServicesDiscovered(int status)
    {
        if (status == 0) // GATT_SUCCESS
        {
            GD.Print($"{LogPrefix} GATT Services discovered.");
            _servicesTcs?.TrySetResult(true);
        }
        else
        {
            GD.PrintErr($"{LogPrefix} Services discovery failed with status: {status}");
            _servicesTcs?.TrySetException(new Exception($"GATT services discovery failed with status: {status}"));
        }
    }
    
    internal void OnCharacteristicRead(string uuidStr, byte[] value, int status)
    {
        if (Guid.TryParse(uuidStr, out var uuid) && _readTcsMap.TryRemove(uuid, out var tcs))
        {
            if (status == 0) // GATT_SUCCESS
            {
                tcs.TrySetResult(value);
            }
            else
            {
                tcs.TrySetException(new Exception($"Read characteristic failed with status: {status}"));
            }
        }
    }
    
    internal void OnCharacteristicWrite(string uuidStr, int status)
    {
        if (Guid.TryParse(uuidStr, out var uuid) && _writeTcsMap.TryRemove(uuid, out var tcs))
        {
            if (status == 0) // GATT_SUCCESS
            {
                tcs.TrySetResult(true);
            }
            else
            {
                tcs.TrySetException(new Exception($"Write characteristic failed with status: {status}"));
            }
        }
    }
    
    internal void OnCharacteristicChanged(string uuidStr, byte[] value)
    {
        if (Guid.TryParse(uuidStr, out var uuid))
        {
            CharacteristicValueChanged?.Invoke(new BluetoothCharacteristicValue(uuid, value));
        }
    }
    
    private partial class AndroidScanListener : GodotObject
    {
        private readonly AndroidBluetoothGattClient _client;
        public AndroidScanListener(AndroidBluetoothGattClient client) { _client = client; }
        
        public void onDeviceDiscovered(string deviceId, string name, int rssi)
        {
            _client.OnDeviceDiscovered(deviceId, name, rssi);
        }
    }
    
    private partial class AndroidGattListener : GodotObject
    {
        private readonly AndroidBluetoothGattClient _client;
        public AndroidGattListener(AndroidBluetoothGattClient client) { _client = client; }
        
        public void onConnectionStateChange(int status, int newState)
        {
            _client.OnConnectionStateChange(status, newState);
        }
        
        public void onServicesDiscovered(int status)
        {
            _client.OnServicesDiscovered(status);
        }
        
        public void onCharacteristicRead(string uuid, byte[] value, int status)
        {
            _client.OnCharacteristicRead(uuid, value, status);
        }
        
        public void onCharacteristicWrite(string uuid, int status)
        {
            _client.OnCharacteristicWrite(uuid, status);
        }
        
        public void onCharacteristicChanged(string uuid, byte[] value)
        {
            _client.OnCharacteristicChanged(uuid, value);
        }
    }
}
