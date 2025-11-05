<#
.SYNOPSIS
    Script maestro para ejecutar backup BMR completo desde tu PC.

.DESCRIPTION
    Orquesta todo el proceso de backup:
    1. Conecta a VPS origen
    2. Instala prerequisitos si es necesario
    3. Crea backup BMR
    4. Sube a Object Storage
    5. Verifica y genera reporte

.PARAMETER SkipPrerequisites
    Omite la instalación de prerequisitos.

.PARAMETER CompressLevel
    Nivel de compresión (None, Fast, Maximum).

.PARAMETER DeleteLocalBackup
    Elimina el backup local después de subirlo a Object Storage.

.EXAMPLE
    .\Start-BMRBackup.ps1

.EXAMPLE
    .\Start-BMRBackup.ps1 -CompressLevel Maximum -DeleteLocalBackup

.NOTES
    Ejecuta este script desde tu PC local para gestionar el backup remotamente.
#>

[CmdletBinding()]
param(
    [switch]$SkipPrerequisites,
    
    [ValidateSet('None', 'Fast', 'Maximum')]
    [string]$CompressLevel = 'Maximum',
    
    [switch]$DeleteLocalBackup,
    
    [switch]$TestConnection
)

# Configuración
$scriptRoot = $PSScriptRoot
$configPath = Join-Path $scriptRoot "config\credentials.json"
$logPath = Join-Path $scriptRoot "logs"

# Crear directorio de logs
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

# Iniciar logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logPath "backup-orchestration-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $logMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
    
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Log "═══════════════════════════════════════════════════════════" "INFO"
Write-Log "   SISTEMA DE BACKUP BMR - VPS WINDOWS SERVER 2025" "INFO"
Write-Log "═══════════════════════════════════════════════════════════" "INFO"
Write-Log "" "INFO"

# Cargar configuración
if (-not (Test-Path $configPath)) {
    Write-Log "Archivo de configuración no encontrado: $configPath" "ERROR"
    Write-Log "Copie credentials.example.json a credentials.json y configure sus credenciales" "ERROR"
    exit 1
}

Write-Log "Cargando configuración..." "INFO"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$vpsOrigen = $config.vpsOrigen
$objectStorage = $config.objectStorage

Write-Log "Configuración cargada:" "SUCCESS"
Write-Log "  - VPS Origen: $($vpsOrigen.name) ($($vpsOrigen.ip))" "INFO"
Write-Log "  - Object Storage: $($objectStorage.bucket) @ $($objectStorage.endpoint)" "INFO"
Write-Log "" "INFO"

# Probar conectividad
Write-Log "Probando conectividad a VPS origen..." "INFO"

try {
    # Convertir password a SecureString
    $securePassword = ConvertTo-SecureString $vpsOrigen.password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vpsOrigen.username, $securePassword)
    
    # Probar conexión básica
    $rdpTest = Test-NetConnection -ComputerName $vpsOrigen.ip -Port 3389 -WarningAction SilentlyContinue
    
    if ($rdpTest.TcpTestSucceeded) {
        Write-Log "Conectividad RDP: OK" "SUCCESS"
    }
    else {
        Write-Log "No se pudo conectar por RDP (puerto 3389)" "WARNING"
    }
    
    # Probar WinRM
    Write-Log "Probando WinRM..." "INFO"
    
    $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
    $session = New-PSSession -ComputerName $vpsOrigen.ip -Credential $credential -SessionOption $sessionOption -ErrorAction Stop
    
    Write-Log "Conexión WinRM establecida" "SUCCESS"
    
    # Obtener información del sistema remoto
    $remoteInfo = Invoke-Command -Session $session -ScriptBlock {
        @{
            Hostname  = $env:COMPUTERNAME
            OS        = (Get-CimInstance Win32_OperatingSystem).Caption
            FreeSpace = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
            UsedSpace = [math]::Round((Get-PSDrive C).Used / 1GB, 2)
        }
    }
    
    Write-Log "Información de VPS Origen:" "INFO"
    Write-Log "  - Hostname: $($remoteInfo.Hostname)" "INFO"
    Write-Log "  - OS: $($remoteInfo.OS)" "INFO"
    Write-Log "  - Espacio libre C:: $($remoteInfo.FreeSpace) GB" "INFO"
    Write-Log "" "INFO"
}
catch {
    Write-Log "Error conectando a VPS origen: $_" "ERROR"
    Write-Log "Verifique que:" "WARNING"
    Write-Log "  1. Las credenciales en config\credentials.json son correctas" "WARNING"
    Write-Log "  2. WinRM está habilitado en la VPS" "WARNING"
    Write-Log "  3. El firewall permite conexiones WinRM" "WARNING"
    Write-Log "" "WARNING"
    Write-Log "Para habilitar WinRM en la VPS, ejecute:" "WARNING"
    Write-Log "  Enable-PSRemoting -Force" "WARNING"
    Write-Log "  Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force" "WARNING"
    exit 1
}

