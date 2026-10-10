using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using LaunchMonitors.Common;

namespace LaunchMonitors.Common.Bluetooth.Apple;

internal sealed class AppleBluetoothGattClient : IBluetoothGattClient
{
    private const string LogPrefix = "[AppleBLE]";

    private static void Log(string message) => DebugLoggerBridge.LogBluetooth($"{LogPrefix} {message}");
    private static void LogErr(string message) => DebugLoggerBridge.LogError($"{LogPrefix} {message}");

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
    private IntPtr _dispatchQueue;

    private BluetoothScanOptions _scanOptions = new(string.Empty);
    private BluetoothConnectionOptions _connectionOptions = new([], [], 4, TimeSpan.FromMilliseconds(700));

    private readonly ConcurrentDictionary<string, IntPtr> _discoveredPeripherals = new();
    private readonly ConcurrentDictionary<string, string> _reportedDeviceNames = new();
    private readonly ConcurrentDictionary<string, bool> _loggedUnknownDevices = new();
    private readonly ConcurrentDictionary<Guid, IntPtr> _characteristics = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<byte[]>> _readTcsMap = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<bool>> _writeTcsMap = new();
    private readonly ConcurrentDictionary<Guid, TaskCompletionSource<bool>> _subscribeTcsMap = new();

    private TaskCompletionSource<bool>? _statePoweredOnTcs;
    private TaskCompletionSource<bool>? _connectTcs;
    private TaskCompletionSource<bool>? _disconnectTcs;
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
            Log("Objective-C delegates registered successfully.");
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

        // Dedicated dispatch queue ensures CoreBluetooth delegate callbacks run smoothly and are not blocked by the main thread
        _dispatchQueue = ObjCRuntime.dispatch_queue_create("com.hecklegolf.ble", IntPtr.Zero);

        // [[CBCentralManager alloc] initWithDelegate:delegate queue:dispatchQueue options:nil]
        _centralManager = ObjCRuntime.objc_msgSend(allocCentral, ObjCRuntime.sel_registerName("initWithDelegate:queue:options:"), _centralDelegate, _dispatchQueue, IntPtr.Zero);
        ObjCRuntime.Retain(_centralManager);

