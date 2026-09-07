# HeckleLinks Shot Injection Utility (PowerShell Native)
# No dependencies or Python installation required!

$Host.UI.RawUI.WindowTitle = "HeckleLinks Shot Injector"

$presets = @{
    "1" = @{ name = "Driver (Bomb) - Long straight drive"; speed = 165.0; spinAxis = 0.5; totalSpin = 2200.0; hla = 0.8; vla = 11.5; type = "drive" }
    "2" = @{ name = "Wedge (Approach) - Short iron to green"; speed = 85.0; spinAxis = -1.0; totalSpin = 7500.0; hla = -0.5; vla = 28.0; type = "iron" }
    "3" = @{ name = "Slice - Massive curve right"; speed = 145.0; spinAxis = 18.0; totalSpin = 3500.0; hla = 3.0; vla = 14.0; type = "drive" }
    "4" = @{ name = "Hook - Massive curve left"; speed = 145.0; spinAxis = -18.0; totalSpin = 3500.0; hla = -3.0; vla = 14.0; type = "drive" }
    "5" = @{ name = "Wormburner - Low rolling shot"; speed = 110.0; spinAxis = 0.0; totalSpin = 1800.0; hla = 0.0; vla = 2.5; type = "iron" }
    "6" = @{ name = "Duff - Mis-hit going nowhere"; speed = 25.0; spinAxis = 5.0; totalSpin = 800.0; hla = 4.0; vla = 10.0; type = "iron" }
    "7" = @{ name = "Putt (Short) - Direct roll on green"; speed = 6.5; spinAxis = 0.0; totalSpin = 100.0; hla = 0.1; vla = 0.0; type = "putt" }
    "8" = @{ name = "Putt (Long) - Fast roll on green"; speed = 15.0; spinAxis = 0.0; totalSpin = 120.0; hla = -0.2; vla = 0.0; type = "putt" }
}

function Show-Menu {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "      HeckleLinks Shot Injection Utility" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Select a shot type preset to inject:"
    foreach ($key in ($presets.Keys | Sort-Object)) {
        Write-Host "  [$key] $($presets[$key].name)"
    }
    Write-Host "  [9] Custom Shot (Enter custom parameters)"
    Write-Host "  [Q] Exit"
    Write-Host "--------------------------------------------------"
}

while ($true) {
    Clear-Host
    Show-Menu
    $choice = (Read-Host "Enter choice").Trim().ToLower()

    if ($choice -eq 'q') {
        break
    }

    $ballData = $null

    if ($presets.ContainsKey($choice)) {
        $preset = $presets[$choice]
        $ballData = @{
            "Speed" = $preset.speed
            "SpinAxis" = $preset.spinAxis
            "TotalSpin" = $preset.totalSpin
            "HLA" = $preset.hla
            "VLA" = $preset.vla
            "ShotType" = $preset.type
        }
    }
    elseif ($choice -eq '9') {
        Write-Host "`nEnter custom shot parameters (press Enter for defaults):"
        $speed = [float](Read-Host "  Speed (mph) [150]" -ErrorAction SilentlyContinue)
        if ($null -eq $speed) { $speed = 150.0 }
        
        $spinAxis = [float](Read-Host "  Spin Axis (deg) [0]" -ErrorAction SilentlyContinue)
        if ($null -eq $spinAxis) { $spinAxis = 0.0 }
        
        $totalSpin = [float](Read-Host "  Total Spin (rpm) [2500]" -ErrorAction SilentlyContinue)
        if ($null -eq $totalSpin) { $totalSpin = 2500.0 }
        
        $hla = [float](Read-Host "  Horizontal Launch Angle (deg) [0]" -ErrorAction SilentlyContinue)
        if ($null -eq $hla) { $hla = 0.0 }
        
        $vla = [float](Read-Host "  Vertical Launch Angle (deg) [12]" -ErrorAction SilentlyContinue)
        if ($null -eq $vla) { $vla = 12.0 }
        
        $type = (Read-Host "  Shot Type (drive/iron/putt) [iron]").Trim()
        if ($type -eq "") { $type = "iron" }

        $ballData = @{
            "Speed" = $speed
            "SpinAxis" = $spinAxis
            "TotalSpin" = $totalSpin
            "HLA" = $hla
            "VLA" = $vla
            "ShotType" = $type
        }
    }
    else {
        Write-Host "Invalid choice!" -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    # Construct TCP payload wrapper
    $payload = @{
        "ShotDataOptions" = @{
            "ContainsBallData" = $true
        }
        "BallData" = $ballData
    }

    # Convert to JSON string
    $payloadStr = ConvertTo-Json $payload -Depth 4 -Compress

    Write-Host "`nConnecting to HeckleLinks on 127.0.0.1:49152..." -ForegroundColor Yellow
    
    try {
        $socket = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 49152)
        $socket.ReceiveTimeout = 3000 # 3 seconds timeout
        $stream = $socket.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        
        Write-Host "Connected! Sending payload:" -ForegroundColor Green
        Write-Host (ConvertTo-Json $payload -Depth 4) -ForegroundColor Gray

        $writer.Write($payloadStr)
        $writer.Flush()

        # Read response as raw bytes to avoid blocking on newline
        $buffer = New-Object byte[] 1024
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        
        if ($bytesRead -gt 0) {
            $responseStr = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
            $resp = ConvertFrom-Json $responseStr
            if ($resp.Code -eq 200) {
                Write-Host "`n[SUCCESS] Shot injected successfully!" -ForegroundColor Green
            } else {
                Write-Host "`n[ERROR] Server returned error: $($resp.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "`n[WARNING] Connected and sent payload, but server closed connection without response." -ForegroundColor Yellow
        }

        $writer.Close()
        $stream.Close()
        $socket.Close()
    }
    catch {
        Write-Host "`n[ERROR] Failed to inject shot: $_" -ForegroundColor Red
        Write-Host "Make sure the game is running, a course/range is loaded, and the TCP Server is listening." -ForegroundColor Yellow
    }

    Write-Host "`nPress Enter to continue..."
    [void][System.Console]::ReadLine()
}
