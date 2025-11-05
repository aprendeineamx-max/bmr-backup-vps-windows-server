<#
.SYNOPSIS
    Crea un backup BMR (Bare Metal Recovery) del sistema Windows Server.

.DESCRIPTION
    Utiliza Windows Server Backup (wbadmin) para crear una imagen completa
    del sistema que puede ser restaurada en hardware diferente.

.PARAMETER BackupPath
    Ruta donde se almacenará el backup temporal.

.PARAMETER VolumesToBackup
    Volúmenes a incluir en el backup. Por defecto: C:

.PARAMETER Compress
    Nivel de compresión (None, Fast, Maximum).

.EXAMPLE
    .\Create-BMRBackup.ps1 -BackupPath "C:\BackupTemp" -Compress Maximum

.NOTES
    Requiere privilegios de administrador y Windows Server Backup instalado.
#>

[CmdletBinding()]
param(
    [string]$BackupPath = "C:\BackupTemp",
    [string[]]$VolumesToBackup = @("C:"),
    [ValidateSet('None', 'Fast', 'Maximum')]
    [string]$Compress = "Maximum",
    [switch]$SkipVerification
)

# Importar utilidades
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "..\utils\Logger.ps1")

Initialize-Logger -LogName "bmr-backup"

Write-LogInfo "========================================"
Write-LogInfo "Iniciando Backup BMR"
Write-LogInfo "========================================"

# Verificar privilegios de administrador
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-LogError "Este script debe ejecutarse como Administrador"
    exit 1
}

# Verificar que Windows Server Backup está instalado
Write-LogInfo "Verificando Windows Server Backup..."
$wsbFeature = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction SilentlyContinue
if (-not $wsbFeature -or -not $wsbFeature.Installed) {
    Write-LogError "Windows Server Backup no está instalado"
    Write-LogError "Ejecute: Install-WindowsFeature -Name Windows-Server-Backup"
    exit 1
}
Write-LogSuccess "Windows Server Backup: OK"

# Crear directorio de backup si no existe
if (-not (Test-Path $BackupPath)) {
    Write-LogInfo "Creando directorio de backup: $BackupPath"
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
}

# Verificar espacio disponible
$drive = Get-PSDrive -Name ($BackupPath.Substring(0, 1))
$freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
$usedSpaceGB = [math]::Round($drive.Used / 1GB, 2)

Write-LogInfo "Espacio en disco:"
Write-LogInfo "  - Usado: $usedSpaceGB GB"
Write-LogInfo "  - Libre: $freeSpaceGB GB"

# Estimar tamaño del backup (aproximadamente el espacio usado con compresión)
$estimatedSizeGB = switch ($Compress) {
    'None'    { $usedSpaceGB }
    'Fast'    { $usedSpaceGB * 0.7 }
    'Maximum' { $usedSpaceGB * 0.5 }
}

Write-LogInfo "Tamaño estimado del backup: $([math]::Round($estimatedSizeGB, 2)) GB"

if ($freeSpaceGB -lt ($estimatedSizeGB + 10)) {
    Write-LogWarning "Espacio en disco puede ser insuficiente"
    Write-LogWarning "Se recomienda al menos $([math]::Round($estimatedSizeGB + 10, 2)) GB libres"
    
    $continue = Read-Host "¿Desea continuar de todos modos? (S/N)"
    if ($continue -ne 'S') {
        Write-LogInfo "Operación cancelada por el usuario"
        exit 0
    }
}

# Generar nombre de backup con timestamp
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "BMR-Backup-$env:COMPUTERNAME-$timestamp"
$backupTarget = Join-Path $BackupPath $backupName

Write-LogInfo ""
Write-LogInfo "Configuración del backup:"
Write-LogInfo "  - Nombre: $backupName"
Write-LogInfo "  - Destino: $backupTarget"
Write-LogInfo "  - Volúmenes: $($VolumesToBackup -join ', ')"
Write-LogInfo "  - Compresión: $Compress"
Write-LogInfo ""

# Iniciar el backup
Write-LogInfo "Iniciando backup BMR con wbadmin..."
Write-LogInfo "NOTA: Este proceso puede tardar de 30 a 60 minutos dependiendo del tamaño de los datos"

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    # Construir comando wbadmin
    $volumeArgs = $VolumesToBackup | ForEach-Object { "-include:$_" }
    
    # Comando para backup completo (BMR)
    $wbadminArgs = @(
        "start", "backup"
        "-backupTarget:$backupTarget"
        "-allCritical"
        "-systemState"
    ) + $volumeArgs
    
    # Agregar opciones de compresión si es necesario
    if ($Compress -eq 'None') {
        $wbadminArgs += "-noVerify"
    }
    
    $wbadminArgs += "-quiet"
    
    Write-LogInfo "Ejecutando: wbadmin $($wbadminArgs -join ' ')"
    
    # Ejecutar wbadmin
    $process = Start-Process -FilePath "wbadmin" -ArgumentList $wbadminArgs -NoNewWindow -Wait -PassThru
    
    $stopwatch.Stop()
    
    if ($process.ExitCode -eq 0) {
        $elapsed = $stopwatch.Elapsed
        Write-LogSuccess "Backup completado exitosamente"
        Write-LogInfo "Tiempo transcurrido: $($elapsed.Hours)h $($elapsed.Minutes)m $($elapsed.Seconds)s"
    }
    else {
        Write-LogError "wbadmin finalizó con código de error: $($process.ExitCode)"
        Write-LogError "Consulte los logs de Windows para más detalles"
        exit 1
    }
}
catch {
    $stopwatch.Stop()
    Write-LogError "Error ejecutando wbadmin: $_"
    Write-LogError $_.Exception.Message
    exit 1
}

