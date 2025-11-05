<#
.SYNOPSIS
    Script maestro para restaurar backup BMR en VPS destino desde tu PC.

.DESCRIPTION
    Orquesta todo el proceso de restauración:
    1. Conecta a VPS destino
    2. Instala prerequisitos si es necesario
    3. Descarga backup desde Object Storage
    4. Prepara restauración BMR
    5. Guía en el proceso de restauración

.PARAMETER S3Key
    Clave (path) del backup en Object Storage.

.PARAMETER SkipPrerequisites
    Omite la instalación de prerequisitos.

.PARAMETER AutoRestore
    Intenta restaurar automáticamente (System State).

.EXAMPLE
    .\Start-BMRRestore.ps1 -S3Key "bmr-backups/BMR-Backup-Civer-One-20250104-153045.zip"

.NOTES
    Ejecuta este script desde tu PC local para gestionar la restauración remotamente.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$S3Key,
    
    [switch]$SkipPrerequisites,
    
    [switch]$AutoRestore,
    
    [switch]$ListAvailableBackups
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
$logFile = Join-Path $logPath "restore-orchestration-$timestamp.log"

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
Write-Log "   RESTAURACIÓN BMR - VPS WINDOWS SERVER 2025" "INFO"
Write-Log "═══════════════════════════════════════════════════════════" "INFO"
Write-Log "" "INFO"

# Cargar configuración
if (-not (Test-Path $configPath)) {
    Write-Log "Archivo de configuración no encontrado: $configPath" "ERROR"
    exit 1
}

Write-Log "Cargando configuración..." "INFO"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$vpsDestino = $config.vpsDestino
$objectStorage = $config.objectStorage

Write-Log "Configuración cargada:" "SUCCESS"
Write-Log "  - VPS Destino: $($vpsDestino.name) ($($vpsDestino.ip))" "INFO"
Write-Log "  - Object Storage: $($objectStorage.bucket) @ $($objectStorage.endpoint)" "INFO"
Write-Log "" "INFO"

# Listar backups disponibles si se solicita
if ($ListAvailableBackups) {
    Write-Log "Listando backups disponibles en Object Storage..." "INFO"
    
    # Aquí necesitaríamos AWS CLI configurado en el PC local
    try {
        $env:AWS_ACCESS_KEY_ID = $objectStorage.accessKey
        $env:AWS_SECRET_ACCESS_KEY = $objectStorage.secretKey
        
        $backups = & aws s3 ls "s3://$($objectStorage.bucket)/bmr-backups/" --endpoint-url "https://$($objectStorage.endpoint)"
        
        Write-Log "" "INFO"
        Write-Log "Backups disponibles:" "SUCCESS"
        Write-Log $backups "INFO"
        Write-Log "" "INFO"
        
        exit 0
    }
    catch {
        Write-Log "Error listando backups: $_" "ERROR"
        Write-Log "Instale AWS CLI para listar backups automáticamente" "WARNING"
        exit 1
    }
}

# Verificar que se proporcionó S3Key
if (-not $S3Key) {
    Write-Log "Debe proporcionar -S3Key con la ruta del backup" "ERROR"
    Write-Log "Use -ListAvailableBackups para ver backups disponibles" "INFO"
    exit 1
}

# Probar conectividad con VPS destino
Write-Log "Probando conectividad a VPS destino..." "INFO"

try {
    $securePassword = ConvertTo-SecureString $vpsDestino.password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vpsDestino.username, $securePassword)
    
    $testConnection = Test-NetConnection -ComputerName $vpsDestino.ip -Port 3389 -WarningAction SilentlyContinue
    
    if ($testConnection.TcpTestSucceeded) {
        Write-Log "Conectividad RDP: OK" "SUCCESS"
    }
    
    Write-Log "Estableciendo conexión WinRM..." "INFO"
    $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
    $session = New-PSSession -ComputerName $vpsDestino.ip -Credential $credential -SessionOption $sessionOption -ErrorAction Stop
    
    Write-Log "Conexión WinRM establecida" "SUCCESS"
    
    $remoteInfo = Invoke-Command -Session $session -ScriptBlock {
        @{
            Hostname  = $env:COMPUTERNAME
            OS        = (Get-CimInstance Win32_OperatingSystem).Caption
            FreeSpace = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
            UsedSpace = [math]::Round((Get-PSDrive C).Used / 1GB, 2)
        }
    }
    
    Write-Log "Información de VPS Destino:" "INFO"
    Write-Log "  - Hostname: $($remoteInfo.Hostname)" "INFO"
    Write-Log "  - OS: $($remoteInfo.OS)" "INFO"
    Write-Log "  - Disco C: usado $($remoteInfo.UsedSpace) GB, libre $($remoteInfo.FreeSpace) GB" "INFO"
    Write-Log "" "INFO"
}
catch {
    Write-Log "Error conectando a VPS destino: $_" "ERROR"
    exit 1
}