        Log("CBCentralManager instantiated with dedicated dispatch queue.");
    }

    private async Task EnsureCentralReadyAsync(CancellationToken cancellationToken)
    {
        if (_centralState == 5) return; // 5 = CBManagerStatePoweredOn
        if (_statePoweredOnTcs != null)
        {
            using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(6));
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
            using var reg = linkedCts.Token.Register(() => _statePoweredOnTcs.TrySetCanceled());
            try
            {
                await _statePoweredOnTcs.Task;
            }
            catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException("Bluetooth initialization timed out. Please verify Bluetooth is powered on and authorized in macOS/iOS System Settings.");
            }
        }
    }

    public async Task StartScanAsync(BluetoothScanOptions options, CancellationToken cancellationToken)
    {
        _scanOptions = options;
        _reportedDeviceNames.Clear();
        _loggedUnknownDevices.Clear();
        Log($"StartScanAsync requested for prefix '{options.DeviceNamePrefix}'. Waiting for CentralManager to power on...");
        await EnsureCentralReadyAsync(cancellationToken);

        await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
        {
            // CBCentralManagerScanOptionAllowDuplicatesKey = YES ensures scan response packets (holding device name) are processed
            IntPtr scanOptions = ObjCRuntime.CreateScanOptionsDictionary(allowDuplicates: true);
            ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("scanForPeripheralsWithServices:options:"), IntPtr.Zero, scanOptions);
        });
        Log("Active scanning started with duplicate advertisements enabled for scan response resolution.");
    }

    public async Task StopScanAsync(CancellationToken cancellationToken)
    {
        if (_centralManager != IntPtr.Zero)
        {
            await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
            {
                ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("stopScan"));
            });
            Log("Scanning stopped.");
        }
    }

    public async Task ConnectAsync(string deviceId, BluetoothConnectionOptions options, CancellationToken cancellationToken)
    {
        _connectionOptions = options;
        await EnsureCentralReadyAsync(cancellationToken);

        // CoreBluetooth best practice: Stop scanning once connection process begins to eliminate queue contention and duplicate callbacks
        await StopScanAsync(cancellationToken);

        IntPtr peripheral = IntPtr.Zero;
        if (_discoveredPeripherals.TryGetValue(deviceId, out var p))
        {
            peripheral = p;
        }
        else if (Guid.TryParse(deviceId, out var guid))
        {
            // CoreBluetooth retrievePeripheralsWithIdentifiers: expects an NSArray of NSUUID instances
            await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
            {
                IntPtr nsUuid = ObjCRuntime.CreateNSUUID(guid);
                IntPtr nsArrayClass = ObjCRuntime.objc_getClass("NSArray");
                IntPtr idArray = ObjCRuntime.objc_msgSend(nsArrayClass, ObjCRuntime.sel_registerName("arrayWithObject:"), nsUuid);
                IntPtr retrievedArray = ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("retrievePeripheralsWithIdentifiers:"), idArray);
                int count = (int)(long)ObjCRuntime.objc_msgSend(retrievedArray, ObjCRuntime.sel_registerName("count"));
                if (count > 0)
                {
                    peripheral = ObjCRuntime.objc_msgSend(retrievedArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)0);
                }
            });
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

        Log($"Connecting to peripheral {deviceId}...");
        await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
        {
            ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("connectPeripheral:options:"), _activePeripheral, IntPtr.Zero);
        });

        using var reg = cancellationToken.Register(() => _connectTcs.TrySetCanceled());
        await _connectTcs.Task;
        Log("Connected and GATT characteristics ready!");
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken)
    {
        if (_centralManager != IntPtr.Zero && _activePeripheral != IntPtr.Zero)
        {
            int state = 0;
            await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
            {
                if (_activePeripheral != IntPtr.Zero)
                {
                    state = (int)(long)ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("state"));
                }
            });
            if (state == 1 || state == 2) // Connecting or Connected
            {
                var disconnectTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                _disconnectTcs = disconnectTcs;
                await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
                {
                    if (_centralManager != IntPtr.Zero && _activePeripheral != IntPtr.Zero)
                    {
                        ObjCRuntime.objc_msgSend(_centralManager, ObjCRuntime.sel_registerName("cancelPeripheralConnection:"), _activePeripheral);
                    }
                });
                using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(500));
                using var reg = cts.Token.Register(() => disconnectTcs.TrySetResult(true));
                try
                {
                    await disconnectTcs.Task;
                }
                catch
                {
                }
                finally
                {
                    _disconnectTcs = null;
                }
            }
        }
    }

    public async Task<byte[]> ReadCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        // Match WindowsBluetoothGattClient: return empty array if characteristic is not present
        if (!_characteristics.TryGetValue(characteristicUuid, out var characteristic) || _activePeripheral == IntPtr.Zero)
        {
            return Array.Empty<byte>();
        }

        var tcs = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        _readTcsMap[characteristicUuid] = tcs;

        // [peripheral readValueForCharacteristic:characteristic] dispatched to _dispatchQueue for thread confinement
        await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
        {
            if (_activePeripheral != IntPtr.Zero)
            {
                ObjCRuntime.objc_msgSend(_activePeripheral, ObjCRuntime.sel_registerName("readValueForCharacteristic:"), characteristic);
            }
        });

        // Bound read with a 3-second timeout so unacknowledged reads (like firmware) do not hang the connection
        using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        using var reg = linkedCts.Token.Register(() => tcs.TrySetCanceled());

        try
        {
            return await tcs.Task;
        }
        catch (OperationCanceledException)
        {
            _readTcsMap.TryRemove(characteristicUuid, out _);
            return Array.Empty<byte>();
        }
        catch (Exception ex)
        {
            _readTcsMap.TryRemove(characteristicUuid, out _);
            LogErr($"ReadCharacteristicAsync exception for {characteristicUuid}: {ex.Message}");
            return Array.Empty<byte>();
        }
    }

    public async Task SubscribeToCharacteristicAsync(Guid characteristicUuid, CancellationToken cancellationToken)
    {
        if (!_characteristics.TryGetValue(characteristicUuid, out var characteristic) || _activePeripheral == IntPtr.Zero)
        {
            return;
        }

        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _subscribeTcsMap[characteristicUuid] = tcs;

        // [peripheral setNotifyValue:YES forCharacteristic:characteristic] dispatched to _dispatchQueue
        await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
        {
            if (_activePeripheral != IntPtr.Zero)
            {
                ObjCRuntime.objc_msgSend_bool(_activePeripheral, ObjCRuntime.sel_registerName("setNotifyValue:forCharacteristic:"), 1, characteristic);
            }
        });

        using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        using var reg = linkedCts.Token.Register(() => tcs.TrySetCanceled());

        try
        {
            await tcs.Task;
        }
        catch (OperationCanceledException)
        {
            _subscribeTcsMap.TryRemove(characteristicUuid, out _);
        }
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

        // Adapt write mode based on characteristic properties (0x04 = WriteWithoutResponse, 0x08 = WriteWithResponse)
        ulong properties = 0;
        await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
        {
            properties = (ulong)(long)ObjCRuntime.objc_msgSend(characteristic, ObjCRuntime.sel_registerName("properties"));
        });
        bool canWriteWithoutResponse = (properties & 0x04) != 0;
        bool canWriteWithResponse = (properties & 0x08) != 0;

        var effectiveMode = writeMode;
        if (effectiveMode == BluetoothWriteMode.WithResponse && !canWriteWithResponse && canWriteWithoutResponse)
        {
            effectiveMode = BluetoothWriteMode.WithoutResponse;
        }
        else if (effectiveMode == BluetoothWriteMode.WithoutResponse && !canWriteWithoutResponse && canWriteWithResponse)
        {
            effectiveMode = BluetoothWriteMode.WithResponse;
        }

        IntPtr nsData = ObjCRuntime.CreateNSData(value);
        IntPtr writeType = effectiveMode == BluetoothWriteMode.WithResponse ? (IntPtr)0 : (IntPtr)1; // 0 = CBCharacteristicWriteWithResponse, 1 = CBCharacteristicWriteWithoutResponse

        if (effectiveMode == BluetoothWriteMode.WithResponse)
        {
            var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            _writeTcsMap[characteristicUuid] = tcs;

            // [peripheral writeValue:nsData forCharacteristic:characteristic type:writeType] dispatched to _dispatchQueue
            await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
            {
                if (_activePeripheral != IntPtr.Zero)
                {
                    ObjCRuntime.objc_msgSend_write(_activePeripheral, ObjCRuntime.sel_registerName("writeValue:forCharacteristic:type:"), nsData, characteristic, writeType);
                }
            });

            using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
            using var reg = linkedCts.Token.Register(() => tcs.TrySetCanceled());
            try
            {
                await tcs.Task;
            }
            catch (OperationCanceledException) when (canWriteWithoutResponse && !cancellationToken.IsCancellationRequested)
            {
                Log($"Write with response timed out for {characteristicUuid}; falling back to write without response.");
                await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
                {
                    if (_activePeripheral != IntPtr.Zero)
                    {
                        ObjCRuntime.objc_msgSend_write(_activePeripheral, ObjCRuntime.sel_registerName("writeValue:forCharacteristic:type:"), nsData, characteristic, (IntPtr)1);
                    }
                });
            }
            finally
            {
                _writeTcsMap.TryRemove(characteristicUuid, out _);
            }
        }
        else
        {
            await ObjCRuntime.DispatchAsync(_dispatchQueue, () =>
            {
                if (_activePeripheral != IntPtr.Zero)
                {
                    ObjCRuntime.objc_msgSend_write(_activePeripheral, ObjCRuntime.sel_registerName("writeValue:forCharacteristic:type:"), nsData, characteristic, writeType);
                }
            });
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

        _reportedDeviceNames.Clear();
        _loggedUnknownDevices.Clear();
        _dispatchQueue = IntPtr.Zero;

        return ValueTask.CompletedTask;
    }

    // --- Static Delegate Callbacks Routed by Delegate Instance Pointer ---

    private static void Central_DidUpdateState(IntPtr self, IntPtr _cmd, IntPtr central)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            int state = (int)(long)ObjCRuntime.objc_msgSend(central, ObjCRuntime.sel_registerName("state"));
            client._centralState = state;
            Log($"CBCentralManager state updated: {state} (0=Unknown, 1=Resetting, 2=Unsupported, 3=Unauthorized, 4=PoweredOff, 5=PoweredOn)");
            if (state == 5) // CBManagerStatePoweredOn
            {
                client._statePoweredOnTcs?.TrySetResult(true);
            }
            else if (state == 3) // CBManagerStateUnauthorized
            {
                LogErr("Bluetooth permission denied by user / OS. Please check System Settings -> Privacy & Security -> Bluetooth.");
                client._statePoweredOnTcs?.TrySetException(new UnauthorizedAccessException("Bluetooth permission denied by macOS/iOS. Please check System Settings -> Privacy & Security -> Bluetooth."));
            }
            else if (state == 2) // CBManagerStateUnsupported
            {
                LogErr("Bluetooth Low Energy is unsupported on this hardware.");
                client._statePoweredOnTcs?.TrySetException(new NotSupportedException("Bluetooth Low Energy is unsupported on this hardware."));
            }
            else if (state == 4) // CBManagerStatePoweredOff
            {
                LogErr("Bluetooth is powered off. Please turn on Bluetooth in System Settings.");
                client._statePoweredOnTcs?.TrySetException(new InvalidOperationException("Bluetooth is turned off. Please turn on Bluetooth in System Settings."));
            }
        }
        catch (Exception ex)
        {
            LogErr($"Central_DidUpdateState unhandled exception: {ex}");
        }
    }

    private static void Central_DidDiscoverPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr advData, IntPtr rssi)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;

            IntPtr identifier = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("identifier"));
            IntPtr uuidStringNs = ObjCRuntime.objc_msgSend(identifier, ObjCRuntime.sel_registerName("UUIDString"));
            string deviceId = ObjCRuntime.NSStringToString(uuidStringNs) ?? string.Empty;

            IntPtr nameNs = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("name"));
            string? name = ObjCRuntime.NSStringToString(nameNs);

            // 1. Check local name in advertisement data
            if (string.IsNullOrWhiteSpace(name) && advData != IntPtr.Zero)
            {
                IntPtr localNameKey = ObjCRuntime.CreateNSString("kCBAdvDataLocalName");
                IntPtr localNameNs = ObjCRuntime.objc_msgSend(advData, ObjCRuntime.sel_registerName("objectForKey:"), localNameKey);
                name = ObjCRuntime.NSStringToString(localNameNs);
            }

            bool matchesServiceUuid = false;

            // 2. Inspect advertised service UUIDs for known launch monitors
            if (advData != IntPtr.Zero)
            {
                IntPtr serviceUuidsKey = ObjCRuntime.CreateNSString("kCBAdvDataServiceUUIDs");
                IntPtr serviceUuidsArray = ObjCRuntime.objc_msgSend(advData, ObjCRuntime.sel_registerName("objectForKey:"), serviceUuidsKey);
                if (serviceUuidsArray != IntPtr.Zero)
                {
                    int uuidCount = (int)(long)ObjCRuntime.objc_msgSend(serviceUuidsArray, ObjCRuntime.sel_registerName("count"));
                    for (int i = 0; i < uuidCount; i++)
                    {
                        IntPtr cbUuid = ObjCRuntime.objc_msgSend(serviceUuidsArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)i);
                        IntPtr serviceUuidNs = ObjCRuntime.objc_msgSend(cbUuid, ObjCRuntime.sel_registerName("UUIDString"));
                        string? uuidStr = ObjCRuntime.NSStringToString(serviceUuidNs)?.ToLowerInvariant();
                        if (!string.IsNullOrEmpty(uuidStr))
                        {
                            if (uuidStr.Contains("8660"))
                            {
                                if (string.IsNullOrWhiteSpace(name) || name == "Unknown")
                                {
                                    name = "Square Golf";
                                }
                                if (client._scanOptions?.DeviceNamePrefix?.Contains("square", StringComparison.OrdinalIgnoreCase) == true)
                                {
                                    matchesServiceUuid = true;
                                }
                                break;
                            }
                            else if (uuidStr.Contains("6a4e"))
                            {
                                if (string.IsNullOrWhiteSpace(name) || name == "Unknown")
                                {
                                    name = "Approach R10";
                                }
                                if (client._scanOptions?.DeviceNamePrefix?.Contains("approach", StringComparison.OrdinalIgnoreCase) == true ||
                                    client._scanOptions?.DeviceNamePrefix?.Contains("garmin", StringComparison.OrdinalIgnoreCase) == true)
                                {
                                    matchesServiceUuid = true;
                                }
                                break;
                            }
                        }
                    }
                }
            }

            // 3. Inspect Manufacturer Data if name is still unknown
            if (string.IsNullOrWhiteSpace(name) && advData != IntPtr.Zero)
            {
                IntPtr mfgKey = ObjCRuntime.CreateNSString("kCBAdvDataManufacturerData");
                IntPtr mfgDataNs = ObjCRuntime.objc_msgSend(advData, ObjCRuntime.sel_registerName("objectForKey:"), mfgKey);
                if (mfgDataNs != IntPtr.Zero)
                {
                    byte[] mfgBytes = ObjCRuntime.NSDataToBytes(mfgDataNs);
                    if (mfgBytes.Length > 0)
                    {
                        string mfgStr = System.Text.Encoding.ASCII.GetString(mfgBytes);
                        if (mfgStr.Contains("Square", StringComparison.OrdinalIgnoreCase))
                        {
                            name = "Square Golf";
                        }
                    }
                }
            }

            name ??= "Unknown";
            int rssiVal = (int)(long)ObjCRuntime.objc_msgSend(rssi, ObjCRuntime.sel_registerName("intValue"));

            if (!client._discoveredPeripherals.ContainsKey(deviceId))
            {
                ObjCRuntime.Retain(peripheral);
                client._discoveredPeripherals[deviceId] = peripheral;
            }

            if (!matchesServiceUuid && !IsDeviceNameMatch(name, client._scanOptions?.DeviceNamePrefix))
            {
                if (client._loggedUnknownDevices.TryAdd(deviceId, true))
                {
                    Log($"[AppleBLE Discovery] Ignored non-matching peripheral: Name='{name}', DeviceId={deviceId}, RSSI={rssiVal}");
                }
                return;
            }

            // Only emit discovered event once per device or if name became more specific
            if (client._reportedDeviceNames.TryGetValue(deviceId, out var prevName) && prevName == name)
            {
                return;
            }
            client._reportedDeviceNames[deviceId] = name;

            Log($"Device discovered: {name} ({deviceId}) RSSI={rssiVal}");
            client.DeviceDiscovered?.Invoke(new BluetoothDevice(deviceId, name, rssiVal));
        }
        catch (Exception ex)
        {
            LogErr($"Central_DidDiscoverPeripheral unhandled exception: {ex}");
        }
    }

    private static bool IsDeviceNameMatch(string name, string? prefix) =>
        BluetoothDeviceFilter.IsDeviceNameMatch(name, prefix);

    private static void Central_DidConnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            Log("Central connected to peripheral. Discovering services...");

            // Set peripheral delegate to client's peripheral delegate
            ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("setDelegate:"), client._peripheralDelegate);

            // [peripheral discoverServices:nil]
            ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("discoverServices:"), IntPtr.Zero);
        }
        catch (Exception ex)
        {
            LogErr($"Central_DidConnectPeripheral unhandled exception: {ex}");
        }
    }

    private static void Central_DidFailToConnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            string errorDesc = error != IntPtr.Zero ? ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Unknown error" : "Connection failed";
            LogErr($"Failed to connect to peripheral: {errorDesc}");
            client._connectTcs?.TrySetException(new InvalidOperationException(errorDesc));
        }
        catch (Exception ex)
        {
            LogErr($"Central_DidFailToConnectPeripheral unhandled exception: {ex}");
        }
    }

    private static void Central_DidDisconnectPeripheral(IntPtr self, IntPtr _cmd, IntPtr central, IntPtr peripheral, IntPtr error)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            Log("Peripheral disconnected.");
            client._disconnectTcs?.TrySetResult(true);
            if (client._connectTcs != null && !client._connectTcs.Task.IsCompleted)
            {
                client._connectTcs.TrySetException(new InvalidOperationException("Peripheral disconnected during connection attempt."));
            }
            client.Disconnected?.Invoke();
        }
        catch (Exception ex)
        {
            LogErr($"Central_DidDisconnectPeripheral unhandled exception: {ex}");
        }
    }

    private static void Peripheral_DidDiscoverServices(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr error)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            if (error != IntPtr.Zero)
            {
                string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Service discovery failed";
                LogErr($"Error discovering services: {errorDesc}");
                client._connectTcs?.TrySetException(new InvalidOperationException(errorDesc));
                return;
            }

            IntPtr servicesArray = ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("services"));
            int count = (int)(long)ObjCRuntime.objc_msgSend(servicesArray, ObjCRuntime.sel_registerName("count"));
            Log($"Discovered {count} services. Discovering characteristics for each...");

            for (int i = 0; i < count; i++)
            {
                IntPtr service = ObjCRuntime.objc_msgSend(servicesArray, ObjCRuntime.sel_registerName("objectAtIndex:"), (IntPtr)i);
                ObjCRuntime.objc_msgSend(peripheral, ObjCRuntime.sel_registerName("discoverCharacteristics:forService:"), IntPtr.Zero, service);
            }
        }
        catch (Exception ex)
        {
            LogErr($"Peripheral_DidDiscoverServices unhandled exception: {ex}");
        }
    }

    private static void Peripheral_DidDiscoverCharacteristics(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr service, IntPtr error)
    {
        try
        {
            if (!_instances.TryGetValue(self, out var client)) return;
            if (error != IntPtr.Zero)
            {
                string errorDesc = ObjCRuntime.NSStringToString(ObjCRuntime.objc_msgSend(error, ObjCRuntime.sel_registerName("localizedDescription"))) ?? "Characteristic discovery failed";
                LogErr($"Error discovering characteristics: {errorDesc}");
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
                        Log($"Characteristic mapped: {guid.Value}");
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
        catch (Exception ex)
        {
            LogErr($"Peripheral_DidDiscoverCharacteristics unhandled exception: {ex}");
        }
    }

    private static void Peripheral_DidUpdateValue(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        try
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
        catch (Exception ex)
        {
            LogErr($"Peripheral_DidUpdateValue unhandled exception: {ex}");
        }
    }

    private static void Peripheral_DidWriteValue(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        try
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
        catch (Exception ex)
        {
            LogErr($"Peripheral_DidWriteValue unhandled exception: {ex}");
        }
    }

    private static void Peripheral_DidUpdateNotificationState(IntPtr self, IntPtr _cmd, IntPtr peripheral, IntPtr characteristic, IntPtr error)
    {
        try
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
        catch (Exception ex)
        {
            LogErr($"Peripheral_DidUpdateNotificationState unhandled exception: {ex}");
        }
    }
}