# Verificar que el backup se creó
Write-LogInfo "Verificando archivos de backup..."
if (Test-Path $backupTarget) {
    $backupFiles = Get-ChildItem -Path $backupTarget -Recurse
    $totalSizeGB = [math]::Round(($backupFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    
    Write-LogSuccess "Backup creado: $backupTarget"
    Write-LogInfo "Tamaño total: $totalSizeGB GB"
    Write-LogInfo "Archivos: $($backupFiles.Count)"
    
    # Listar archivos principales
    Write-LogInfo "Archivos principales:"
    $backupFiles | Where-Object { $_.Length -gt 100MB } | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-LogInfo "  - $($_.Name) ($sizeMB MB)"
    }
}
else {
    Write-LogError "No se encontró el directorio de backup: $backupTarget"
    exit 1
}

# Crear archivo ZIP del backup para facilitar transferencia
if ($Compress -ne 'None') {
    Write-LogInfo "Comprimiendo backup en archivo ZIP..."
    
    $zipPath = "$backupTarget.zip"
    
    try {
        # Usar PowerShell para comprimir
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        $compressionLevel = switch ($Compress) {
            'Fast'    { [System.IO.Compression.CompressionLevel]::Fastest }
            'Maximum' { [System.IO.Compression.CompressionLevel]::Optimal }
            default   { [System.IO.Compression.CompressionLevel]::Optimal }
        }
        
        Write-LogInfo "Nivel de compresión: $compressionLevel"
        
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $backupTarget,
            $zipPath,
            $compressionLevel,
            $false
        )
        
        if (Test-Path $zipPath) {
            $zipSizeGB = [math]::Round((Get-Item $zipPath).Length / 1GB, 2)
            Write-LogSuccess "Archivo ZIP creado: $zipPath"
            Write-LogInfo "Tamaño del ZIP: $zipSizeGB GB"
            
            # Calcular ratio de compresión
            $compressionRatio = [math]::Round((1 - ($zipSizeGB / $totalSizeGB)) * 100, 2)
            Write-LogInfo "Ratio de compresión: $compressionRatio%"
        }
    }
    catch {
        Write-LogWarning "No se pudo crear archivo ZIP: $_"
        Write-LogWarning "El backup sin comprimir estará disponible en: $backupTarget"
    }
}

# Verificación del backup (opcional)
if (-not $SkipVerification) {
    Write-LogInfo "Verificando integridad del backup..."
    
    try {
        # Verificar con wbadmin
        $verifyArgs = @(
            "get", "status"
        )
        
        $verifyProcess = Start-Process -FilePath "wbadmin" -ArgumentList $verifyArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "verify-output.txt"
        
        if ($verifyProcess.ExitCode -eq 0) {
            Write-LogSuccess "Verificación completada"
        }
    }
    catch {
        Write-LogWarning "No se pudo verificar el backup automáticamente: $_"
    }
}

# Generar reporte de backup
$reportPath = Join-Path $BackupPath "backup-report-$timestamp.json"
$report = @{
    Hostname       = $env:COMPUTERNAME
    BackupDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    BackupName     = $backupName
    BackupPath     = $backupTarget
    ZipPath        = if (Test-Path "$backupTarget.zip") { "$backupTarget.zip" } else { $null }
    Volumes        = $VolumesToBackup
    TotalSizeGB    = $totalSizeGB
    ZipSizeGB      = if (Test-Path "$backupTarget.zip") { [math]::Round((Get-Item "$backupTarget.zip").Length / 1GB, 2) } else { 0 }
    Duration       = "$($stopwatch.Elapsed.Hours)h $($stopwatch.Elapsed.Minutes)m $($stopwatch.Elapsed.Seconds)s"
    Status         = "Success"
    OSVersion      = (Get-CimInstance Win32_OperatingSystem).Caption
    FileCount      = $backupFiles.Count
}

$report | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportPath -Encoding UTF8
Write-LogInfo "Reporte guardado en: $reportPath"

Write-LogInfo ""
Write-LogSuccess "========================================"
Write-LogSuccess "Backup BMR completado exitosamente"
Write-LogSuccess "========================================"
Write-LogInfo ""
Write-LogInfo "Próximos pasos:"
Write-LogInfo "  1. Subir el backup a Object Storage con Upload-ToObjectStorage.ps1"
Write-LogInfo "  2. Verificar que el backup se subió correctamente"
Write-LogInfo "  3. Opcionalmente, eliminar el backup local para liberar espacio"
Write-LogInfo ""
Write-LogInfo "Ubicación del backup: $backupTarget"
if (Test-Path "$backupTarget.zip") {
    Write-LogInfo "Archivo ZIP: $backupTarget.zip"
}

# Retornar información del backup
return @{
    Success    = $true
    BackupPath = $backupTarget
    ZipPath    = "$backupTarget.zip"
    SizeGB     = $totalSizeGB
    ReportPath = $reportPath
}
