using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace LaunchMonitors.Common.Bluetooth.Apple;

internal sealed class AppleBluetoothGattClient : IBluetoothGattClient
{
    private const string LogPrefix = "[AppleBLE]";

    public event Action<BluetoothDevice>? DeviceDiscovered;
    public event Action<BluetoothCharacteristicValue>? CharacteristicValueChanged;
    public event Action? Disconnected;

    private static readonly ConcurrentDictionary<IntPtr, AppleBluetoothGattClient> _instances = new();
    private static bool _classesRegistered;
    private static readonly object _initLock = new();

    private IntPtr _centralManager;
    private IntPtr _centralDelegate;
    private IntPtr _peripheralDelegate;
    private IntPtr _activePeripheral;

    private BluetoothScanOptions _scanOptions = new(string.Empty);
    private BluetoothConnectionOptions _connectionOptions = new([], [], 4, TimeSpan.FromMilliseconds(700));

    private readonly ConcurrentDictionary<string, IntPtr> _discoveredPeripherals = new();
    private readonly ConcurrentDictionary<Guid, IntPtr> _characteristics = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<byte[]>> _readTcsMap = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<bool>> _writeTcsMap = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<bool>> _subscribeTcsMap = new();

    private TaskCompletionSource<bool>? _statePoweredOnTcs;
    private TaskCompletionSource<bool>? _connectTcs;
    private int _centralState;
    private bool _isDisposed;

    // Delegates kept alive as static references
    private static readonly CentralDidUpdateStateDelegate _centralDidUpdateState = Central_DidUpdateState;
    private static readonly CentralDidDiscoverPeripheralDelegate _centralDidDiscoverPeripheral = Central_DidDiscoverPeripheral;
    private static readonly CentralDidConnectPeripheralDelegate _centralDidConnectPeripheral = Central_DidConnectPeripheral;
    private static readonly CentralDidFailToConnectPeripheralDelegate _centralDidFailToConnectPeripheral = Central_DidFailToConnectPeripheral;
    private static readonly CentralDidDisconnectPeripheralDelegate _centralDidDisconnectPeripheral = Central_DidDisconnectPeripheral;

