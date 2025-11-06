# BACKUP BMR COMPLETO - INCLUYE TODO SIN EXCLUSIONES
# Para restauración completa del sistema en VPS destino

param(
    [string]$TargetIP = "216.238.88.126",
    [string]$Username = "Administrator",
    [string]$Password = "6K#fVnH-arJG-(wT"
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BACKUP BMR COMPLETO - SIN EXCLUSIONES" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "Este backup incluye:" -ForegroundColor Cyan
Write-Host "  - C:\Users (COMPLETO con todas las extensiones VS Code)" -ForegroundColor White
Write-Host "  - C:\ProgramData (COMPLETO)" -ForegroundColor White
Write-Host "  - C:\Program Files (COMPLETO)" -ForegroundColor White
Write-Host "  - C:\Program Files (x86) (COMPLETO)" -ForegroundColor White
Write-Host "  - C:\Windows\System32\config (Registro)" -ForegroundColor White
Write-Host "`nTiempo estimado: 2-4 horas segun tamano" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Conectando a $TargetIP..." -ForegroundColor Cyan
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)
$session = New-PSSession -ComputerName $TargetIP -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "[OK] Sesion establecida`n" -ForegroundColor Green

$remoteScript = {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "CIVER-TWO-BMR-COMPLETO-$timestamp"
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
    
    Log "===== BACKUP BMR COMPLETO - SIN EXCLUSIONES =====" "Green"
    Log "Servidor: $env:COMPUTERNAME" "Cyan"
    Log "Backup Name: $backupName" "Cyan"
    
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
        Log "PsExec disponible" "Green"
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
    
    # Carpetas COMPLETAS a respaldar (SIN EXCLUSIONES)
    $foldersToBackup = @(
        @{Source="C:\Users"; Dest="Users"; Priority="Critical"},
        @{Source="C:\ProgramData"; Dest="ProgramData"; Priority="Critical"},
        @{Source="C:\Program Files"; Dest="ProgramFiles"; Priority="High"},
        @{Source="C:\Program Files (x86)"; Dest="ProgramFilesx86"; Priority="High"},
        @{Source="C:\Windows\System32\config"; Dest="WindowsConfig"; Priority="Critical"}
    )
    
    Log "`n[COPIANDO ARCHIVOS COMPLETOS COMO SYSTEM]..." "Cyan"
    Log "Usando PsExec para permisos SYSTEM completos" "Yellow"
    Log "SIN EXCLUSIONES - Se copiara TODO`n" "Yellow"
    
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
        
        # Calcular tamaño origen
        try {
            $sourceSize = (Get-ChildItem $source -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $sourceSizeMB = [math]::Round($sourceSize/1MB, 2)
            $sourceSizeGB = [math]::Round($sourceSize/1GB, 2)
            Log "  Origen: $source" "White"
            Log "    Tamaño: $sourceSizeMB MB ($sourceSizeGB GB)" "Gray"
            Log "    Prioridad: $($folder.Priority)" "Gray"
        } catch {
            Log "  Origen: $source" "White"
            Log "    No se pudo calcular tamaño" "Gray"
        }
        
        # Crear directorio destino
        New-Item -Path $dest -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        
        # Comando robocopy SIN EXCLUSIONES
        # /B = Backup mode (SeBackupPrivilege)
        # /COPYALL = Copia TODO (datos, atributos, timestamps, seguridad, owner, auditoría)
        # /E = Todos los subdirectorios incluyendo vacíos
        # /R:3 = 3 reintentos en archivos bloqueados
        # /W:3 = 3 segundos entre reintentos
        # /MT:4 = 4 threads paralelos
        # /XJ = Excluir junction points (para evitar loops)
        # NO XD = NO excluir directorios - copiamos TODO
        
        $robocopyCmd = "robocopy `"$source`" `"$dest`" /E /B /COPYALL /R:3 /W:3 /MT:4 /XJ /NP /NFL /NDL"
        
        # Log del comando
        $cmdLog = Join-Path $backupDir "cmd_$destName.txt"
        "COMANDO: $robocopyCmd`n`nSALIDA:" | Out-File $cmdLog -Encoding UTF8
        
        Log "    Iniciando copia..." "Cyan"
        
        # Ejecutar como SYSTEM usando PsExec
        try {
            # Usar PsExec para ejecutar robocopy como SYSTEM
            $psexecArgs = @(
                "-accepteula",
                "-nobanner", 
                "-s",  # SYSTEM account
                "-w", "`"$backupDir`"",  # Working directory
                "cmd.exe",
                "/c",
                "`"$robocopyCmd >> `"$cmdLog`" 2>&1`""
            )
            
            $process = Start-Process -FilePath $psexecPath -ArgumentList $psexecArgs -Wait -PassThru -NoNewWindow -ErrorAction Continue
            
            $exitCode = $process.ExitCode
            
            # Códigos robocopy: 
            # 0 = No files copied (already up to date)
            # 1 = Files copied successfully
            # 2 = Extra files/folders detected
            # 3 = Files copied + extras detected
            # 4 = Mismatched files/folders detected
            # 5 = Files copied + mismatches
            # 6 = Extra + mismatches
            # 7 = Files copied + extras + mismatches
            # 8+ = ERRORES
            
            if($exitCode -le 7){
                if(Test-Path $dest){
                    $files = Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue
                    $size = ($files | Measure-Object Length -Sum).Sum
                    $sizeMB = [math]::Round($size/1MB, 2)
                    $sizeGB = [math]::Round($size/1GB, 2)
                    $fileCount = $files.Count
                    
                    $statusColor = "Green"
                    if($exitCode -eq 0){ $status = "Sin cambios" }
                    elseif($exitCode -eq 1){ $status = "Copiado OK" }
                    elseif($exitCode -le 3){ $status = "OK con extras" }
                    elseif($exitCode -le 7){ $status = "OK con diferencias" }
                    
                    Log "    [OK] $status - $fileCount archivos" "Green"
                    Log "    Copiado: $sizeMB MB ($sizeGB GB)" "Green"
                    Log "    Codigo robocopy: $exitCode" "Gray"
                    $totalCopied += $sizeMB
                    $successCount++
                } else {
                    Log "    [!] Directorio destino no creado" "Yellow"
                }
            } else {
                Log "    [ERROR] Robocopy fallo (codigo: $exitCode)" "Red"
                Log "    Ver detalles en: $cmdLog" "Gray"
                
                # Leer últimas líneas del log para diagnóstico
                if(Test-Path $cmdLog){
                    $lastLines = Get-Content $cmdLog -Tail 10 -ErrorAction SilentlyContinue
                    if($lastLines){
                        Log "    Ultimas lineas del error:" "Gray"
                        $lastLines | ForEach-Object { Log "      $_" "Gray" }
                    }
                }
            }
            
        } catch {
            Log "    [ERROR] Excepcion: $_" "Red"
        }
        
        Log "" "White"
    }
    
    $totalGB = [math]::Round($totalCopied/1024, 2)
    Log "TOTAL COPIADO: $totalCopied MB ($totalGB GB)" "Cyan"
    Log "Carpetas exitosas: $successCount de $($foldersToBackup.Count)" "Cyan"
    
    # Si no se copió suficiente, advertencia
    if($totalCopied -lt 100){
        Log "`n[ADVERTENCIA] Solo se copiaron $totalCopied MB" "Yellow"
        Log "Es posible que haya habido errores. Revisar logs." "Yellow"
    }
    
    # Comprimir
    Log "`n[COMPRIMIENDO BACKUP COMPLETO]..." "Cyan"
    $zipFile = "C:\BackupTemp\$backupName.7z"
    Log "  Archivo: $zipFile" "White"
    Log "  Dividido en partes de 1000MB (1GB)" "Gray"
    Log "  Nivel de compresion: 5 (medio - balance velocidad/tamaño)" "Gray"
    Log "  Incluyendo TODO sin exclusiones..." "Yellow"
    Log "  Esto puede tardar 30-90 minutos dependiendo del tamaño...`n" "Yellow"
    
    $sourcePattern = Join-Path $backupDir "*"
    
    try {
        $compressArgs = @(
            "a",                    # Add
            "-t7z",                 # Type 7z
            "-mx=5",                # Compression level 5 (medium)
            "-mmt=on",              # Multithreading ON
            "-v1000m",              # Split into 1000MB (1GB) volumes
            "-bsp1",                # Show progress every 1%
            "`"$zipFile`"",
            "`"$sourcePattern`""
        )
        
        Log "  Ejecutando 7-Zip..." "Cyan"
        $compressStart = Get-Date
        
        & $7zip $compressArgs 2>&1 | Out-Null
        
        $compressEnd = Get-Date
        $compressDuration = ($compressEnd - $compressStart).TotalMinutes
        
        if($LASTEXITCODE -le 1){
            $pattern = [System.IO.Path]::GetFileNameWithoutExtension($zipFile) + ".7z.*"
            $parts = Get-ChildItem "C:\BackupTemp" -Filter $pattern -ErrorAction SilentlyContinue
            
            if($parts){
                $totalSize = ($parts | Measure-Object Length -Sum).Sum
                $totalCompressedGB = [math]::Round($totalSize/1GB, 2)
                $compressionRatio = [math]::Round(($totalSize / ($totalCopied * 1024 * 1024)) * 100, 1)
                
                Log "  [OK] Compresion completada en $([math]::Round($compressDuration, 1)) minutos" "Green"
                Log "  Partes creadas: $($parts.Count)" "Green"
                Log "  Tamaño comprimido: $totalCompressedGB GB" "Green"
                Log "  Ratio compresion: $compressionRatio%" "Green"
                
                Log "`n[ARCHIVOS CREADOS]:" "Cyan"
                foreach($part in $parts){
                    $partSizeMB = [math]::Round($part.Length/1MB, 2)
                    $partSizeGB = [math]::Round($part.Length/1GB, 2)
                    Log "  - $($part.Name): $partSizeMB MB ($partSizeGB GB)" "White"
                }
                
                Log "`n===== BACKUP BMR COMPLETO EXITOSO =====" "Green"
                Log "Datos originales: $totalCopied MB ($totalGB GB)" "White"
                Log "Comprimido a: $totalCompressedGB GB" "White"
                Log "Ahorro de espacio: $([math]::Round(100 - $compressionRatio, 1))%" "White"
                Log "Partes: $($parts.Count) archivos de 1GB cada uno" "White"
                Log "Duracion compresion: $([math]::Round($compressDuration, 1)) minutos" "White"
                Log "Ubicacion: C:\BackupTemp\" "Cyan"
                Log "Log completo: $logFile" "Gray"
                
                # Información para restauración
                Log "`n[INFORMACION PARA RESTAURACION]:" "Yellow"
                Log "1. Descargar TODAS las partes .7z.001, .7z.002, etc" "White"
                Log "2. En VPS destino, instalar 7-Zip" "White"
                Log "3. Extraer con: 7z x $($parts[0].Name)" "White"
                Log "4. Copiar carpetas extraidas a sus ubicaciones:" "White"
                Log "   - Users -> C:\Users" "Gray"
                Log "   - ProgramData -> C:\ProgramData" "Gray"
                Log "   - ProgramFiles -> C:\Program Files" "Gray"
                Log "   - ProgramFilesx86 -> C:\Program Files (x86)" "Gray"
                Log "   - WindowsConfig -> C:\Windows\System32\config (REQUIERE modo seguro)" "Gray"
                
                return @{
                    Success = $true
                    BackupName = $backupName
                    PartsCreated = $parts.Count
                    TotalSizeGB = $totalCompressedGB
                    OriginalSizeMB = $totalCopied
                    OriginalSizeGB = $totalGB
                    CompressionRatio = $compressionRatio
                    CompressionMinutes = [math]::Round($compressDuration, 1)
                    LogFile = $logFile
                    Parts = $parts | ForEach-Object { 
                        @{
                            Name=$_.Name
                            SizeMB=[math]::Round($_.Length/1MB,2)
                            SizeGB=[math]::Round($_.Length/1GB,2)
                        } 
                    }
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

Write-Host "Ejecutando backup COMPLETO (tiempo estimado: 2-4 horas)..." -ForegroundColor Yellow
Write-Host "El proceso mostrara progreso en tiempo real.`n" -ForegroundColor Gray

$startTime = Get-Date

try {
    $result = Invoke-Command -Session $session -ScriptBlock $remoteScript
    
    $endTime = Get-Date
    $totalDuration = ($endTime - $startTime).TotalMinutes
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "RESULTADO FINAL" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    if($result.Success){
        Write-Host "[OK] BACKUP BMR COMPLETO EXITOSO!" -ForegroundColor Green
        Write-Host "`nEstadisticas:" -ForegroundColor Cyan
        Write-Host "  Datos originales: $($result.OriginalSizeMB) MB ($($result.OriginalSizeGB) GB)" -ForegroundColor White
        Write-Host "  Comprimido a: $($result.TotalSizeGB) GB" -ForegroundColor White
        Write-Host "  Ratio compresion: $($result.CompressionRatio)%" -ForegroundColor White
        Write-Host "  Partes creadas: $($result.PartsCreated)" -ForegroundColor White
        Write-Host "  Duracion total: $([math]::Round($totalDuration, 1)) minutos" -ForegroundColor White
        
        Write-Host "`nArchivos en Civer-Two:" -ForegroundColor Cyan
        foreach($part in $result.Parts){
            Write-Host "  - $($part.Name): $($part.SizeMB) MB ($($part.SizeGB) GB)" -ForegroundColor White
        }
        
        Write-Host "`nUbicacion en Civer-Two:" -ForegroundColor Cyan
        Write-Host "  C:\BackupTemp\$($result.BackupName)*" -ForegroundColor Yellow
        Write-Host "  Log: $($result.LogFile)" -ForegroundColor Gray
        
        # Copiar a Civer-One
        Write-Host "`n[COPIANDO A CIVER-ONE]..." -ForegroundColor Cyan
        Write-Host "Transfiriendo $($result.TotalSizeGB) GB en $($result.PartsCreated) partes..." -ForegroundColor Yellow
        Write-Host "Esto puede tardar 10-30 minutos...`n" -ForegroundColor Yellow
        
        $copied = 0
        $failed = 0
        $totalSizeMB = 0
        $copyStart = Get-Date
        
        foreach($part in $result.Parts){
            $remotePath = "C:\BackupTemp\$($part.Name)"
            $localPath = "C:\BackupTemp\$($part.Name)"
            
            try {
                Write-Host "  $($part.Name) ($($part.SizeGB) GB)..." -NoNewline
                Copy-Item -Path $remotePath -Destination $localPath -FromSession $session -Force -ErrorAction Stop
                
                if(Test-Path $localPath){
                    $localSize = (Get-Item $localPath).Length
                    $localSizeMB = [math]::Round($localSize/1MB, 2)
                    if($localSizeMB -eq $part.SizeMB){
                        Write-Host " [OK]" -ForegroundColor Green
                        $copied++
                        $totalSizeMB += $part.SizeMB
                    } else {
                        Write-Host " [ERROR] Tamaño no coincide ($localSizeMB MB vs $($part.SizeMB) MB)" -ForegroundColor Red
                        $failed++
                    }
                } else {
                    Write-Host " [ERROR] No se creo archivo local" -ForegroundColor Red
                    $failed++
                }
            } catch {
                Write-Host " [ERROR] $_" -ForegroundColor Red
                $failed++
            }
        }
        
        $copyEnd = Get-Date
        $copyDuration = ($copyEnd - $copyStart).TotalMinutes
        
        Write-Host "`n[RESUMEN TRANSFERENCIA]" -ForegroundColor Green
        Write-Host "  Archivos copiados: $copied de $($result.PartsCreated)" -ForegroundColor White
        Write-Host "  Tamano total: $([math]::Round($totalSizeMB/1024,2)) GB" -ForegroundColor White
        Write-Host "  Fallidos: $failed" -ForegroundColor $(if($failed -gt 0){'Red'}else{'Green'})
        Write-Host "  Duracion copia: $([math]::Round($copyDuration, 1)) minutos" -ForegroundColor White
        Write-Host "`n  Ubicacion en Civer-One:" -ForegroundColor Cyan
        Write-Host "  C:\BackupTemp\$($result.BackupName).7z.*" -ForegroundColor Yellow
        
        if($copied -eq $result.PartsCreated){
            Write-Host "`n[EXITO TOTAL]" -ForegroundColor Green
            Write-Host "Backup BMR COMPLETO listo para transferir a RESPALDO-1!" -ForegroundColor White
            Write-Host "`nPROXIMOS PASOS:" -ForegroundColor Yellow
            Write-Host "  1. Descargar TODAS las partes desde Civer-One" -ForegroundColor White
            Write-Host "     Ubicacion: C:\BackupTemp\$($result.BackupName).7z.*" -ForegroundColor Gray
            Write-Host "  2. Subir a RESPALDO-1 (216.238.84.243)" -ForegroundColor White
            Write-Host "  3. En RESPALDO-1, extraer con 7-Zip" -ForegroundColor White
            Write-Host "  4. Restaurar carpetas a sus ubicaciones" -ForegroundColor White
            Write-Host "`nMetodos de transferencia:" -ForegroundColor Cyan
            Write-Host "  - WinSCP / FileZilla (SCP/SFTP)" -ForegroundColor Gray
            Write-Host "  - Recurso compartido SMB" -ForegroundColor Gray
            Write-Host "  - Vultr Object Storage (si se arregla S3)" -ForegroundColor Gray
        } else {
            Write-Host "`n[ATENCION]" -ForegroundColor Yellow
            Write-Host "Algunos archivos no se copiaron correctamente." -ForegroundColor Yellow
            Write-Host "Revisar errores arriba y reintentar copia de partes fallidas." -ForegroundColor Yellow
        }
        
    } else {
        Write-Host "[ERROR] Backup fallo" -ForegroundColor Red
        Write-Host "  Razon: $($result.Error)" -ForegroundColor Yellow
        if($result.TotalCopiedMB){
            Write-Host "  Datos copiados antes del error: $($result.TotalCopiedMB) MB" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "[ERROR] Excepcion en ejecucion: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
} finally {
    Remove-PSSession $session
    Write-Host "`nSesion cerrada." -ForegroundColor Gray
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
