using System;
using Godot;
using Godot.Collections;

namespace HeckleLinks.Announcer;

public static class AndroidTTS
{
    private static readonly string LogPrefix = "[AndroidTTS]";

    public static Array<Dictionary> GetVoices()
    {
        try
        {
            return DisplayServer.TtsGetVoices();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} Failed to get TTS voices: {ex.Message}");
            return new Array<Dictionary>();
        }
    }

    public static void Speak(string text, string voiceId, float pitch = 1.0f, float rate = 1.0f)
    {
        if (string.IsNullOrEmpty(text)) return;
        
        GD.Print($"{LogPrefix} Speaking: '{text}' (voice: '{voiceId}', pitch: {pitch}, rate: {rate})");
        
        try
        {
            DisplayServer.TtsStop();
            DisplayServer.TtsSpeak(text, voiceId, volume: 100, pitch: pitch, rate: rate);
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} TTS Speak failed: {ex.Message}");
        }
    }

    public static void Stop()
    {
        try
        {
            DisplayServer.TtsStop();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"{LogPrefix} TTS Stop failed: {ex.Message}");
        }
    }
}
