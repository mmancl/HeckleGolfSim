using System;
using Godot;
using LaunchMonitors.Square;

public partial class TestSquareBle : Node
{
    public override void _Ready()
    {
        GD.Print("==================================================");
        GD.Print("Running Square BLE & Protocol Verification Tests");
        GD.Print("==================================================");

        TestStatusPacketParsing();
        TestClubDataPacketParsing();
        TestShotPacketParsing();
        TestBatteryPacketParsing();
        TestCommandBuilder();
        TestDeviceNameMatching();

        GD.Print("==================================================");
        GD.Print("ALL SQUARE BLE & PROTOCOL TESTS PASSED SUCCESSFULLY!");
        GD.Print("==================================================");
    }

    private static void TestStatusPacketParsing()
    {
        GD.Print("\n--- Test 1: Status Packet Parsing ---");
        // 3-byte status packet: [0x11, 0x03, 0x04 (Ready)]
        byte[] status3 = [0x11, 0x03, 0x04];
        if (!SquareProtocol.IsStatusPacket(status3))
            throw new Exception("3-byte status packet was not recognized!");
        if (!SquareProtocol.TryParseStatus(status3, out var code3) || code3 != SquareProtocol.StatusReady)
            throw new Exception($"Expected StatusReady (0x04), got 0x{code3:X2}");

        // 4-byte status packet: [0x11, 0x03, 0x01 (seq), 0x05 (Shot)]
        byte[] status4 = [0x11, 0x03, 0x01, 0x05];
        if (!SquareProtocol.IsStatusPacket(status4))
            throw new Exception("4-byte status packet was not recognized!");
        if (!SquareProtocol.TryParseStatus(status4, out var code4) || code4 != SquareProtocol.StatusShot)
            throw new Exception($"Expected StatusShot (0x05), got 0x{code4:X2}");

        // 9-byte heartbeat ack / status packet: [0x11, 0x03, 0x01 (seq), 0x04 (Ready), 0x00, ...]
        // MUST be recognized as status packet, NOT as club data!
        byte[] status9 = [0x11, 0x03, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00];
        if (!SquareProtocol.IsStatusPacket(status9))
            throw new Exception("9-byte status/heartbeat ack packet was not recognized!");
        if (!SquareProtocol.TryParseStatus(status9, out var code9) || code9 != SquareProtocol.StatusReady)
            throw new Exception($"Expected StatusReady (0x04) in 9-byte packet, got 0x{code9:X2}");
        if (SquareProtocol.IsClubDataPacket(status9))
            throw new Exception("9-byte status packet was falsely recognized as club data packet!");

        GD.Print("PASS: Status packets (including 9-byte heartbeat acks) parsed correctly.");
    }

    private static void TestClubDataPacketParsing()
    {
        GD.Print("\n--- Test 2: Club Data Packet Parsing ---");
        // Test 11-byte 0x11 0x07 format:
        // Path = +1.50 (150 = 0x0096), Face = -0.75 (-75 = 0xFFB5), Attack = -2.10 (-210 = 0xFF2E), Loft = 10.50 (1050 = 0x041A)
        byte[] club11 = [
            0x11, 0x07, 0x0F,
            0x96, 0x00, // Path: 150 -> 1.50
            0xB5, 0xFF, // Face: -75 -> -0.75
            0x2E, 0xFF, // Attack: -210 -> -2.10
            0x1A, 0x04  // Loft: 1050 -> 10.50
        ];
        if (!SquareProtocol.IsClubDataPacket(club11))
            throw new Exception("11-byte 0x07 club data packet not recognized!");
        if (!SquareProtocol.TryParseClubData(club11, out var metrics11))
            throw new Exception("Failed to parse 11-byte club data!");
        if (MathF.Abs(metrics11.ClubPath - 1.50f) > 0.01f)
            throw new Exception($"ClubPath mismatch in 11-byte packet: {metrics11.ClubPath}");
        if (MathF.Abs(metrics11.FaceAngle - (-0.75f)) > 0.01f)
            throw new Exception($"FaceAngle mismatch in 11-byte packet: {metrics11.FaceAngle}");
        if (MathF.Abs(metrics11.AttackAngle - (-2.10f)) > 0.01f)
            throw new Exception($"AttackAngle mismatch in 11-byte packet: {metrics11.AttackAngle}");
        if (MathF.Abs(metrics11.DynamicLoft - 10.50f) > 0.01f)
            throw new Exception($"DynamicLoft mismatch in 11-byte packet: {metrics11.DynamicLoft}");

        GD.Print("PASS: 11-byte (0x07) club delivery packets parsed accurately.");
    }