# Instalar prerequisitos si es necesario
if (-not $SkipPrerequisites) {
    Write-Log "Verificando e instalando prerequisitos..." "INFO"
    
    try {
        # Copiar scripts a VPS
        $remoteTempPath = "C:\BMR-Backup-System"
        
        Write-Log "Copiando scripts a VPS..." "INFO"
        Invoke-Command -Session $session -ScriptBlock {
            param($path)
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
        } -ArgumentList $remoteTempPath
        
        # Copiar archivos necesarios
        $localScriptsPath = Join-Path $scriptRoot "scripts"
        
        # Copiar utils
        Copy-Item -Path (Join-Path $localScriptsPath "utils\*") -Destination "$remoteTempPath\utils\" -ToSession $session -Recurse -Force
        
        # Copiar scripts remotos
        Copy-Item -Path (Join-Path $localScriptsPath "remote\*") -Destination "$remoteTempPath\" -ToSession $session -Force
        
        # Copiar configuración
        Copy-Item -Path $configPath -Destination "$remoteTempPath\credentials.json" -ToSession $session -Force
        
        Write-Log "Scripts copiados exitosamente" "SUCCESS"
        
        # Ejecutar instalación de prerequisitos
        Write-Log "Instalando prerequisitos en VPS origen..." "INFO"
        
        $prereqResult = Invoke-Command -Session $session -ScriptBlock {
            Set-Location C:\BMR-Backup-System
            & .\Install-Prerequisites.ps1 -Target Origen
            return $LASTEXITCODE
        }
        
        if ($prereqResult -eq 0) {
            Write-Log "Prerequisitos instalados correctamente" "SUCCESS"
        }
        else {
            Write-Log "Advertencia: Algunos prerequisitos pueden no haberse instalado correctamente" "WARNING"
        }
    }
    catch {
        Write-Log "Error instalando prerequisitos: $_" "ERROR"
        Write-Log "Continuando de todos modos..." "WARNING"
    }
}

Write-Log "" "INFO"
Write-Log "Iniciando proceso de backup BMR..." "INFO"
Write-Log "" "INFO"

# Ejecutar backup
try {
    Write-Log "Creando backup BMR en VPS origen..." "INFO"
    Write-Log "NOTA: Este proceso puede tardar 30-60 minutos" "WARNING"
    Write-Log "" "INFO"
    
    $backupResult = Invoke-Command -Session $session -ScriptBlock {
        param($compress)
        Set-Location C:\BMR-Backup-System
        $result = & .\Create-BMRBackup.ps1 -BackupPath "C:\BackupTemp" -Compress $compress
        return $result
    } -ArgumentList $CompressLevel
    
    if ($backupResult.Success) {
        Write-Log "Backup BMR creado exitosamente" "SUCCESS"
        Write-Log "  - Ubicación: $($backupResult.BackupPath)" "INFO"
        Write-Log "  - Tamaño: $($backupResult.SizeGB) GB" "INFO"
        
        if ($backupResult.ZipPath) {
            Write-Log "  - Archivo ZIP: $($backupResult.ZipPath)" "INFO"
        }
    }
    else {
        Write-Log "Error creando backup BMR" "ERROR"
        Remove-PSSession $session
        exit 1
    }
}
catch {
    Write-Log "Error durante el backup: $_" "ERROR"
    Remove-PSSession $session
    exit 1
}

Write-Log "" "INFO"
Write-Log "Subiendo backup a Object Storage..." "INFO"
Write-Log "NOTA: Este proceso puede tardar 20-40 minutos" "WARNING"
Write-Log "" "INFO"

# Subir a Object Storage
try {
    $uploadResult = Invoke-Command -Session $session -ScriptBlock {
        param($backupZip, $deleteLocal)
        Set-Location C:\BMR-Backup-System
        
        $params = @{
            BackupPath = $backupZip
            ConfigPath = ".\credentials.json"
        }
        
        if ($deleteLocal) {
            $params.DeleteAfterUpload = $true
        }
        
        $result = & .\Upload-ToObjectStorage.ps1 @params
        return $result
    } -ArgumentList $backupResult.ZipPath, $DeleteLocalBackup
    
    if ($uploadResult.Success) {
        Write-Log "Backup subido exitosamente a Object Storage" "SUCCESS"
        Write-Log "  - Bucket: $($uploadResult.S3Bucket)" "INFO"
        Write-Log "  - Key: $($uploadResult.S3Key)" "INFO"
        Write-Log "  - Tamaño: $($uploadResult.SizeGB) GB" "INFO"
        Write-Log "  - MD5: $($uploadResult.MD5)" "INFO"
    }
    else {
        Write-Log "Error subiendo backup a Object Storage" "ERROR"
        Write-Log "El backup local está disponible en la VPS origen" "WARNING"
        Remove-PSSession $session
        exit 1
    }
}
catch {
    Write-Log "Error durante el upload: $_" "ERROR"
    Remove-PSSession $session
    exit 1
}

# Limpiar sesión
Remove-PSSession $session

Write-Log "" "INFO"
Write-Log "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-Log "   BACKUP BMR COMPLETADO EXITOSAMENTE" "SUCCESS"
Write-Log "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-Log "" "INFO"
Write-Log "Resumen del backup:" "INFO"
Write-Log "  - Origen: $($vpsOrigen.name) ($($vpsOrigen.ip))" "INFO"
Write-Log "  - Tamaño: $($uploadResult.SizeGB) GB" "INFO"
Write-Log "  - Almacenamiento: Object Storage" "INFO"
Write-Log "  - Bucket: $($uploadResult.S3Bucket)" "INFO"
Write-Log "  - Key: $($uploadResult.S3Key)" "INFO"
Write-Log "  - Checksum MD5: $($uploadResult.MD5)" "INFO"
Write-Log "" "INFO"
Write-Log "Para restaurar este backup en otra VPS, ejecute:" "INFO"
Write-Log "  .\Start-BMRRestore.ps1 -S3Key '$($uploadResult.S3Key)'" "INFO"
Write-Log "" "INFO"
Write-Log "Log completo guardado en: $logFile" "INFO"
