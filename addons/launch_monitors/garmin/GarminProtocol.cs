using System;
using System.Collections.Generic;
using System.Linq;

namespace LaunchMonitors.Garmin;

internal static class GarminCrc16
{
    private const ushort Polynomial = 0xA001;
    private static readonly ushort[] Table = new ushort[256];

    static GarminCrc16()
    {
        for (ushort i = 0; i < Table.Length; ++i)
        {
            ushort value = 0;
            ushort temp = i;
            for (byte j = 0; j < 8; ++j)
            {
                if (((value ^ temp) & 0x0001) != 0)
                {
                    value = (ushort)((value >> 1) ^ Polynomial);
                }
                else
                {
                    value >>= 1;
                }
                temp >>= 1;
            }
            Table[i] = value;
        }
    }

    public static byte[] ComputeChecksum(IEnumerable<byte> bytes)
    {
        ushort crc = 0;
        foreach (byte b in bytes)
        {
            crc = (ushort)((crc >> 8) ^ Table[(byte)(crc ^ b)]);
        }
        return BitConverter.GetBytes(crc);
    }
}

internal static class GarminCobs
{
    public static IEnumerable<byte> Encode(IEnumerable<byte> input)
    {
        var result = new List<byte>();
        int distanceIndex = 0;
        byte distance = 1;

        foreach (byte b in input)
        {
            if (b != 0 && distance < 255)
            {
                result.Add(b);
                distance++;
            }
            else
            {
                result.Insert(distanceIndex, distance);
                distanceIndex = result.Count;
                distance = 1;
            }
        }

        if (result.Count != 255 && result.Count > 0)
        {
            result.Insert(distanceIndex, distance);
        }

        return result;
    }

    public static IEnumerable<byte> Decode(IEnumerable<byte> input)
    {
        byte[] inputArray = input.ToArray();
        var result = new List<byte>();
        int distanceIndex = 0;

        while (distanceIndex < inputArray.Length)
        {
            byte distance = inputArray[distanceIndex];

            if (inputArray.Length < distanceIndex + distance || distance < 1)
            {
                return [];
            }

            if (distance > 1)
            {
                for (byte i = 1; i < distance; i++)
                {
                    result.Add(inputArray[distanceIndex + i]);
                }
            }

            distanceIndex += distance;

            if (distance < 0xFF && distanceIndex < inputArray.Length)
            {
                result.Add(0);
            }
        }

        return result;
    }
}

internal static class GarminByteExtensions
{
    public static byte[] HexStringToBytes(string hexString)
    {
        var cleaned = hexString.Replace("-", string.Empty).Trim();
        byte[] bytes = new byte[cleaned.Length / 2];
        for (int i = 0; i < cleaned.Length; i += 2)
        {
            bytes[i / 2] = Convert.ToByte(cleaned.Substring(i, 2), 16);
        }
        return bytes;
    }

    public static string ToHexString(this byte[] bytes) => BitConverter.ToString(bytes).Replace("-", string.Empty);

    public static string ToHexString(this IEnumerable<byte> bytes) => ToHexString(bytes.ToArray());

    public static byte[] Checksum(this IEnumerable<byte> bytes) => GarminCrc16.ComputeChecksum(bytes);
}