    private static readonly PeripheralDidDiscoverServicesDelegate _peripheralDidDiscoverServices = Peripheral_DidDiscoverServices;
    private static readonly PeripheralDidDiscoverCharacteristicsDelegate _peripheralDidDiscoverCharacteristics = Peripheral_DidDiscoverCharacteristics;
    private static readonly PeripheralDidUpdateValueDelegate _peripheralDidUpdateValue = Peripheral_DidUpdateValue;
    private static readonly PeripheralDidWriteValueDelegate _peripheralDidWriteValue = Peripheral_DidWriteValue;
    private static readonly PeripheralDidUpdateNotificationStateDelegate _peripheralDidUpdateNotificationState = Peripheral_DidUpdateNotificationState;

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CentralDidUpdateStateDelegate(IntPtr self, IntPtr _cmd, IntPtr central);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CentralDidDiscoverPeripheralDelegate(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr advData, IntPtr rssi);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CentralDidConnectPeripheralDelegate(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CentralDidFailToConnectPeripheralDelegate(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CentralDidDisconnectPeripheralDelegate(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PeripheralDidDiscoverServicesDelegate(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PeripheralDidDiscoverCharacteristicsDelegate(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr service, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PeripheralDidUpdateValueDelegate(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PeripheralDidWriteValueDelegate(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PeripheralDidUpdateNotificationStateDelegate(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error);

    public AppleBluetoothGattClient()
    {
        ObjCRuntime.EnsureFrameworksLoaded();
        EnsureClassesRegistered();
        InitializeCentralManager();
    }

    private static void EnsureClassesRegistered()
    {
        if (_classesRegistered) return;
        lock (_initLock)
        {
            if (_classesRegistered) return;

            IntPtr nsObjectClass = ObjCRuntime.objc_getClass("NSObject");

            // 1. Central Manager Delegate Class
            IntPtr centralClass = ObjCRuntime.objc_allocateClassPair(nsObjectClass, "HeckleBleCentralDelegate", IntPtr.Zero);
            if (centralClass != IntPtr.Zero)
            {
                ObjCRuntime.class_addMethod(centralClass, ObjCRuntime.sel_registerName("centralManagerDidUpdateState:"),
                    Marshal.GetFunctionPointerForDelegate(_centralDidUpdateState), "v@:@");
                ObjCRuntime.class_addMethod(centralClass, ObjCRuntime.sel_registerName("centralManager:didDiscoverPeripheral:advertisementData:RSSI:"),
                    Marshal.GetFunctionPointerForDelegate(_centralDidDiscoverPeripheral), "v@:@@@@");
                ObjCRuntime.class_addMethod(centralClass, ObjCRuntime.sel_registerName("centralManager:didConnectPeripheral:"),
                    Marshal.GetFunctionPointerForDelegate(_centralDidConnectPeripheral), "v@:@@");
                ObjCRuntime.class_addMethod(centralClass, ObjCRuntime.sel_registerName("centralManager:didFailToConnectPeripheral:error:"),
                    Marshal.GetFunctionPointerForDelegate(_centralDidFailToConnectPeripheral), "v@:@@@");
                ObjCRuntime.class_addMethod(centralClass, ObjCRuntime.sel_registerName("centralManager:didDisconnectPeripheral:error:"),
                    Marshal.GetFunctionPointerForDelegate(_centralDidDisconnectPeripheral), "v@:@@@");
                ObjCRuntime.objc_registerClassPair(centralClass);
            }

            // 2. Peripheral Delegate Class
            IntPtr peripheralClass = ObjCRuntime.objc_allocateClassPair(nsObjectClass, "HeckleBlePeripheralDelegate", IntPtr.Zero);
            if (peripheralClass != IntPtr.Zero)
            {
                ObjCRuntime.class_addMethod(peripheralClass, ObjCRuntime.sel_registerName("peripheral:didDiscoverServices:"),
                    Marshal.GetFunctionPointerForDelegate(_peripheralDidDiscoverServices), "v@:@@");
                ObjCRuntime.class_addMethod(peripheralClass, ObjCRuntime.sel_registerName("peripheral:didDiscoverCharacteristicsForService:error:"),
                    Marshal.GetFunctionPointerForDelegate(_peripheralDidDiscoverCharacteristics), "v@:@@@");
                ObjCRuntime.class_addMethod(peripheralClass, ObjCRuntime.sel_registerName("peripheral:didUpdateValueForCharacteristic:error:"),
                    Marshal.GetFunctionPointerForDelegate(_peripheralDidUpdateValue), "v@:@@@");
                ObjCRuntime.class_addMethod(peripheralClass, ObjCRuntime.sel_registerName("peripheral:didWriteValueForCharacteristic:error:"),
                    Marshal.GetFunctionPointerForDelegate(_peripheralDidWriteValue), "v@:@@@");
                ObjCRuntime.class_addMethod(peripheralClass, ObjCRuntime.sel_registerName("peripheral:didUpdateNotificationStateForCharacteristic:error:"),
                    Marshal.GetFunctionPointerForDelegate(_peripheralDidUpdateNotificationState), "v@:@@@");
                ObjCRuntime.objc_registerClassPair(peripheralClass);
            }

            _classesRegistered = true;
            GD.Print($"{LogPrefix} Objective-C delegates registered successfully.");
        }
    }

    private void InitializeCentralManager()
    {
        _statePoweredOnTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        IntPtr centralDelegateCls = ObjCRuntime.objc_getClass("HeckleBleCentralDelegate");
        _centralDelegate = ObjCRuntime.objc_msgSend(ObjCRuntime.objc_msgSend(centralDelegateCls, ObjCRuntime.sel_registerName("alloc")), ObjCRuntime.sel_registerName("init"));
        ObjCRuntime.Retain(_centralDelegate);
        _instances[_centralDelegate] = this;

        IntPtr peripheralDelegateCls = ObjCRuntime.objc_getClass("HeckleBlePeripheralDelegate");
        _peripheralDelegate = ObjCRuntime.objc_msgSend(ObjCRuntime.objc_msgSend(peripheralDelegateCls, ObjCRuntime.sel_registerName("alloc")), ObjCRuntime.sel_registerName("init"));
        ObjCRuntime.Retain(_peripheralDelegate);
        _instances[_peripheralDelegate] = this;

        IntPtr cbCentralManagerClass = ObjCRuntime.objc_getClass("CBCentralManager");
        IntPtr allocCentral = ObjCRuntime.objc_msgSend(cbCentralManagerClass, ObjCRuntime.sel_registerName("alloc"));

        // [[CBCentralManager alloc] initWithDelegate:delegate queue:nil options:nil]
        _centralManager = ObjCRuntime.objc_msgSend(allocCentral, ObjCRuntime.sel_registerName("initWithDelegate:queue:options:"), _centralDelegate, IntPtr.Zero, IntPtr.Zero);
        ObjCRuntime.Retain(_centralManager);

        GD.Print($"{LogPrefix} CBCentralManager instantiated.");
    }

    private async Task EnsureCentralReadyAsync(CancellationToken cancellationToken)
    {
        if (_centralState == 5) return; // 5 = CBManagerStatePoweredOn
        if (_statePoweredOnTcs != null)
        {
            using var reg = cancellationToken.Register(() => _statePoweredOnTcs.TrySetCanceled());
            await _statePoweredOnTcs.Task;
        }
    }

    public async Task StartScanAsync(BluetoothScanOptions options, CancellationToken cancellationToken)
    {
        _scanOptions = options;
        GD.Print($"{LogPrefix} StartScanAsync requested for prefix '{options.DeviceNamePrefix}'. Waiting for CentralManager to power on...");
        await EnsureCentralReadyAsync(cancellationToken);

        // [centralManager scanForPeripheralsWithServices:nil options:nil]
        ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("scanForPeripheralsWithServices:options:"), IntPtr.Zero, IntPtr.Zero);
        GD.Print($"{LogPrefix} Active scanning started.");
    }

    public Task StopScanAsync(CancellationToken cancellationToken)
    {
        if (_centralManager != IntPtr.Zero)
        {
            ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("stopScan"));
            GD.Print($"{LogPrefix} Scanning stopped.");
        }
        return Task.CompletedTask;
    }

    public async Task ConnectAsync(string deviceId, BluetoothConnectionOptions options, CancellationToken cancellationToken)
    {
        _connectionOptions = options;
        await EnsureCentralReadyAsync(cancellationToken);

        IntPtr peripheral = IntPtr.Zero;
        if (_discoveredPeripherals.TryGetValue(deviceId, out var p))
        {
            peripheral = p;
        }
        else if (Guid.TryParse(deviceId, out var guid))
        {
            // Attempt retrievePeripheralsWithIdentifiers:
            IntPtr cbUuid = ObjCRuntime.CreateCBUUID(guid);
            IntPtr nsArrayClass = ObjCRuntime.objc_getClass("NSArray");
            IntPtr idArray = ObjCRuntime.objc_msgSend(nsArrayClass, ObjCRuntime.sel_registerName("arrayWithObject:"), cbUuid);
            IntPtr retrievedArray = ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("retrievePeripheralsWithIdentifiers:"), idArray);
            int count = (int)(long)ObjCRuntime.objc_msgSend(retrievedArray, ObjCRuntime.sel_registerName("count"));
            if (count > 0)
            {
                peripheral = ObjCRuntime.objc_msgSend(retrievedArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)0);
            }
        }

        if (peripheral == IntPtr.Zero)
        {
            throw new InvalidOperationException($"Peripheral with identifier {deviceId} was not found.");
        }

        if (_activePeripheral != IntPtr.Zero && _activePeripheral != peripheral)
        {
            ObjCRuntime.Release(_activePeripheral);
        }

        _activePeripheral = peripheral;
        ObjCRuntime.Retain(_activePeripheral);

        _characteristics.Clear();
        _connectTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        GD.Print($"{LogPrefix} Connecting to peripheral {deviceId}...");
        // [centralManager connectPeripheral:peripheral options:nil]
        ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("connectPeripheral:options:"), _activePeripheral, IntPtr.Zero);

        using var reg = cancellationToken.Register(() => _connectTcs.TrySetCanceled());
        await _connectTcs.Task;
        GD.Print($"{LogPrefix} Connected and GATT characteristics ready!");
    }

    public Task DisconnectAsync(CancellationToken cancellationToken)
    {
        if (_centralManager != IntPtr.Zero && _activePeripheral != IntPtr.Zero)
        {
            ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("cancelPeripheralConnection:"), _activePeripheral);
        }
        return Task.CompletedTask;
    }

    public async Task<byte[]> ReadCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        if (!_characteristics.TryGetValue(characteristicUuid, out var characteristic) || _activePeripheral == IntPtr.Zero)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found or not connected.");
        }