    private static void TestBatteryPacketParsing()
    {
        GD.Print("\n--- Test 2b: Battery & Clock Packet Parsing ---");
        // Square Omni battery packet: [0x91, 0x45 (69%), 0x01 (charging)]
        byte[] batPacket = [0x91, 0x45, 0x01];
        if (!SquareProtocol.IsBatteryPacket(batPacket))
            throw new Exception("0x91 battery packet not recognized!");
        if (!SquareProtocol.TryParseBattery(batPacket, out var level, out var chargingState))
            throw new Exception("Failed to parse 0x91 battery packet!");
        if (level != 69)
            throw new Exception($"Expected battery level 69%, got {level}%");
        if (chargingState != 1)
            throw new Exception($"Expected chargingState 1, got {chargingState}");

        // Clock packet: [0x71, ...]
        byte[] clockPacket = [0x71, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        if (!SquareProtocol.IsClockPacket(clockPacket))
            throw new Exception("0x71 clock packet not recognized!");

        GD.Print("PASS: 0x91 battery and 0x71 clock packets recognized and parsed accurately.");
    }

    private static void TestShotPacketParsing()
    {
        GD.Print("\n--- Test 3: Shot Packet Parsing ---");
        // 17-byte ball-only shot: Speed = 45.50 m/s (4550 = 0x11C6), VLA = 12.5 deg (1250 = 0x04E2), HLA = -1.2 deg (-120 = 0xFF88), Spin = 2500 (0x09C4), Axis = -2.5 deg (250 = 0x00FA -> -2.5), Back = 2400 (0x0960), Side = -150 (0xFF6A)
        byte[] shot17 = [
            0x11, 0x02, 0x37,
            0xC6, 0x11, // Speed: 45.50 m/s
            0xE2, 0x04, // VLA: 12.50 deg
            0x88, 0xFF, // HLA: -1.20 deg
            0xC4, 0x09, // TotalSpin: 2500 rpm
            0xFA, 0x00, // SpinAxis: -2.50 deg
            0x60, 0x09, // BackSpin: 2400 rpm
            0x6A, 0xFF  // SideSpin: -150 rpm
        ];
        if (!SquareProtocol.IsShotPacket(shot17))
            throw new Exception("17-byte shot packet not recognized!");
        if (!SquareProtocol.TryParseShot(shot17, out var metrics17))
            throw new Exception("Failed to parse 17-byte shot packet!");
        if (metrics17.HasClubData)
            throw new Exception("17-byte ball-only shot should have HasClubData = false!");
        if (MathF.Abs(metrics17.BallSpeedMps - 45.50f) > 0.01f)
            throw new Exception($"Speed mismatch: {metrics17.BallSpeedMps}");

        // 25-byte shot packet with club delivery data:
        // Appends: ClubPath = 2.0 (200 = 0x00C8), FaceAngle = -1.0 (-100 = 0xFF9C), AttackAngle = -3.5 (-350 = 0xFEA2), DynamicLoft = 14.2 (1420 = 0x058C)
        byte[] shot25 = [
            0x11, 0x02, 0x37,
            0xC6, 0x11,
            0xE2, 0x04,
            0x88, 0xFF,
            0xC4, 0x09,
            0xFA, 0x00,
            0x60, 0x09,
            0x6A, 0xFF,
            0xC8, 0x00, // ClubPath = 2.0
            0x9C, 0xFF, // FaceAngle = -1.0
            0xA2, 0xFE, // AttackAngle = -3.5
            0x8C, 0x05  // DynamicLoft = 14.2
        ];
        if (!SquareProtocol.IsShotPacket(shot25))
            throw new Exception("25-byte shot packet not recognized!");
        if (!SquareProtocol.TryParseShot(shot25, out var metrics25))
            throw new Exception("Failed to parse 25-byte shot packet!");
        if (!metrics25.HasClubData)
            throw new Exception("25-byte shot packet with club delivery must have HasClubData = true!");
        if (MathF.Abs(metrics25.ClubPath - 2.0f) > 0.01f)
            throw new Exception($"ClubPath mismatch: {metrics25.ClubPath}");
        if (MathF.Abs(metrics25.FaceAngle - (-1.0f)) > 0.01f)
            throw new Exception($"FaceAngle mismatch: {metrics25.FaceAngle}");
        if (MathF.Abs(metrics25.AttackAngle - (-3.5f)) > 0.01f)
            throw new Exception($"AttackAngle mismatch: {metrics25.AttackAngle}");
        if (MathF.Abs(metrics25.DynamicLoft - 14.2f) > 0.01f)
            throw new Exception($"DynamicLoft mismatch: {metrics25.DynamicLoft}");

        GD.Print("PASS: Shot packets correctly parsed and HasClubData properly distinguished.");
    }

    private static void TestCommandBuilder()
    {
        GD.Print("\n--- Test 4: SquareCommandBuilder Commands ---");
        var hb = SquareCommandBuilder.Heartbeat(0x05);
        if (Convert.ToHexString(hb) != "1183050000000000")
            throw new Exception($"Heartbeat hex mismatch: {Convert.ToHexString(hb)}");

        var club = SquareCommandBuilder.Club(0x02, "0204", 0);
        if (Convert.ToHexString(club) != "118202020400000000")
            throw new Exception($"Club hex mismatch: {Convert.ToHexString(club)}");

        var detect = SquareCommandBuilder.DetectBall(0x01, mode: 1, spinMode: 1);
        if (Convert.ToHexString(detect) != "118101011100000000")
            throw new Exception($"DetectBall hex mismatch: {Convert.ToHexString(detect)}");

        GD.Print("PASS: Command byte sequences verified.");
    }

    private static void TestDeviceNameMatching()
    {
        GD.Print("\n--- Test 5: Bluetooth Device Name Matching (including SGO models) ---");
        // Square Golf naming tests
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SquareGolf", "SquareGolf"))
            throw new Exception("Exact 'SquareGolf' name failed match!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("Square Golf", "SquareGolf"))
            throw new Exception("'Square Golf' with space failed match!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SquareGolf_1234", "SquareGolf"))
            throw new Exception("'SquareGolf_1234' failed match!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SGO300A", "SquareGolf"))
            throw new Exception("'SGO300A' model failed match for SquareGolf prefix!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SGO-300", "SquareGolf"))
            throw new Exception("'SGO-300' model failed match for SquareGolf prefix!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("sgo_300", "SquareGolf"))
            throw new Exception("'sgo_300' model failed match for SquareGolf prefix!");
        if (LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("Approach R10", "SquareGolf"))
            throw new Exception("'Approach R10' falsely matched SquareGolf prefix!");

        // Garmin Approach naming tests
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("Approach R10", "Approach"))
            throw new Exception("'Approach R10' failed match for Approach prefix!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("Garmin Approach R10", "Approach"))
            throw new Exception("'Garmin Approach R10' failed match for Approach prefix!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("R10 [1234]", "Approach"))
            throw new Exception("'R10 [1234]' failed match for Approach prefix!");
        if (LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SGO300A", "Approach"))
            throw new Exception("'SGO300A' falsely matched Approach prefix!");

        // Edge cases
        if (LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch(null, "SquareGolf"))
            throw new Exception("null name should not match!");
        if (LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("Unknown", "SquareGolf"))
            throw new Exception("'Unknown' name should not match!");
        if (!LaunchMonitors.Common.Bluetooth.BluetoothDeviceFilter.IsDeviceNameMatch("SGO300A", null))
            throw new Exception("null prefix should match any valid device!");

        GD.Print("PASS: Bluetooth device name matching successfully validates Square Golf, SGO models, and Garmin devices.");
    }
}
