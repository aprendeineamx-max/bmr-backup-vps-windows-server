# Backup COMPLETO ejecutando como SYSTEM
# Descarga PsExec y ejecuta robocopy como SYSTEM para acceso total

param(
    [string]$TargetIP = "216.238.88.126",
    [string]$Username = "Administrator",
    [string]$Password = "6K#fVnH-arJG-(wT"
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BACKUP COMPLETO COMO SYSTEM" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Conectando a $TargetIP..." -ForegroundColor Cyan
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)
$session = New-PSSession -ComputerName $TargetIP -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "[OK] Sesion establecida`n" -ForegroundColor Green

$remoteScript = {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "CIVER-TWO-FULL-$timestamp"
    $backupDir = "C:\BackupTemp\$backupName"
    $logFile = "C:\BackupTemp\$backupName-log.txt"
    
    function Log { 
        param($msg, $color = "White")
        $line = "$([DateTime]::Now.ToString('HH:mm:ss')) $msg"
        $line | Out-File -FilePath $logFile -Append -Encoding UTF8
        Write-Host $line -ForegroundColor $color
    }
    
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    New-Item -Path "C:\BackupTemp\tools" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    Log "===== BACKUP COMPLETO COMO SYSTEM =====" "Green"
    Log "Servidor: $env:COMPUTERNAME" "Cyan"
    
    # Descargar PsExec si no existe
    $psexecPath = "C:\BackupTemp\tools\PsExec.exe"
    if(!(Test-Path $psexecPath)){
        Log "`n[DESCARGANDO PSEXEC]..." "Cyan"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $url = "https://live.sysinternals.com/PsExec.exe"
            Invoke-WebRequest -Uri $url -OutFile $psexecPath -UseBasicParsing -TimeoutSec 60
            Log "  [OK] PsExec descargado" "Green"
        } catch {
            Log "  [ERROR] No se pudo descargar PsExec: $_" "Red"
            return @{Success=$false; Error="PsExec download failed"}
        }
    } else {
        Log "PsExec ya disponible" "Green"
    }
    
    # Verificar/Instalar 7-Zip
    $7zip = "C:\Program Files\7-Zip\7z.exe"
    if(!(Test-Path $7zip)){
        Log "`n[INSTALANDO 7-ZIP]..." "Cyan"
        try {
            $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
            $installer = "$env:TEMP\7zip.msi"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing -TimeoutSec 120
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
            Start-Sleep -Seconds 5
            
            if(Test-Path $7zip){
                Log "  [OK] 7-Zip instalado" "Green"
            } else {
                Log "  [ERROR] 7-Zip no se instalo correctamente" "Red"
                return @{Success=$false; Error="7-Zip install failed"}
            }
        } catch {
            Log "  [ERROR] Fallo instalacion 7-Zip: $_" "Red"
            return @{Success=$false; Error="7-Zip install failed"}
        }
    } else {
        Log "7-Zip ya instalado" "Green"
    }
    
    # Carpetas a respaldar
    $foldersToBackup = @(
        @{Source="C:\Users"; Dest="Users"; Exclude="AppData\Local\Temp;Downloads;Cache"},
        @{Source="C:\ProgramData"; Dest="ProgramData"; Exclude=""},
        @{Source="C:\Program Files\Common Files"; Dest="ProgramFilesCommon"; Exclude=""},
        @{Source="C:\Windows\System32\config"; Dest="WindowsConfig"; Exclude=""}
    )
    
    Log "`n[COPIANDO ARCHIVOS COMO SYSTEM]..." "Cyan"
    Log "Esto puede tardar 30-60 minutos segun tamano de datos`n" "Yellow"
    
    $totalCopied = 0
    $successCount = 0
    
    foreach($folder in $foldersToBackup){
        $source = $folder.Source
        $destName = $folder.Dest
        $dest = Join-Path $backupDir $destName
        
        if(!(Test-Path $source)){
            Log "  SKIP: $source (no existe)" "Gray"
            continue
        }
        
        Log "  Copiando: $source" "White"
        
        # Crear directorio destino
        New-Item -Path $dest -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        
        # Construir comando robocopy
        $excludeDirs = ""
        if($folder.Exclude -ne ""){
            $excludeParts = $folder.Exclude -split ";"
            $excludeDirs = "/XD " + ($excludeParts -join " ")
        }
        
        # Comando robocopy optimizado
        $robocopyCmd = "robocopy `"$source`" `"$dest`" /E /COPYALL /R:2 /W:1 /MT:2 /XJ $excludeDirs /NFL /NDL /NP"
        
        # Log del comando
        $cmdLog = Join-Path $backupDir "cmd_$destName.txt"
        "COMANDO: $robocopyCmd" | Out-File $cmdLog -Encoding UTF8
        
        # Ejecutar como SYSTEM usando PsExec
        try {
            $psexecCmd = "& `"$psexecPath`" -accepteula -nobanner -s cmd.exe /c `"$robocopyCmd >> `"$cmdLog`" 2>&1`""
            
            # Invocar PsExec
            $process = Start-Process -FilePath $psexecPath -ArgumentList "-accepteula","-nobanner","-s","cmd.exe","/c","`"$robocopyCmd 2>&1`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $cmdLog -ErrorAction Continue
            
            $exitCode = $process.ExitCode
            
            # Códigos robocopy: 0-7 = éxito, 8+ = error
            if($exitCode -le 7){
                if(Test-Path $dest){
                    $files = Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue
                    $size = ($files | Measure-Object Length -Sum).Sum
                    $sizeMB = [math]::Round($size/1MB, 2)
                    $fileCount = $files.Count
                    Log "    [OK] $fileCount archivos, $sizeMB MB (codigo: $exitCode)" "Green"
                    $totalCopied += $sizeMB
                    $successCount++
                } else {
                    Log "    [!] Directorio vacio" "Yellow"
                }
            } else {
                Log "    [ERROR] Robocopy fallo (codigo: $exitCode)" "Red"
                Log "    Ver: $cmdLog" "Gray"
            }
            
        } catch {
            Log "    [ERROR] Excepcion: $_" "Red"
        }
    }
    
    Log "`nTotal copiado: $totalCopied MB ($([math]::Round($totalCopied/1024,2)) GB)" "Cyan"
    Log "Carpetas exitosas: $successCount de $($foldersToBackup.Count)" "Cyan"
    
    # Si no se copió nada, error
    if($totalCopied -eq 0){
        Log "`n[ERROR] No se copiaron archivos!" "Red"
        return @{Success=$false; Error="No files copied"; TotalCopiedMB=0}
    }
    
    # Comprimir
    Log "`n[COMPRIMIENDO BACKUP]..." "Cyan"
    $zipFile = "C:\BackupTemp\$backupName.7z"
    Log "  Archivo: $zipFile" "White"
    Log "  Dividido en partes de 500MB" "Gray"
    Log "  Nivel de compresion: medio (5)" "Gray"
    Log "  Esto puede tardar 10-30 minutos...`n" "Yellow"
    
    $sourcePattern = Join-Path $backupDir "*"
    
    try {
        $compressArgs = @(
            "a",                    # Add
            "-t7z",                 # Type 7z
            "-mx=5",                # Compression level 5 (medium)
            "-mmt=on",              # Multithreading
            "-v500m",               # Split into 500MB volumes
            "`"$zipFile`"",
            "`"$sourcePattern`""
        )
        
        & $7zip $compressArgs 2>&1 | Out-Null
        
        if($LASTEXITCODE -le 1){
            $pattern = [System.IO.Path]::GetFileNameWithoutExtension($zipFile) + ".7z.*"
            $parts = Get-ChildItem "C:\BackupTemp" -Filter $pattern -ErrorAction SilentlyContinue
            
            if($parts){
                $totalSize = ($parts | Measure-Object Length -Sum).Sum
                $totalGB = [math]::Round($totalSize/1GB, 2)
                Log "  [OK] $($parts.Count) partes creadas, $totalGB GB total" "Green"
                
                Log "`n[ARCHIVOS CREADOS]:" "Cyan"
                foreach($part in $parts){
                    $partSizeMB = [math]::Round($part.Length/1MB, 2)
                    Log "  - $($part.Name): $partSizeMB MB" "White"
                }
                
                Log "`n===== BACKUP COMPLETADO =====" "Green"
                Log "Datos originales: $totalCopied MB ($([math]::Round($totalCopied/1024,2)) GB)" "White"
                Log "Comprimido a: $totalGB GB" "White"
                Log "Ratio: $([math]::Round(($totalSize/$totalCopied*1024*1024)*100,1))%" "White"
                Log "Partes: $($parts.Count)" "White"
                Log "Ubicacion: C:\BackupTemp\" "Cyan"
                Log "Log completo: $logFile" "Gray"
                
                return @{
                    Success = $true
                    BackupName = $backupName
                    PartsCreated = $parts.Count
                    TotalSizeGB = $totalGB
                    OriginalSizeMB = $totalCopied
                    CompressionRatio = [math]::Round(($totalSize/($totalCopied*1024*1024))*100,1)
                    LogFile = $logFile
                    Parts = $parts | ForEach-Object { @{Name=$_.Name; SizeMB=[math]::Round($_.Length/1MB,2)} }
                }
            } else {
                Log "  [ERROR] No se crearon partes comprimidas" "Red"
                return @{Success=$false; Error="No compressed parts"; TotalCopiedMB=$totalCopied}
            }
        } else {
            Log "  [ERROR] Compresion fallo (codigo: $LASTEXITCODE)" "Red"
            return @{Success=$false; Error="Compression failed"; TotalCopiedMB=$totalCopied}
        }
    } catch {
        Log "  [ERROR] Excepcion en compresion: $_" "Red"
        return @{Success=$false; Error=$_.Exception.Message; TotalCopiedMB=$totalCopied}
    }
}

Write-Host "Ejecutando backup (tiempo estimado: 60-120 min)..." -ForegroundColor Yellow
Write-Host "El proceso mostrara progreso en tiempo real.`n" -ForegroundColor Gray

try {
    $result = Invoke-Command -Session $session -ScriptBlock $remoteScript
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "RESULTADO FINAL" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    if($result.Success){
        Write-Host "[OK] BACKUP COMPLETO EXITOSO!" -ForegroundColor Green
        Write-Host "`nEstadisticas:" -ForegroundColor Cyan
        Write-Host "  Datos originales: $($result.OriginalSizeMB) MB ($([math]::Round($result.OriginalSizeMB/1024,2)) GB)" -ForegroundColor White
        Write-Host "  Comprimido a: $($result.TotalSizeGB) GB" -ForegroundColor White
        Write-Host "  Ratio compresion: $($result.CompressionRatio)%" -ForegroundColor White
        Write-Host "  Partes creadas: $($result.PartsCreated)" -ForegroundColor White
        
        Write-Host "`nArchivos:" -ForegroundColor Cyan
        foreach($part in $result.Parts){
            Write-Host "  - $($part.Name): $($part.SizeMB) MB" -ForegroundColor White
        }
        
        Write-Host "`nUbicacion en Civer-Two:" -ForegroundColor Cyan
        Write-Host "  C:\BackupTemp\$($result.BackupName)*" -ForegroundColor Yellow
        Write-Host "  Log: $($result.LogFile)" -ForegroundColor Gray
        
        # Copiar a Civer-One
        Write-Host "`n[COPIANDO A CIVER-ONE]..." -ForegroundColor Cyan
        $copied = 0
        $failed = 0
        $totalSizeMB = 0
        
        foreach($part in $result.Parts){
            $remotePath = "C:\BackupTemp\$($part.Name)"
            $localPath = "C:\BackupTemp\$($part.Name)"
            
            try {
                Write-Host "  $($part.Name) ($($part.SizeMB) MB)..." -NoNewline
                Copy-Item -Path $remotePath -Destination $localPath -FromSession $session -Force -ErrorAction Stop
                
                if(Test-Path $localPath){
                    Write-Host " [OK]" -ForegroundColor Green
                    $copied++
                    $totalSizeMB += $part.SizeMB
                } else {
                    Write-Host " [ERROR]" -ForegroundColor Red
                    $failed++
                }
            } catch {
                Write-Host " [ERROR] $_" -ForegroundColor Red
                $failed++
            }
        }
        
        Write-Host "`n[RESUMEN]" -ForegroundColor Green
        Write-Host "  Archivos copiados: $copied de $($result.PartsCreated)" -ForegroundColor White
        Write-Host "  Tamano total: $([math]::Round($totalSizeMB/1024,2)) GB" -ForegroundColor White
        Write-Host "  Fallidos: $failed" -ForegroundColor $(if($failed -gt 0){'Red'}else{'Green'})
        Write-Host "`n  Ubicacion en Civer-One:" -ForegroundColor Cyan
        Write-Host "  C:\BackupTemp\$($result.BackupName).7z.*" -ForegroundColor Yellow
        
        if($copied -eq $result.PartsCreated){
            Write-Host "`n[EXITO TOTAL]" -ForegroundColor Green
            Write-Host "Todos los archivos backup fueron copiados exitosamente!" -ForegroundColor White
            Write-Host "`nPROXIMO PASO:" -ForegroundColor Yellow
            Write-Host "  Transferir desde Civer-One a RESPALDO-1 usando:" -ForegroundColor White
            Write-Host "  - SCP/SFTP con WinSCP o FileZilla" -ForegroundColor Gray
            Write-Host "  - O crear recurso compartido SMB" -ForegroundColor Gray
        }
        
    } else {
        Write-Host "[ERROR] Backup fallo" -ForegroundColor Red
        Write-Host "  Razon: $($result.Error)" -ForegroundColor Yellow
        if($result.TotalCopiedMB){
            Write-Host "  Datos copiados: $($result.TotalCopiedMB) MB" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "[ERROR] Excepcion en ejecucion: $_" -ForegroundColor Red
} finally {
    Remove-PSSession $session
    Write-Host "`nSesion cerrada." -ForegroundColor Gray
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
