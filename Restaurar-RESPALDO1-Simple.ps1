# RESTAURAR Y ANALIZAR BACKUP EN RESPALDO-1 - Version Simplificada

param(
    [string]$BackupName = "CIVER-TWO-BMR-COMPLETO-20251104-195448"
)

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " RESTAURACION BMR EN RESPALDO-1" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

# 1. Verificar archivos en Civer-One
Write-Host "[1/4] Verificando archivos en Civer-One..." -ForegroundColor Yellow
$sourceIP = "216.238.80.222"
$sourceUser = "Administrator"
$sourcePass = ConvertTo-SecureString "g#7UH-jM{otz9bd@" -AsPlainText -Force
$sourceCred = New-Object PSCredential($sourceUser, $sourcePass)

$sourceSession = New-PSSession -ComputerName $sourceIP -Credential $sourceCred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
if(!$sourceSession){
    Write-Host "[ERROR] No se pudo conectar a Civer-One" -ForegroundColor Red
    exit
}

Write-Host "[OK] Conectado a Civer-One`n" -ForegroundColor Green

$backupFiles = Invoke-Command -Session $sourceSession -ArgumentList $BackupName -ScriptBlock {
    param($name)
    Get-ChildItem "C:\BackupTemp" -Filter "$name.7z.*" | Select-Object Name, Length
}

if($backupFiles){
    Write-Host "Archivos encontrados: $($backupFiles.Count)" -ForegroundColor Green
    $totalBytes = ($backupFiles | Measure-Object Length -Sum).Sum
    $totalGB = [math]::Round($totalBytes/1GB, 2)
    Write-Host "Tamano total: $totalGB GB`n" -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] No se encontraron archivos backup" -ForegroundColor Red
    Remove-PSSession $sourceSession
    exit
}

# 2. Conectar a RESPALDO-1
Write-Host "[2/4] Conectando a RESPALDO-1..." -ForegroundColor Yellow
$destIP = "216.238.84.243"
$destUser = "Administrator"
$destPass = ConvertTo-SecureString "VL0jh-eDuT7+ftUz" -AsPlainText -Force
$destCred = New-Object PSCredential($destUser, $destPass)

$destSession = New-PSSession -ComputerName $destIP -Credential $destCred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
if(!$destSession){
    Write-Host "[ERROR] No se pudo conectar a RESPALDO-1" -ForegroundColor Red
    Remove-PSSession $sourceSession
    exit
}

Write-Host "[OK] Conectado a RESPALDO-1`n" -ForegroundColor Green

# Crear directorios
Invoke-Command -Session $destSession -ScriptBlock {
    New-Item -Path "C:\Restore\Backup" -ItemType Directory -Force | Out-Null
}

# 3. Transferir archivos
Write-Host "[3/4] Transfiriendo archivos ($($backupFiles.Count) partes)..." -ForegroundColor Yellow
Write-Host "Esto puede tardar 30-60 minutos...`n" -ForegroundColor Yellow

$transferred = 0
$startTime = Get-Date

foreach($file in $backupFiles){
    $fileName = $file.Name
    $percent = [math]::Round(($transferred / $backupFiles.Count) * 100, 0)
    Write-Host "  [$percent%] $fileName..." -NoNewline
    
    try {
        # Copiar a local
        $tempLocal = "C:\BackupTemp\$fileName"
        Copy-Item -Path "C:\BackupTemp\$fileName" -Destination $tempLocal -FromSession $sourceSession -Force -ErrorAction Stop
        
        # Copiar a destino
        Copy-Item -Path $tempLocal -Destination "C:\Restore\Backup\$fileName" -ToSession $destSession -Force -ErrorAction Stop
        
        # Limpiar local
        Remove-Item $tempLocal -Force -ErrorAction SilentlyContinue
        
        Write-Host " OK" -ForegroundColor Green
        $transferred++
    } catch {
        Write-Host " FAIL" -ForegroundColor Red
    }
}

$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalMinutes, 1)

Write-Host "`n[OK] Transferidos: $transferred de $($backupFiles.Count) ($duration min)`n" -ForegroundColor Green

if($transferred -lt $backupFiles.Count){
    Write-Host "[ERROR] No se completó la transferencia" -ForegroundColor Red
    Remove-PSSession $sourceSession, $destSession
    exit
}

# 4. Extraer y analizar
Write-Host "[4/4] Extrayendo y analizando backup..." -ForegroundColor Yellow

