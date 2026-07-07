$targetBase = "c:\Users\micha\Repositories\HeckleGolfSim\Courses\Environments"
$tempDir = Join-Path $targetBase "temp_downloads"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$assets = @(
    @{ Id = "Grass001"; Folder = "grass-green" },
    @{ Id = "Grass002"; Folder = "grass-fairway" },
    @{ Id = "Grass004"; Folder = "grass-rough" },
    @{ Id = "Ground054"; Folder = "sand-bunker" },
    @{ Id = "Bark001"; Folder = "tree-bark" },
    @{ Id = "Foliage001"; Folder = "tree-foliage" }
)

foreach ($asset in $assets) {
    $id = $asset.Id
    $folderName = $asset.Folder
    $zipName = "$($id)_1K-PNG.zip"
    $url = "https://ambientcg.com/get?file=$zipName"
    $zipPath = Join-Path $tempDir $zipName
    $destFolder = Join-Path $targetBase $folderName
    
    Write-Host "=============================="
    Write-Host "Downloading $id to $folderName..."
    Write-Host "URL: $url"
    
    try {
        # Download the zip
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UserAgent "Mozilla/5.0"
        Write-Host "Download complete. Extracting..."
        
        # Extract files to a temporary extract folder
        $extractDir = Join-Path $tempDir "extract_$id"
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        
        # Ensure destination folder exists
        New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
        
        # We need Color, NormalGL, Roughness, AmbientOcclusion, and Displacement
        $filesToCopy = @(
            @{ SrcSuffix = "_Color.png"; DestName = "albedo.png" },
            @{ SrcSuffix = "_NormalGL.png"; DestName = "normal.png" },
            @{ SrcSuffix = "_Roughness.png"; DestName = "roughness.png" },
            @{ SrcSuffix = "_AmbientOcclusion.png"; DestName = "ao.png" },
            @{ SrcSuffix = "_Displacement.png"; DestName = "height.png" }
        )
        
        foreach ($fileInfo in $filesToCopy) {
            # Find the file in extractDir
            $suffix = $fileInfo.SrcSuffix
            $destName = $fileInfo.DestName
            $srcFile = Get-ChildItem -Path $extractDir -Filter "*$suffix" | Select-Object -First 1
            
            if ($srcFile) {
                $destPath = Join-Path $destFolder $destName
                Copy-Item -Path $srcFile.FullName -Destination $destPath -Force
                Write-Host " - Copied $($srcFile.Name) to $destName"
            } else {
                Write-Warning " - Could not find file ending in $suffix"
            }
        }
        
        Write-Host "Successfully installed $id into $folderName!"
    } catch {
        Write-Error ("Failed to install " + $id + ": " + $_)
    }
}

# Cleanup
Write-Host "Cleaning up temporary files..."
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
Write-Host "Texture download and installation process complete!"