        var tcs = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        _readTcsMap[characteristicUuid] = tcs;

        // [peripheral readValueForCharacteristic:characteristic]
        ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("readValueForCharacteristic:"), characteristic);

        using var reg = cancellationToken.Register(() => tcs.TrySetCanceled());
        return await tcs.Task;
    }

    public async Task SubscribeToCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        if (!_characteristics.TryGetValue(characteristicUuid, out var characteristic) || _activePeripheral == IntPtr.Zero)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found or not connected.");
        }

        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _subscribeTcsMap[characteristicUuid] = tcs;

        // [peripheral setNotifyValue:YES forCharacteristic:characteristic]
        ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("setNotifyValue:forCharacteristic:"), true, characteristic);

        using var reg = cancellationToken.Register(() => tcs.TrySetCanceled());
        await tcs.Task;
    }

    public async Task WriteCharacteristicAsync(
        Guid characteristicUuid,
        byte[] value,
        BluetoothWriteMode writeMode,
        CancellationToken cancellationToken)
    {
        if (!_characteristics.TryGetValue(characteristicUuid, out var characteristic) || _activePeripheral == IntPtr.Zero)
        {
            throw new InvalidOperationException($"Characteristic {characteristicUuid} not found or not connected.");
        }

        IntPtr nsData = ObjCRuntime.CreateNSData(value);
        int writeType = writeMode == BluetoothWriteMode.WithResponse ? 0 : 1; // 0 = CBCharacteristicWriteWithResponse, 1 = CBCharacteristicWriteWithoutResponse

        if (writeMode == BluetoothWriteMode.WithResponse)
        {
            var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            _writeTcsMap[characteristicUuid] = tcs;

            // [peripheral writeValue:nsData forCharacteristic:characteristic type:writeType]
            ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("writeValue:forCharacteristic:type:"), nsData, characteristic, writeType);

            using var reg = cancellationToken.Register(() => tcs.TrySetCanceled());
            await tcs.Task;
        }
        else
        {
            ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("writeValue:forCharacteristic:type:"), nsData, characteristic, writeType);
        }
    }

    public ValueTask DisposeAsync()
    {
        if (_isDisposed) return ValueTask.CompletedTask;
        _isDisposed = true;

        _instances.TryRemove(_centralDelegate, out _);
        _instances.TryRemove(_peripheralDelegate, out _);

        foreach (var p in _discoveredPeripherals.Values)
        {
            ObjCRuntime.Release(p);
        }
        _discoveredPeripherals.Clear();

        foreach (var c in _characteristics.Values)
        {
            ObjCRuntime.Release(c);
        }
        _characteristics.Clear();

        if (_activePeripheral != IntPtr.Zero)
        {
            ObjCRuntime.Release(_activePeripheral);
            _activePeripheral = IntPtr.Zero;
        }

        if (_centralManager != IntPtr.Zero)
        {
            ObjCRuntime.Release(_centralManager);
            _centralManager = IntPtr.Zero;
        }

        if (_centralDelegate != IntPtr.Zero)
        {
            ObjCRuntime.Release(_centralDelegate);
            _centralDelegate = IntPtr.Zero;
        }

        if (_peripheralDelegate != IntPtr.Zero)
        {
            ObjCRuntime.Release(_peripheralDelegate);
            _peripheralDelegate = IntPtr.Zero;
        }

        return ValueTask.CompletedTask;
    }

    // --- Static Delegate Callbacks Routed by Delegate Instance Pointer ---

    private static void Central_DidUpdateState(IntPtr self, IntPtr _cmd, IntPtr central)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        int state = (int)(long)ObjCRuntime.objc_msgSend(central, ObjCRuntime.sel_registerName("state"));
        client._centralState = state;
        GD.Print($"{LogPrefix} CBCentralManager state updated: {state} (5=PoweredOn)");
        if (state == 5) // CBManagerStatePoweredOn
        {
            client._statePoweredOnTcs?.TrySetResult(true);
        }
        else if (state == 1) // CBManagerStateUnauthorized
        {
            GD.PrintErr($"{LogPrefix} Bluetooth permission denied by user / OS. Please check System Settings -> Privacy & Security -> Bluetooth.");
        }
    }

    private static void Central_DidDiscoverPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr advData, IntPtr rssi)
    {
        if (!_instances.TryGetValue(self, out var client)) return;

        IntPtr identifier = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("identifier"));
        IntPtr uuidStringNs = ObjCRuntime.objc_msgSend(identifier, ObjCRuntime.sel_registerName("UUIDString"));
        string deviceId = ObjCRuntime.NSStringToString(uuidStringNs) ?? string.Empty;

        IntPtr nameNs = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("name"));
        string? name = ObjCRuntime.NSStringToString(nameNs);

        if (string.IsNullOrWhiteSpace(name) && advData != IntPtr.Zero)
        {
            IntPtr localNameKey = ObjCRuntime.CreateNSString("kCBAdvDataLocalName");
            IntPtr localNameNs = ObjCRuntime.objc_msgSend(advData, ObjCRuntime.sel_registerName("objectForKey:"), localNameKey);
            name = ObjCRuntime.NSStringToString(localNameNs);
        }

        name ??= "Unknown";
        int rssiVal = (int)(long)ObjCRuntime.objc_msgSend(rssi, ObjCRuntime.sel_registerName("intValue"));

        if (!client._discoveredPeripherals.ContainsKey(deviceId))
        {
            ObjCRuntime.Retain(peripheral);
            client._discoveredPeripherals[deviceId] = peripheral;
        }

        if (!string.IsNullOrEmpty(client._scanOptions.DeviceNamePrefix) &&
            !name.StartsWith(client._scanOptions.DeviceNamePrefix, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        GD.Print($"{LogPrefix} Device discovered: {name} ({deviceId}) RSSI={rssiVal}");
        client.DeviceDiscovered?.Invoke(new BluetoothDevice(deviceId, name, rssiVal));
    }

    private static void Central_DidConnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        GD.Print($"{LogPrefix} Central connected to peripheral. Discovering services...");

        // Set peripheral delegate to client's peripheral delegate
        ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("setDelegate:"), client._peripheralDelegate);

        // [peripheral discoverServices:nil]
        ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("discoverServices:"), IntPtr.Zero);
    }

    private static void Central_DidFailToConnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        string errorDesc = error != IntPtr.Zero ? ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Unknown error" : "Connection failed";
        GD.PrintErr($"{LogPrefix} Failed to connect to peripheral: {errorDesc}");
        client._connectTcs?.TrySetException(new InvalidOperationException(errorDesc));
    }

    private static void Central_DidDisconnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        GD.Print($"{LogPrefix} Peripheral disconnected.");
        client.Disconnected?.Invoke();
    }

    private static void Peripheral_DidDiscoverServices(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        if (error != IntPtr.Zero)
        {
            string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Service discovery failed";
            GD.PrintErr($"{LogPrefix} Error discovering services: {errorDesc}");
            client._connectTcs?.TrySetException(new InvalidOperationException(errorDesc));
            return;
        }

        IntPtr servicesArray = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("services"));
        int count = (int)(long)ObjCRuntime.objc_msgSend(servicesArray, ObjCRuntime.sel_registerName("count"));
        GD.Print($"{LogPrefix} Discovered {count} services. Discovering characteristics for each...");

        for (int i = 0; i < count; i++)
        {
            IntPtr service = ObjCRuntime.objc_msgSend(servicesArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)i);
            ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("discoverCharacteristics:forService:"), IntPtr.Zero, service);
        }
    }

    private static void Peripheral_DidDiscoverCharacteristics(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr service, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;
        if (error != IntPtr.Zero)
        {
            string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Characteristic discovery failed";
            GD.PrintErr($"{LogPrefix} Error discovering characteristics: {errorDesc}");
            return;
        }

        IntPtr charsArray = ObjCRuntime.objc_msgSend(service, ObjCRuntime.sel_registerName("characteristics"));
        int count = (int)(long)ObjCRuntime.objc_msgSend(charsArray, ObjCRuntime.sel_registerName("count"));

        for (int i = 0; i < count; i++)
        {
            IntPtr characteristic = ObjCRuntime.objc_msgSend(charsArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)i);
            IntPtr cbUuid = ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("UUID"));
            var guid = ObjCRuntime.CBUUIDToGuid(cbUuid);
            if (guid.HasValue)
            {
                if (!client._characteristics.ContainsKey(guid.Value))
                {
                    ObjCRuntime.Retain(characteristic);
                    client._characteristics[guid.Value] = characteristic;
                    GD.Print($"{LogPrefix} Characteristic mapped: {guid.Value}");
                }
            }
        }

        // Check if all required characteristics are discovered
        bool allRequiredFound = true;
        foreach (var reqUuid in client._connectionOptions.RequiredCharacteristicUuids)
        {
            if (!client._characteristics.ContainsKey(reqUuid))
            {
                allRequiredFound = false;
                break;
            }
        }

        if (allRequiredFound && client._connectTcs != null && !client._connectTcs.Task.IsCompleted)
        {
            client._connectTcs.TrySetResult(true);
        }
    }

    private static void Peripheral_DidUpdateValue(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;

        IntPtr cbUuid = ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("UUID"));
        var guid = ObjCRuntime.CBUUIDToGuid(cbUuid);
        if (!guid.HasValue) return;

        if (error != IntPtr.Zero)
        {
            string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Read value failed";
            if (client._readTcsMap.TryRemove(guid.Value, out var readTcs))
            {
                readTcs.TrySetException(new InvalidOperationException(errorDesc));
            }
            return;
        }

        IntPtr nsData = ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("value"));
        byte[] value = ObjCRuntime.NSDataToBytes(nsData);

        if (client._readTcsMap.TryRemove(guid.Value, out var tcs))
        {
            tcs.TrySetResult(value);
        }

        client.CharacteristicValueChanged?.Invoke(new BluetoothCharacteristicValue(guid.Value, value));
    }

    private static void Peripheral_DidWriteValue(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;

        IntPtr cbUuid = ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("UUID"));
        var guid = ObjCRuntime.CBUUIDToGuid(cbUuid);
        if (!guid.HasValue) return;

        if (client._writeTcsMap.TryRemove(guid.Value, out var writeTcs))
        {
            if (error != IntPtr.Zero)
            {
                string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Write value failed";
                writeTcs.TrySetException(new InvalidOperationException(errorDesc));
            }
            else
            {
                writeTcs.TrySetResult(true);
            }
        }
    }

    private static void Peripheral_DidUpdateNotificationState(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        if (!_instances.TryGetValue(self, out var client)) return;

        IntPtr cbUuid = ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("UUID"));
        var guid = ObjCRuntime.CBUUIDToGuid(cbUuid);
        if (!guid.HasValue) return;

        if (client._subscribeTcsMap.TryRemove(guid.Value, out var subTcs))
        {
            if (error != IntPtr.Zero)
            {
                string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Subscribe failed";
                subTcs.TrySetException(new InvalidOperationException(errorDesc));
            }
            else
            {
                subTcs.TrySetResult(true);
            }
        }
    }
}
