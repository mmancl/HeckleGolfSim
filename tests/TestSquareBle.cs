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
        TestCommandBuilder();

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

        // 9-byte packet (club delivery): MUST NOT be treated as status packet!
        byte[] clubPacket9 = [0x11, 0x03, 0x01, 0x02, 0xFE, 0x01, 0x0A, 0x00, 0x01];
        if (SquareProtocol.IsStatusPacket(clubPacket9))
            throw new Exception("9-byte club delivery packet was falsely recognized as status packet!");

        GD.Print("PASS: Status packets parsed correctly without misidentifying 9-byte club packets.");
    }

    private static void TestClubDataPacketParsing()
    {
        GD.Print("\n--- Test 2: Club Data Packet Parsing ---");
        // Test 9-byte 0x11 0x03 format:
        // [0] 0x11, [1] 0x03, [2] seq 0x01, [3] face: 2 (+2.0 open), [4] path: -2 (0xFE = -2 in-to-out/out-to-in), [5] attack: -3 (0xFD), [6] loft: 12
        byte[] club9 = [0x11, 0x03, 0x01, 0x02, 0xFE, 0xFD, 12, 0x00, 0x01];
        if (!SquareProtocol.IsClubDataPacket(club9))
            throw new Exception("9-byte club data packet not recognized!");
        if (!SquareProtocol.TryParseClubData(club9, out var metrics9))
            throw new Exception("Failed to parse 9-byte club data!");
        if (MathF.Abs(metrics9.FaceAngle - 2.0f) > 0.001f)
            throw new Exception($"FaceAngle mismatch: expected 2.0, got {metrics9.FaceAngle}");
        if (MathF.Abs(metrics9.ClubPath - (-2.0f)) > 0.001f)
            throw new Exception($"ClubPath mismatch: expected -2.0, got {metrics9.ClubPath}");
        if (MathF.Abs(metrics9.AttackAngle - (-3.0f)) > 0.001f)
            throw new Exception($"AttackAngle mismatch: expected -3.0, got {metrics9.AttackAngle}");
        if (MathF.Abs(metrics9.DynamicLoft - 12.0f) > 0.001f)
            throw new Exception($"DynamicLoft mismatch: expected 12.0, got {metrics9.DynamicLoft}");

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

        GD.Print("PASS: Both 9-byte (0x03) and 11-byte (0x07) club delivery packets parsed accurately.");
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
}
