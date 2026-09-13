using System;
using System.Runtime.InteropServices;

namespace LaunchMonitors.Common.Bluetooth.Apple;

internal static class ObjCRuntime
{
    private const string LibObjC = "/usr/lib/libobjc.A.dylib";
    private const string LibSystem = "/usr/lib/libSystem.B.dylib";

    private static bool _frameworksLoaded;
    private static readonly object _lock = new();

    [DllImport(LibSystem, EntryPoint = "dlopen")]
    public static extern IntPtr dlopen(string path, int mode);

    [DllImport(LibObjC, EntryPoint = "objc_getClass")]
    public static extern IntPtr objc_getClass(string name);

    [DllImport(LibObjC, EntryPoint = "sel_registerName")]
    public static extern IntPtr sel_registerName(string name);

    [DllImport(LibObjC, EntryPoint = "objc_allocateClassPair")]
    public static extern IntPtr objc_allocateClassPair(IntPtr superclass, string name, IntPtr extraBytes);

    [DllImport(LibObjC, EntryPoint = "class_addMethod")]
    public static extern bool class_addMethod(IntPtr cls, IntPtr name, IntPtr imp, string types);

    [DllImport(LibObjC, EntryPoint = "objc_registerClassPair")]
    public static extern void objc_registerClassPair(IntPtr cls);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2, IntPtr arg3);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2, IntPtr arg3, IntPtr arg4);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, bool arg1, IntPtr arg2);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1, IntPtr arg2, int arg3);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg1, int arg2);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend_str(IntPtr receiver, IntPtr selector, [MarshalAs(UnmanagedType.LPUTF8Str)] string arg1);

    [DllImport(LibObjC, EntryPoint = "objc_msgSend")]
    public static extern IntPtr objc_msgSend_bytes(IntPtr receiver, IntPtr selector, byte[] arg1, int arg2);

    [DllImport(LibObjC, EntryPoint = "objc_autoreleasePoolPush")]
    public static extern IntPtr objc_autoreleasePoolPush();

    [DllImport(LibObjC, EntryPoint = "objc_autoreleasePoolPop")]
    public static extern void objc_autoreleasePoolPop(IntPtr pool);

    public static void EnsureFrameworksLoaded()
    {
        if (_frameworksLoaded) return;
        lock (_lock)
        {
            if (_frameworksLoaded) return;

            const int RTLD_NOW = 2;
            const int RTLD_GLOBAL = 8;
            int flags = RTLD_NOW | RTLD_GLOBAL;

            // Load Foundation & CoreBluetooth
            _ = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", flags);
            _ = dlopen("/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth", flags);

            _frameworksLoaded = true;
        }
    }

    public static IntPtr CreateNSString(string str)
    {
        if (str == null) return IntPtr.Zero;
        IntPtr nsStringClass = objc_getClass("NSString");
        return objc_msgSend_str(nsStringClass, sel_registerName("stringWithUTF8String:"), str);
    }

    public static string? NSStringToString(IntPtr nsString)
    {
        if (nsString == IntPtr.Zero) return null;
        IntPtr utf8Ptr = objc_msgSend(nsString, sel_registerName("UTF8String"));
        if (utf8Ptr == IntPtr.Zero) return null;
        return Marshal.PtrToStringUTF8(utf8Ptr);
    }

    public static IntPtr CreateNSData(byte[] bytes)
    {
        if (bytes == null || bytes.Length == 0)
        {
            IntPtr nsDataClass = objc_getClass("NSData");
            return objc_msgSend(nsDataClass, sel_registerName("data"));
        }

        IntPtr nsDataCls = objc_getClass("NSData");
        return objc_msgSend_bytes(nsDataCls, sel_registerName("dataWithBytes:length:"), bytes, bytes.Length);
    }

    public static byte[] NSDataToBytes(IntPtr nsData)
    {
        if (nsData == IntPtr.Zero) return Array.Empty<byte>();
        int length = (int)(long)objc_msgSend(nsData, sel_registerName("length"));
        if (length <= 0) return Array.Empty<byte>();

        IntPtr bytesPtr = objc_msgSend(nsData, sel_registerName("bytes"));
        if (bytesPtr == IntPtr.Zero) return Array.Empty<byte>();

        byte[] result = new byte[length];
        Marshal.Copy(bytesPtr, result, 0, length);
        return result;
    }

    public static IntPtr CreateCBUUID(Guid guid)
    {
        IntPtr cbUuidClass = objc_getClass("CBUUID");
        IntPtr uuidStr = CreateNSString(guid.ToString());
        return objc_msgSend(cbUuidClass, sel_registerName("UUIDWithString:"), uuidStr);
    }

    public static Guid? CBUUIDToGuid(IntPtr cbUuid)
    {
        if (cbUuid == IntPtr.Zero) return null;
        IntPtr uuidStrNs = objc_msgSend(cbUuid, sel_registerName("UUIDString"));
        string? uuidStr = NSStringToString(uuidStrNs);
        if (uuidStr != null && Guid.TryParse(uuidStr, out var guid))
        {
            return guid;
        }
        return null;
    }

    public static void Retain(IntPtr obj)
    {
        if (obj != IntPtr.Zero)
        {
            objc_msgSend(obj, sel_registerName("retain"));
        }
    }

    public static void Release(IntPtr obj)
    {
        if (obj != IntPtr.Zero)
        {
            objc_msgSend(obj, sel_registerName("release"));
        }
    }
}
