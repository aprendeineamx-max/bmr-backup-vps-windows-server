# RESTAURAR BACKUP BMR COMPLETO EN RESPALDO-1
# Transfiere archivos desde Civer-One y restaura en RESPALDO-1

param(
    [string]$SourceIP = "216.238.80.222",      # Civer-One (donde están los backups)
    [string]$SourceUser = "Administrator",
    [string]$SourcePass = "g#7UH-jM{otz9bd@",
    
    [string]$DestIP = "216.238.84.243",        # RESPALDO-1 (destino)
    [string]$DestUser = "Administrator",
    [string]$DestPass = "VL0jh-eDuT7+ftUz",
    
    [string]$BackupName = "CIVER-TWO-BMR-COMPLETO-20251104-195448"
)

$ErrorActionPreference = "Continue"

Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RESTAURACION BMR COMPLETA EN RESPALDO-1           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "[FASE 1: VERIFICACION]" -ForegroundColor Yellow
Write-Host "Verificando archivos backup en Civer-One...`n" -ForegroundColor White

# Conectar a Civer-One (origen)
Write-Host "Conectando a Civer-One ($SourceIP)..." -ForegroundColor Cyan
$sourceSecPass = ConvertTo-SecureString $SourcePass -AsPlainText -Force
$sourceCred = New-Object PSCredential($SourceUser, $sourceSecPass)
$sourceSession = New-PSSession -ComputerName $SourceIP -Credential $sourceCred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)

if($sourceSession){
    Write-Host "[OK] Conectado a Civer-One`n" -ForegroundColor Green
    
    # Verificar archivos backup
    $backupFiles = Invoke-Command -Session $sourceSession -ScriptBlock {
        param($name)
        $pattern = "$name.7z.*"
        Get-ChildItem "C:\BackupTemp" -Filter $pattern | Select-Object Name, @{N="SizeMB";E={[math]::Round($_.Length/1MB,2)}}, @{N="SizeGB";E={[math]::Round($_.Length/1GB,2)}}
    } -ArgumentList $BackupName
    
    if($backupFiles){
        Write-Host "Archivos encontrados en Civer-One:" -ForegroundColor Green
        $totalSize = ($backupFiles | Measure-Object SizeMB -Sum).Sum
        foreach($file in $backupFiles){
            $fname = $file.Name
            $fmb = $file.SizeMB
            $fgb = $file.SizeGB
            Write-Host "  - $fname : $fmb MB ($fgb GB)" -ForegroundColor White
        }
        $totalGB = [math]::Round($totalSize/1024,2)
        Write-Host "`nTotal: $($backupFiles.Count) archivos, $totalGB GB`n" -ForegroundColor Cyan
    } else {
        Write-Host "[ERROR] No se encontraron archivos backup!" -ForegroundColor Red
        Write-Host "Buscando: C:\BackupTemp\$BackupName.7z.*" -ForegroundColor Gray
        Remove-PSSession $sourceSession
        exit 1
    }
} else {
    Write-Host "[ERROR] No se pudo conectar a Civer-One" -ForegroundColor Red
    exit 1
}

# Conectar a RESPALDO-1 (destino)
Write-Host "Conectando a RESPALDO-1 ($DestIP)..." -ForegroundColor Cyan
$destSecPass = ConvertTo-SecureString $DestPass -AsPlainText -Force
$destCred = New-Object PSCredential($DestUser, $destSecPass)
$destSession = New-PSSession -ComputerName $DestIP -Credential $destCred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)

