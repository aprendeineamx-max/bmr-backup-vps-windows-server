# BMR Backup FUNCIONAL - Copia directa + Compresion + S3
# Ejecutar desde Civer-One, respalda Civer-Two

param(
    [string]$TargetIP = "216.238.88.126",
    [string]$Username = "Administrator", 
    [string]$Password = "6K#fVnH-arJG-(wT"
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BMR BACKUP FUNCIONAL - CIVER-TWO" -ForegroundColor Green  
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Conectando a $TargetIP..." -ForegroundColor Cyan
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)
$session = New-PSSession -ComputerName $TargetIP -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "[OK] Sesion establecida`n" -ForegroundColor Green

# Script remoto optimizado
$remoteScript = {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "CIVER-TWO-BMR-$timestamp"
    $backupDir = "C:\BackupTemp\$backupName"
    $logFile = "C:\BackupTemp\$backupName-log.txt"
    
    function Log { param($msg) "$([DateTime]::Now.ToString('HH:mm:ss')) $msg" | Tee-Object -FilePath $logFile -Append | Write-Host }
    
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    
    Log "===== BACKUP BMR INICIADO ====="
    Log "Servidor: $env:COMPUTERNAME"
    
    # Carpetas a respaldar (directo, sin VSS)
    $foldersToBackup = @(
        @{Source="C:\Users"; Dest="Users"; Skip="*/AppData/Local/Temp,*/Downloads,*/Cache"},
        @{Source="C:\ProgramData"; Dest="ProgramData"; Skip="*/Temp,*/Cache"},
        @{Source="C:\Program Files\Common Files"; Dest="ProgramFilesCommon"; Skip=""},
        @{Source="C:\Windows\System32\config"; Dest="WindowsConfig"; Skip=""}
    )
    
    Log "`n[PASO 1/3] Copiando archivos criticos..."
    $totalCopied = 0
    
    foreach($folder in $foldersToBackup){
        $source = $folder.Source
        $dest = Join-Path $backupDir $folder.Dest
        
        if(Test-Path $source){
            Log "  Copiando: $source"
            
            if($folder.Skip){
                $excludes = $folder.Skip -split ','
                $xdArgs = $excludes | ForEach-Object { "/XD `"$_`"" }
                $robocopyCmd = "robocopy `"$source`" `"$dest`" /E /R:1 /W:1 /MT:2 /XJ $xdArgs /NFL /NDL /NJH /NJS"
            } else {
                $robocopyCmd = "robocopy `"$source`" `"$dest`" /E /R:1 /W:1 /MT:2 /XJ /NFL /NDL /NJH /NJS"
            }
            
            Invoke-Expression $robocopyCmd | Out-Null
            
            if(Test-Path $dest){
                $size = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sizeMB = [math]::Round($size/1MB, 2)
                Log "    OK: $sizeMB MB"
                $totalCopied += $sizeMB
            } else {
                Log "    ERROR: No se pudo copiar"
            }
        } else {
            Log "  SKIP: $source no existe"
        }
    }
    
    Log "`nTotal copiado: $totalCopied MB ($([math]::Round($totalCopied/1024,2)) GB)"
    
    # Comprimir
    Log "`n[PASO 2/3] Comprimiendo backup..."
    $7zip = "C:\Program Files\7-Zip\7z.exe"
    
    if(!(Test-Path $7zip)){
        Log "  Instalando 7-Zip..."
        try {
            $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
            $installer = "$env:TEMP\7zip.msi"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing -TimeoutSec 120
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
            Log "  7-Zip instalado"
        } catch {
            Log "  ERROR: No se pudo instalar 7-Zip: $_"
            return @{Success=$false; Error="7-Zip install failed"}
        }
    }
    
    $zipFile = "C:\BackupTemp\$backupName.7z"
    Log "  Comprimiendo: $zipFile"
    Log "  (Compresion media, dividido en partes de 1GB)"
    
    $sourcePattern = $backupDir + "\*"
    & $7zip a -t7z -mx=3 -mmt=on -v1000m $zipFile $sourcePattern 2>&1 | Out-Null
    
    if($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1){
        Log "  ERROR: Compresion fallo (codigo: $LASTEXITCODE)"
        return @{Success=$false; Error="Compression failed"}
    }
    
    $pattern = "$backupName.7z.*"
    $parts = Get-ChildItem "C:\BackupTemp" -Filter $pattern -ErrorAction SilentlyContinue
    
    if(!$parts){
        Log "  ERROR: No se crearon archivos comprimidos"
        return @{Success=$false; Error="No compressed files"}
    }
    
    $totalSize = ($parts | Measure-Object Length -Sum).Sum
    $totalGB = [math]::Round($totalSize/1GB, 2)
    Log "  OK: $($parts.Count) partes, $totalGB GB total"
    
    # Subir a S3
    Log "`n[PASO 3/3] Subiendo a Object Storage..."
    $awsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    
    if(!(Test-Path $awsPath)){
        Log "  Instalando AWS CLI..."
        try {
            $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
            $awsInstaller = "$env:TEMP\AWSCLIV2.msi"
            Invoke-WebRequest -Uri $awsUrl -OutFile $awsInstaller -UseBasicParsing -TimeoutSec 120
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$awsInstaller`" /quiet /norestart"
            $env:Path = "C:\Program Files\Amazon\AWSCLIV2;" + $env:Path
            Log "  AWS CLI instalado"
        } catch {
            Log "  ERROR: No se pudo instalar AWS CLI: $_"
            return @{Success=$false; Error="AWS CLI install failed"}
        }
    }
    
    # Configurar AWS
    $awsDir = "$env:USERPROFILE\.aws"
    if(!(Test-Path $awsDir)){ New-Item -Path $awsDir -ItemType Directory -Force | Out-Null }
    
    "[default]`nregion = us-west-1`noutput = json" | Set-Content "$awsDir\config" -Force
    "[default]`naws_access_key_id = G0LDHU6PIXWDEDJTAQ4B`naws_secret_access_key = a9Vg7EMOomETgQ5V6bJlXPzMR6DhCEonUXBqcpRo" | Set-Content "$awsDir\credentials" -Force
    
    $uploadOK = 0
    $uploadFail = 0
    
    foreach($part in $parts){
        $partSize = [math]::Round($part.Length/1MB, 2)
        Log "  Subiendo: $($part.Name) ($partSize MB)"
        
        $s3Path = "s3://backups-bmr-civer/backups/$($part.Name)"
        
        try {
            & $awsPath s3 cp $part.FullName $s3Path --endpoint-url https://lax1.vultrobjects.com 2>&1 | Out-Null
            
            if($LASTEXITCODE -eq 0){
                Log "    OK"
                $uploadOK++
            } else {
                Log "    ERROR (codigo: $LASTEXITCODE)"
                $uploadFail++
            }
        } catch {
            Log "    ERROR: $_"
            $uploadFail++
        }
    }
    
    Log "`n===== BACKUP COMPLETADO ====="
    Log "Partes creadas: $($parts.Count)"
    Log "Subidas OK: $uploadOK"
    Log "Subidas FAIL: $uploadFail"
    Log "Tamano total: $totalGB GB"
    Log "Backup local: C:\BackupTemp\"
    Log "Backup S3: s3://backups-bmr-civer/backups/"
    Log "Log: $logFile"
    
    return @{
        Success = $true
        BackupName = $backupName
        PartsCreated = $parts.Count
        PartsUploaded = $uploadOK
        PartsFailed = $uploadFail
        TotalSizeGB = $totalGB
        TotalCopiedMB = $totalCopied
        LogFile = $logFile
    }
}

Write-Host "Ejecutando backup (tiempo estimado: 30-90 min)...`n" -ForegroundColor Yellow

try {
    $result = Invoke-Command -Session $session -ScriptBlock $remoteScript
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "RESULTADO FINAL" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    if($result.Success){
        Write-Host "[OK] Backup completado!" -ForegroundColor Green
        Write-Host "`nEstadisticas:" -ForegroundColor Cyan
        Write-Host "  Datos copiados: $($result.TotalCopiedMB) MB" -ForegroundColor White
        Write-Host "  Comprimido a: $($result.TotalSizeGB) GB" -ForegroundColor White
        Write-Host "  Partes: $($result.PartsCreated)" -ForegroundColor White
        Write-Host "  Subidas OK: $($result.PartsUploaded)" -ForegroundColor White
        Write-Host "  Subidas FAIL: $($result.PartsFailed)" -ForegroundColor Yellow
        Write-Host "`nUbicaciones:" -ForegroundColor Cyan
        Write-Host "  Local: C:\BackupTemp\$($result.BackupName)*" -ForegroundColor White
        Write-Host "  S3: s3://backups-bmr-civer/backups/" -ForegroundColor White
        Write-Host "  Log: $($result.LogFile)" -ForegroundColor White
        
        if($result.PartsFailed -gt 0){
            Write-Host "`n[!] ADVERTENCIA: $($result.PartsFailed) partes fallaron al subir" -ForegroundColor Yellow
            Write-Host "Puedes reintentarlas manualmente con:" -ForegroundColor Gray
            Write-Host "  aws s3 cp archivo.7z.XXX s3://backups-bmr-civer/backups/ --endpoint-url https://lax1.vultrobjects.com" -ForegroundColor Gray
        }
    } else {
        Write-Host "[ERROR] Backup fallo" -ForegroundColor Red
        Write-Host "  Error: $($result.Error)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "[ERROR] Excepcion: $_" -ForegroundColor Red
} finally {
    Remove-PSSession $session
    Write-Host "`nSesion cerrada." -ForegroundColor Gray
}