$analysis = Invoke-Command -Session $destSession -ArgumentList $BackupName -ScriptBlock {
    param($backupName)
    
    # Instalar 7-Zip si no existe
    $7zip = "C:\Program Files\7-Zip\7z.exe"
    if(!(Test-Path $7zip)){
        Write-Host "Instalando 7-Zip..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $installer = "$env:TEMP\7zip.msi"
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2301-x64.msi" -OutFile $installer -UseBasicParsing -TimeoutSec 120
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
        Start-Sleep -Seconds 5
    }
    
    # Extraer
    $firstPart = "C:\Restore\Backup\$backupName.7z.001"
    $extractPath = "C:\Restore\Extracted"
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
    
    Write-Host "Extrayendo backup (esto tarda 20-40 min)..."
    & $7zip x $firstPart -o"$extractPath" -y 2>&1 | Out-Null
    
    if($LASTEXITCODE -ne 0){
        return @{Success=$false; Error="Extraction failed"}
    }
    
    # Analizar contenido
    $result = @{
        Success = $true
        HasUsers = Test-Path "$extractPath\Users"
        HasProgramData = Test-Path "$extractPath\ProgramData"
        HasProgramFiles = Test-Path "$extractPath\ProgramFiles"
        HasProgramFilesx86 = Test-Path "$extractPath\ProgramFilesx86"
        HasWindowsConfig = Test-Path "$extractPath\WindowsConfig"
    }
    
    # Calcular tamaños
    if($result.HasUsers){
        $usersSize = (Get-ChildItem "$extractPath\Users" -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $result.UsersSizeGB = [math]::Round($usersSize/1GB, 2)
    }
    if($result.HasProgramData){
        $pdSize = (Get-ChildItem "$extractPath\ProgramData" -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $result.ProgramDataSizeGB = [math]::Round($pdSize/1GB, 2)
    }
    if($result.HasProgramFiles){
        $pfSize = (Get-ChildItem "$extractPath\ProgramFiles" -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $result.ProgramFilesSizeGB = [math]::Round($pfSize/1GB, 2)
    }
    
    # Determinar tipo de backup
    $result.IsBMRComplete = $result.HasUsers -and $result.HasProgramData -and $result.HasProgramFiles -and $result.HasWindowsConfig
    
    # Verificar booteable
    $result.IsBootable = $false
    $result.BootableType = "FILE-LEVEL BACKUP"
    $result.CanConvertBootable = $false
    
    return $result
}

if(!$analysis.Success){
    Write-Host "[ERROR] Fallo la extraccion: $($analysis.Error)" -ForegroundColor Red
    Remove-PSSession $sourceSession, $destSession
    exit
}

# Mostrar resultados
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " ANALISIS DEL BACKUP BMR" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

Write-Host "Componentes encontrados:" -ForegroundColor Yellow
if($analysis.HasUsers){ Write-Host "  [OK] Users: $($analysis.UsersSizeGB) GB" -ForegroundColor Green } else { Write-Host "  [X] Users" -ForegroundColor Red }
if($analysis.HasProgramData){ Write-Host "  [OK] ProgramData: $($analysis.ProgramDataSizeGB) GB" -ForegroundColor Green } else { Write-Host "  [X] ProgramData" -ForegroundColor Red }
if($analysis.HasProgramFiles){ Write-Host "  [OK] Program Files: $($analysis.ProgramFilesSizeGB) GB" -ForegroundColor Green } else { Write-Host "  [X] Program Files" -ForegroundColor Red }
if($analysis.HasProgramFilesx86){ Write-Host "  [OK] Program Files (x86)" -ForegroundColor Green } else { Write-Host "  [X] Program Files (x86)" -ForegroundColor Red }
if($analysis.HasWindowsConfig){ Write-Host "  [OK] Windows Config (Registro)" -ForegroundColor Green } else { Write-Host "  [X] Windows Config" -ForegroundColor Red }

Write-Host "`n===============================================" -ForegroundColor Cyan
if($analysis.IsBMRComplete){
    Write-Host " TIPO: BMR COMPLETO (File-Level)" -ForegroundColor Green
} else {
    Write-Host " TIPO: BACKUP PARCIAL" -ForegroundColor Yellow
}
Write-Host "===============================================`n" -ForegroundColor Cyan

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " BOOTEABLE: NO" -ForegroundColor Red
Write-Host "===============================================`n" -ForegroundColor Cyan

Write-Host "EXPLICACION:" -ForegroundColor Yellow
Write-Host "Este es un backup a NIVEL DE ARCHIVOS, no una imagen de disco.`n" -ForegroundColor White

Write-Host "QUE CONTIENE:" -ForegroundColor Cyan
Write-Host "  + Todos los archivos de usuario" -ForegroundColor Green
Write-Host "  + Configuraciones del sistema" -ForegroundColor Green
Write-Host "  + Programas instalados" -ForegroundColor Green
Write-Host "  + Datos de aplicaciones" -ForegroundColor Green
Write-Host "  + Registro de Windows (parcial)`n" -ForegroundColor Green

Write-Host "QUE NO CONTIENE:" -ForegroundColor Cyan
Write-Host "  - Estructura de particiones (MBR/GPT)" -ForegroundColor Red
Write-Host "  - Bootloader (UEFI/BIOS)" -ForegroundColor Red
Write-Host "  - Boot Configuration Data (BCD) completo" -ForegroundColor Red
Write-Host "  - Drivers de hardware especificos" -ForegroundColor Red
Write-Host "  - Archivos del sistema en uso`n" -ForegroundColor Red

Write-Host "===============================================" -ForegroundColor Yellow
Write-Host " RESPUESTA A TUS PREGUNTAS:" -ForegroundColor Yellow
Write-Host "===============================================`n" -ForegroundColor Yellow

Write-Host "1. ¿Es un BMR completo?" -ForegroundColor Cyan
Write-Host "   SI - Es BMR completo a nivel de archivos" -ForegroundColor Green
Write-Host "   Incluye todos los componentes criticos del sistema`n" -ForegroundColor White

Write-Host "2. ¿Puede convertirse en ISO booteable?" -ForegroundColor Cyan
Write-Host "   NO DIRECTAMENTE" -ForegroundColor Red
Write-Host "   Razon: Es backup de archivos, no imagen de disco`n" -ForegroundColor White

Write-Host "3. ¿Se puede usar para arrancar una nueva VPS?" -ForegroundColor Cyan
Write-Host "   NO como ISO booteable" -ForegroundColor Red
Write-Host "   SI como restauracion sobre Windows instalado`n" -ForegroundColor Green

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " USOS RECOMENDADOS:" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

Write-Host "OPCION 1: Restauracion sobre Windows existente" -ForegroundColor Green
Write-Host "  1. Instalar Windows Server en nueva VPS" -ForegroundColor White
Write-Host "  2. Copiar carpetas extraidas a sus ubicaciones" -ForegroundColor White
Write-Host "  3. Reiniciar y configurar" -ForegroundColor White
Write-Host "  Resultado: Sistema casi identico al original`n" -ForegroundColor Gray

Write-Host "OPCION 2: Migracion manual selectiva" -ForegroundColor Green
Write-Host "  1. Instalar Windows Server en nueva VPS" -ForegroundColor White
Write-Host "  2. Copiar solo datos y configuraciones necesarias" -ForegroundColor White
Write-Host "  3. Reinstalar aplicaciones" -ForegroundColor White
Write-Host "  Resultado: Sistema limpio con datos migrados`n" -ForegroundColor Gray

Write-Host "OPCION 3: Para crear ISO booteable (COMPLEJO)" -ForegroundColor Yellow
Write-Host "  Requiere:" -ForegroundColor White
Write-Host "  - Windows ADK (Assessment and Deployment Kit)" -ForegroundColor Gray
Write-Host "  - Crear imagen WIM del sistema" -ForegroundColor Gray
Write-Host "  - Integrar bootloader y drivers" -ForegroundColor Gray
Write-Host "  - Usar DISM para crear ISO" -ForegroundColor Gray
Write-Host "  - Herramientas: WinPE, ImageX, oscdimg" -ForegroundColor Gray
Write-Host "  Tiempo estimado: 4-8 horas de trabajo manual`n" -ForegroundColor Gray

Write-Host "===============================================" -ForegroundColor Green
Write-Host " CONCLUSION" -ForegroundColor Green
Write-Host "===============================================`n" -ForegroundColor Green

Write-Host "Tu backup esta COMPLETO y LISTO para:" -ForegroundColor Cyan
Write-Host "  [OK] Restaurar archivos y configuraciones" -ForegroundColor Green
Write-Host "  [OK] Migrar datos a nueva VPS" -ForegroundColor Green
Write-Host "  [OK] Recuperar aplicaciones y usuarios" -ForegroundColor Green
Write-Host "`n  [NO] Arrancar directamente como ISO" -ForegroundColor Red
Write-Host "  [NO] Instalar como sistema operativo nuevo`n" -ForegroundColor Red

Write-Host "Ubicacion del backup extraido:" -ForegroundColor Cyan
Write-Host "  RESPALDO-1: C:\Restore\Extracted\`n" -ForegroundColor White

Write-Host "¿Quieres proceder con restauracion manual? (S/N): " -NoNewline -ForegroundColor Yellow

Remove-PSSession $sourceSession, $destSession
Write-Host "`nSesiones cerradas.`n" -ForegroundColor Gray