if($destSession){
    Write-Host "[OK] Conectado a RESPALDO-1`n" -ForegroundColor Green
    
    # Verificar espacio disponible
    $destInfo = Invoke-Command -Session $destSession -ScriptBlock {
        $disk = Get-PSDrive C
        @{
            Hostname = $env:COMPUTERNAME
            OS = (Get-CimInstance Win32_OperatingSystem).Caption
            FreeGB = [math]::Round($disk.Free/1GB, 2)
            UsedGB = [math]::Round($disk.Used/1GB, 2)
            TotalGB = [math]::Round(($disk.Used + $disk.Free)/1GB, 2)
        }
    }
    
    Write-Host "Informacion de RESPALDO-1:" -ForegroundColor Cyan
    Write-Host "  Hostname: $($destInfo.Hostname)" -ForegroundColor White
    Write-Host "  OS: $($destInfo.OS)" -ForegroundColor White
    Write-Host "  Disco C: $($destInfo.UsedGB) GB usado, $($destInfo.FreeGB) GB libre" -ForegroundColor White
    
    $requiredSpace = [math]::Round($totalSize/1024, 2) + 25 # Backup + espacio para extracción
    if($destInfo.FreeGB -lt $requiredSpace){
        Write-Host "`n[ADVERTENCIA] Espacio insuficiente!" -ForegroundColor Yellow
        Write-Host "  Requerido: ~$requiredSpace GB (backup + extraccion)" -ForegroundColor Yellow
        Write-Host "  Disponible: $($destInfo.FreeGB) GB" -ForegroundColor Yellow
        Write-Host "`n¿Continuar de todos modos? (S/N): " -NoNewline -ForegroundColor Yellow
        $continue = Read-Host
        if($continue -ne "S" -and $continue -ne "s"){
            Write-Host "Cancelado por el usuario" -ForegroundColor Red
            Remove-PSSession $sourceSession, $destSession
            exit 1
        }
    } else {
        Write-Host "  [OK] Espacio suficiente`n" -ForegroundColor Green
    }
    
    # Crear directorio de trabajo
    Invoke-Command -Session $destSession -ScriptBlock {
        New-Item -Path "C:\Restore" -ItemType Directory -Force | Out-Null
        New-Item -Path "C:\Restore\Backup" -ItemType Directory -Force | Out-Null
    }
} else {
    Write-Host "[ERROR] No se pudo conectar a RESPALDO-1" -ForegroundColor Red
    Remove-PSSession $sourceSession
    exit 1
}

Write-Host "`n[FASE 2: TRANSFERENCIA]" -ForegroundColor Yellow
Write-Host "Transfiriendo $($backupFiles.Count) archivos desde Civer-One a RESPALDO-1..." -ForegroundColor White
Write-Host "Esto puede tardar 30-60 minutos...`n" -ForegroundColor Yellow

$transferStart = Get-Date
$transferred = 0
$failed = 0

foreach($file in $backupFiles){
    $fileName = $file.Name
    $fileSizeMB = $file.SizeMB
    $transferMsg = "  Transfiriendo: $fileName (" + $fileSizeMB + " MB)..."
    
    Write-Host $transferMsg -NoNewline
    
    try {
        # Copiar de Civer-One a equipo local (intermedio)
        $tempLocal = "C:\BackupTemp\$fileName"
        $sourceRemote = "C:\BackupTemp\$fileName"
        
        Copy-Item -Path $sourceRemote -Destination $tempLocal -FromSession $sourceSession -Force -ErrorAction Stop
        
        # Copiar de equipo local a RESPALDO-1
        $destRemote = "C:\Restore\Backup\$fileName"
        Copy-Item -Path $tempLocal -Destination $destRemote -ToSession $destSession -Force -ErrorAction Stop
        
        # Verificar tamaño
        $destSize = Invoke-Command -Session $destSession -ScriptBlock {
            param($path)
            if(Test-Path $path){
                return [math]::Round((Get-Item $path).Length/1MB, 2)
            }
            return 0
        } -ArgumentList $destRemote
        
        if($destSize -eq $fileSizeMB){
            Write-Host " [OK]" -ForegroundColor Green
            $transferred++
            
            # Limpiar archivo temporal local
            Remove-Item $tempLocal -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host " [ERROR] Tamaño no coincide" -ForegroundColor Red
            $failed++
        }
        
    } catch {
        Write-Host " [ERROR] $_" -ForegroundColor Red
        $failed++
    }
}

$transferEnd = Get-Date
$transferDuration = ($transferEnd - $transferStart).TotalMinutes

Write-Host "`n[RESUMEN TRANSFERENCIA]" -ForegroundColor Cyan
Write-Host "  Transferidos: $transferred de $($backupFiles.Count)" -ForegroundColor White
Write-Host "  Fallidos: $failed" -ForegroundColor $(if($failed -gt 0){'Red'}else{'Green'})
Write-Host "  Duracion: $([math]::Round($transferDuration, 1)) minutos`n" -ForegroundColor White