# Instalar prerequisitos
if (-not $SkipPrerequisites) {
    Write-Log "Verificando e instalando prerequisitos..." "INFO"
    
    try {
        $remoteTempPath = "C:\BMR-Backup-System"
        
        Write-Log "Copiando scripts a VPS destino..." "INFO"
        Invoke-Command -Session $session -ScriptBlock {
            param($path)
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
        } -ArgumentList $remoteTempPath
        
        $localScriptsPath = Join-Path $scriptRoot "scripts"
        
        Copy-Item -Path (Join-Path $localScriptsPath "utils\*") -Destination "$remoteTempPath\utils\" -ToSession $session -Recurse -Force
        Copy-Item -Path (Join-Path $localScriptsPath "remote\*") -Destination "$remoteTempPath\" -ToSession $session -Force
        Copy-Item -Path $configPath -Destination "$remoteTempPath\credentials.json" -ToSession $session -Force
        
        Write-Log "Scripts copiados exitosamente" "SUCCESS"
        
        Write-Log "Instalando prerequisitos en VPS destino..." "INFO"
        
        $prereqResult = Invoke-Command -Session $session -ScriptBlock {
            Set-Location C:\BMR-Backup-System
            & .\Install-Prerequisites.ps1 -Target Destino
            return $LASTEXITCODE
        }
        
        if ($prereqResult -eq 0) {
            Write-Log "Prerequisitos instalados correctamente" "SUCCESS"
        }
    }
    catch {
        Write-Log "Error instalando prerequisitos: $_" "ERROR"
    }
}

Write-Log "" "INFO"
Write-Log "Descargando backup desde Object Storage..." "INFO"
Write-Log "NOTA: Este proceso puede tardar 20-40 minutos" "WARNING"
Write-Log "" "INFO"

# Descargar backup
try {
    $downloadResult = Invoke-Command -Session $session -ScriptBlock {
        param($s3key)
        Set-Location C:\BMR-Backup-System
        
        $result = & .\Download-FromObjectStorage.ps1 `
            -S3Key $s3key `
            -DestinationPath "C:\BackupTemp" `
            -ConfigPath ".\credentials.json" `
            -VerifyChecksum `
            -AutoExtract
        
        return $result
    } -ArgumentList $S3Key
    
    if ($downloadResult.Success) {
        Write-Log "Backup descargado exitosamente" "SUCCESS"
        Write-Log "  - Ubicación: $($downloadResult.DownloadPath)" "INFO"
        Write-Log "  - Tamaño: $($downloadResult.SizeGB) GB" "INFO"
        
        if ($downloadResult.ExtractPath) {
            Write-Log "  - Extraído en: $($downloadResult.ExtractPath)" "INFO"
        }
    }
    else {
        Write-Log "Error descargando backup" "ERROR"
        Remove-PSSession $session
        exit 1
    }
}
catch {
    Write-Log "Error durante la descarga: $_" "ERROR"
    Remove-PSSession $session
    exit 1
}

Write-Log "" "INFO"
Write-Log "═══════════════════════════════════════════════════════════" "WARNING"
Write-Log "   PREPARACIÓN PARA RESTAURACIÓN" "WARNING"
Write-Log "═══════════════════════════════════════════════════════════" "WARNING"
Write-Log "" "INFO"

if ($AutoRestore) {
    Write-Log "Iniciando restauración automática..." "WARNING"
    Write-Log "" "INFO"
    
    try {
        $restorePath = if ($downloadResult.ExtractPath) { $downloadResult.ExtractPath } else { $downloadResult.DownloadPath }
        
        Invoke-Command -Session $session -ScriptBlock {
            param($backupPath)
            Set-Location C:\BMR-Backup-System
            & .\Restore-BMRBackup.ps1 -BackupPath $backupPath -Force
        } -ArgumentList $restorePath
        
        Write-Log "Restauración completada" "SUCCESS"
        Write-Log "La VPS se reiniciará para aplicar los cambios" "WARNING"
    }
    catch {
        Write-Log "Error durante la restauración: $_" "ERROR"
    }
}
else {
    Write-Log "El backup está listo para restaurarse en la VPS destino" "SUCCESS"
    Write-Log "" "INFO"
    Write-Log "╔═══════════════════════════════════════════════════════════╗" "WARNING"
    Write-Log "║            INSTRUCCIONES DE RESTAURACIÓN                  ║" "WARNING"
    Write-Log "╠═══════════════════════════════════════════════════════════╣" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  Para RESTAURACIÓN BMR COMPLETA (Recomendado):           ║" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  1. Conecte por RDP a la VPS destino:                    ║" "WARNING"
    Write-Log "║     IP: $($vpsDestino.ip)" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  2. Abra PowerShell como Administrador                   ║" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  3. Ejecute:                                              ║" "WARNING"
    Write-Log "║     cd C:\BMR-Backup-System                               ║" "WARNING"
    Write-Log "║     .\Restore-BMRBackup.ps1                               ║" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  4. Siga las instrucciones en pantalla                   ║" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "║  NOTA: La restauración completa requiere reiniciar       ║" "WARNING"
    Write-Log "║        en Windows Recovery Environment (WinRE)           ║" "WARNING"
    Write-Log "║                                                           ║" "WARNING"
    Write-Log "╚═══════════════════════════════════════════════════════════╝" "WARNING"
    Write-Log "" "INFO"
    
    Write-Log "Alternativa - Restauración rápida desde aquí:" "INFO"
    Write-Log "  .\Start-BMRRestore.ps1 -S3Key '$S3Key' -AutoRestore" "INFO"
    Write-Log "" "INFO"
}

Remove-PSSession $session

Write-Log "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-Log "   PREPARACIÓN COMPLETADA" "SUCCESS"
Write-Log "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-Log "" "INFO"
Write-Log "Log completo guardado en: $logFile" "INFO"