if($transferred -lt $backupFiles.Count){
    Write-Host "[ERROR] No se transfirieron todos los archivos!" -ForegroundColor Red
    Write-Host "No se puede continuar con la restauracion." -ForegroundColor Yellow
    Remove-PSSession $sourceSession, $destSession
    exit 1
}

Write-Host "`n[FASE 3: EXTRACCION]" -ForegroundColor Yellow
Write-Host "Extrayendo backup en RESPALDO-1...`n" -ForegroundColor White

$extractResult = Invoke-Command -Session $destSession -ScriptBlock {
    param($backupName)
    
    $logFile = "C:\Restore\restore-log.txt"
    function Log { 
        param($msg, $color = "White")
        $line = "$([DateTime]::Now.ToString('HH:mm:ss')) $msg"
        $line | Out-File -FilePath $logFile -Append -Encoding UTF8
        Write-Host $line -ForegroundColor $color
    }
    
    Log "===== EXTRACCION DE BACKUP =====" "Green"
    
    # Verificar/Instalar 7-Zip
    $7zip = "C:\Program Files\7-Zip\7z.exe"
    if(!(Test-Path $7zip)){
        Log "Instalando 7-Zip..." "Cyan"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
            $installer = "$env:TEMP\7zip.msi"
            Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing -TimeoutSec 120
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
            Start-Sleep -Seconds 5
            
            if(Test-Path $7zip){
                Log "  [OK] 7-Zip instalado" "Green"
            } else {
                Log "  [ERROR] No se pudo instalar 7-Zip" "Red"
                return @{Success=$false; Error="7-Zip install failed"}
            }
        } catch {
            Log "  [ERROR] $_" "Red"
            return @{Success=$false; Error=$_.Exception.Message}
        }
    } else {
        Log "7-Zip ya instalado" "Green"
    }
    
    # Extraer backup
    $firstPart = "C:\Restore\Backup\$backupName.7z.001"
    $extractPath = "C:\Restore\Extracted"
    
    if(!(Test-Path $firstPart)){
        Log "[ERROR] No se encuentra archivo: $firstPart" "Red"
        return @{Success=$false; Error="First part not found"}
    }
    
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
    
    Log "`nExtrayendo: $firstPart" "Cyan"
    Log "Destino: $extractPath" "Cyan"
    Log "Esto puede tardar 20-40 minutos...`n" "Yellow"
    
    $extractStart = Get-Date
    
    try {
        & $7zip x $firstPart -o"$extractPath" -y 2>&1 | Out-Null
        
        if($LASTEXITCODE -eq 0){
            $extractEnd = Get-Date
            $extractDuration = ($extractEnd - $extractStart).TotalMinutes
            
            Log "[OK] Extraccion completada en $([math]::Round($extractDuration, 1)) minutos" "Green"
            
            # Verificar carpetas extraídas
            $folders = Get-ChildItem $extractPath -Directory
            Log "`nCarpetas extraidas:" "Cyan"
            foreach($folder in $folders){
                $size = (Get-ChildItem $folder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sizeMB = [math]::Round($size/1MB, 2)
                $sizeGB = [math]::Round($size/1GB, 2)
                $fileCount = (Get-ChildItem $folder.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                $folderMsg = "  - " + $folder.Name + ": $fileCount archivos, $sizeMB MB ($sizeGB GB)"
                Log $folderMsg "White"
            }
            
            return @{
                Success = $true
                ExtractPath = $extractPath
                ExtractDuration = [math]::Round($extractDuration, 1)
                Folders = $folders | ForEach-Object { $_.Name }
            }
        } else {
            Log "[ERROR] Extraccion fallo (codigo: $LASTEXITCODE)" "Red"
            return @{Success=$false; Error="Extract failed with code $LASTEXITCODE"}
        }
    } catch {
        Log "[ERROR] Excepcion: $_" "Red"
        return @{Success=$false; Error=$_.Exception.Message}
    }
} -ArgumentList $BackupName

if($extractResult.Success){
    Write-Host "`n[OK] Extraccion exitosa!" -ForegroundColor Green
    Write-Host "  Ubicacion: $($extractResult.ExtractPath)" -ForegroundColor Cyan
    Write-Host "  Duracion: $($extractResult.ExtractDuration) minutos`n" -ForegroundColor White
} else {
    Write-Host "`n[ERROR] Extraccion fallo: $($extractResult.Error)" -ForegroundColor Red
    Remove-PSSession $sourceSession, $destSession
    exit 1
}

Write-Host "`n[FASE 4: ANALISIS DEL BACKUP]" -ForegroundColor Yellow
Write-Host "Analizando contenido para verificar si es BMR completo...`n" -ForegroundColor White

$analysis = Invoke-Command -Session $destSession -ScriptBlock {
    $extractPath = "C:\Restore\Extracted"
    
    $result = @{
        HasUsers = Test-Path "$extractPath\Users"
        HasProgramData = Test-Path "$extractPath\ProgramData"
        HasProgramFiles = Test-Path "$extractPath\ProgramFiles"
        HasProgramFilesx86 = Test-Path "$extractPath\ProgramFilesx86"
        HasWindowsConfig = Test-Path "$extractPath\WindowsConfig"
        
        MissingBootFiles = $true
        MissingSystemFiles = $true
        IsBootable = $false
        IsBMRComplete = $false
    }
    
    # Verificar archivos críticos de arranque
    $bootFiles = @(
        "$extractPath\WindowsConfig\BCD-Template",
        "$extractPath\WindowsConfig\SYSTEM",
        "$extractPath\WindowsConfig\SOFTWARE"
    )
    
    $result.MissingBootFiles = $false
    foreach($file in $bootFiles){
        if(!(Test-Path $file)){
            $result.MissingBootFiles = $true
            break
        }
    }
    
    # Verificar si tiene archivos de sistema Windows
    if($result.HasWindowsConfig){
        $sysFiles = Get-ChildItem "$extractPath\WindowsConfig" -File -ErrorAction SilentlyContinue
        if($sysFiles.Count -gt 0){
            $result.MissingSystemFiles = $false
        }
    }
    
    # Determinar si es BMR completo (archivo-nivel)
    $result.IsBMRComplete = $result.HasUsers -and 
                           $result.HasProgramData -and 
                           $result.HasProgramFiles -and 
                           $result.HasWindowsConfig
    
    # Determinar si puede ser booteable
    # Un backup de archivos NO puede ser booteable directamente
    # Necesitaría imagen de disco completa (VHD/VHDX)
    $result.IsBootable = $false
    $result.BootableReason = "Este es un backup a nivel de ARCHIVOS, no imagen de disco. No es booteable directamente."
    
    return $result
}

Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ANALISIS DEL BACKUP BMR                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Componentes encontrados:" -ForegroundColor Yellow
Write-Host "  Users (perfiles):        " -NoNewline; Write-Host $(if($analysis.HasUsers){"✓ SI"}else{"✗ NO"}) -ForegroundColor $(if($analysis.HasUsers){"Green"}else{"Red"})
Write-Host "  ProgramData:             " -NoNewline; Write-Host $(if($analysis.HasProgramData){"✓ SI"}else{"✗ NO"}) -ForegroundColor $(if($analysis.HasProgramData){"Green"}else{"Red"})
Write-Host "  Program Files:           " -NoNewline; Write-Host $(if($analysis.HasProgramFiles){"✓ SI"}else{"✗ NO"}) -ForegroundColor $(if($analysis.HasProgramFiles){"Green"}else{"Red"})
Write-Host "  Program Files (x86):     " -NoNewline; Write-Host $(if($analysis.HasProgramFilesx86){"✓ SI"}else{"✗ NO"}) -ForegroundColor $(if($analysis.HasProgramFilesx86){"Green"}else{"Red"})
Write-Host "  Windows Config (Registro):" -NoNewline; Write-Host $(if($analysis.HasWindowsConfig){"✓ SI"}else{"✗ NO"}) -ForegroundColor $(if($analysis.HasWindowsConfig){"Green"}else{"Red"})

Write-Host "`n┌─────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  TIPO DE BACKUP: " -NoNewline -ForegroundColor Cyan
if($analysis.IsBMRComplete){
    Write-Host "BMR COMPLETO (Archivos)      │" -ForegroundColor Green
} else {
    Write-Host "BACKUP PARCIAL               │" -ForegroundColor Yellow
}
Write-Host "└─────────────────────────────────────────────────────┘`n" -ForegroundColor Cyan

Write-Host "┌─────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  ¿ES BOOTEABLE?: " -NoNewline -ForegroundColor Cyan
if($analysis.IsBootable){
    Write-Host "SI                          │" -ForegroundColor Green
} else {
    Write-Host "NO                          │" -ForegroundColor Red
}
Write-Host "└─────────────────────────────────────────────────────┘" -ForegroundColor Cyan

Write-Host "`nRazon:" -ForegroundColor Yellow
Write-Host "  $($analysis.BootableReason)" -ForegroundColor White

Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  EXPLICACION TECNICA                                ║" -ForegroundColor Yellow
Write-Host "╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

Write-Host "1. BACKUP ACTUAL (Nivel de Archivos):" -ForegroundColor Cyan
Write-Host "   ✓ Contiene: Archivos y carpetas del sistema" -ForegroundColor White
Write-Host "   ✓ Permite: Restaurar datos, configuraciones, programas" -ForegroundColor White
Write-Host "   ✗ NO contiene: Estructura de particiones, MBR/GPT, bootloader" -ForegroundColor Yellow
Write-Host "   ✗ NO puede: Arrancar directamente como ISO/disco booteable`n" -ForegroundColor Yellow

Write-Host "2. PARA CONVERTIR A BOOTEABLE SE NECESITARIA:" -ForegroundColor Cyan
Write-Host "   • Crear imagen VHD/VHDX con estructura de particiones" -ForegroundColor White
Write-Host "   • Instalar bootloader (UEFI/BIOS)" -ForegroundColor White
Write-Host "   • Configurar BCD (Boot Configuration Data)" -ForegroundColor White
Write-Host "   • Crear ISO con Windows PE + herramientas de despliegue" -ForegroundColor White
Write-Host "   • Usar herramientas como DISM, WinPE, Macrium, o Clonezilla`n" -ForegroundColor White

Write-Host "3. USO RECOMENDADO DE ESTE BACKUP:" -ForegroundColor Cyan
Write-Host "   → Restaurar SOBRE un Windows Server ya instalado" -ForegroundColor Green
Write-Host "   → Copiar archivos a sus ubicaciones originales" -ForegroundColor Green
Write-Host "   → Reemplazar configuraciones y datos de usuario" -ForegroundColor Green
Write-Host "   → Recuperar aplicaciones y configuraciones`n" -ForegroundColor Green

# Cerrar sesiones
Remove-PSSession $sourceSession, $destSession

Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  RESUMEN FINAL                                      ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "Estado del backup:" -ForegroundColor Cyan
Write-Host "  • Ubicacion: C:\Restore\Extracted en RESPALDO-1" -ForegroundColor White
Write-Host "  • Tipo: BMR Completo (nivel archivos)" -ForegroundColor White
Write-Host "  • Booteable: NO (requiere conversion)" -ForegroundColor White
Write-Host "  • Listo para: Restauracion manual de archivos`n" -ForegroundColor White

Write-Host "Proximos pasos:" -ForegroundColor Yellow
Write-Host "  1. Revisar archivos extraidos en C:\Restore\Extracted" -ForegroundColor White
Write-Host "  2. Copiar carpetas a ubicaciones originales" -ForegroundColor White
Write-Host "  3. Para booteable: Usar herramienta de imagen de disco" -ForegroundColor White

Write-Host "`n¿Deseas crear un script para hacer booteable? (S/N): " -NoNewline -ForegroundColor Yellow
$createBootable = Read-Host

if($createBootable -eq "S" -or $createBootable -eq "s"){
    Write-Host "`nCreando script de conversion a booteable..." -ForegroundColor Cyan
    Write-Host "[NOTA] Esto requiere herramientas adicionales de Windows PE" -ForegroundColor Yellow
    Write-Host "y no puede hacerse completamente via remoto.`n" -ForegroundColor Yellow
    
    # Aquí iría el código para crear ISO booteable
    Write-Host "Script de booteable necesitaría:" -ForegroundColor Cyan
    Write-Host "  - Windows ADK (Assessment and Deployment Kit)" -ForegroundColor White
    Write-Host "  - Crear WinPE (Windows Preinstallation Environment)" -ForegroundColor White
    Write-Host "  - Integrar backup en imagen WIM" -ForegroundColor White
    Write-Host "  - Crear ISO booteable con oscdimg.exe`n" -ForegroundColor White
}

Write-Host "Sesiones cerradas. Proceso completado.`n" -ForegroundColor Green
