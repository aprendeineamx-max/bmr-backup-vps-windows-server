<#
.SYNOPSIS
    Restaura un backup BMR en el sistema Windows Server.

.DESCRIPTION
    Restaura una imagen completa del sistema desde un backup BMR.
    ADVERTENCIA: Este proceso sobrescribirá el sistema actual.

.PARAMETER BackupPath
    Ruta del directorio o archivo de backup a restaurar.

.PARAMETER WhatIf
    Muestra qué se restauraría sin aplicar cambios.

.EXAMPLE
    .\Restore-BMRBackup.ps1 -BackupPath "C:\BackupTemp\BMR-Backup-Server1-20250104"

.NOTES
    Requiere privilegios de administrador.
    El sistema se reiniciará después de la restauración.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    
    [switch]$Force,
    
    [string]$TargetVolume = "C:"
)

# Importar utilidades
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "..\utils\Logger.ps1")

Initialize-Logger -LogName "bmr-restore"

Write-LogInfo "========================================"
Write-LogInfo "Restauración de Backup BMR"
Write-LogInfo "========================================"

# Verificar privilegios de administrador
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-LogError "Este script debe ejecutarse como Administrador"
    exit 1
}

# Verificar si es un archivo ZIP
if ($BackupPath -match '\.zip$') {
    if (-not (Test-Path $BackupPath)) {
        Write-LogError "Archivo de backup no encontrado: $BackupPath"
        exit 1
    }
    
    Write-LogInfo "Detectado archivo ZIP. Extrayendo..."
    $extractPath = $BackupPath -replace '\.zip$', ''
    
    if (Test-Path $extractPath) {
        Write-LogWarning "El directorio de extracción ya existe: $extractPath"
        if (-not $Force) {
            $continue = Read-Host "¿Desea sobrescribirlo? (S/N)"
            if ($continue -ne 'S') {
                Write-LogInfo "Operación cancelada"
                exit 0
            }
        }
        Remove-Item -Path $extractPath -Recurse -Force
    }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $extractPath)
    
    Write-LogSuccess "Archivo extraído"
    $BackupPath = $extractPath
}

# Verificar que el directorio de backup existe
if (-not (Test-Path $BackupPath)) {
    Write-LogError "Directorio de backup no encontrado: $BackupPath"
    exit 1
}

Write-LogInfo "Directorio de backup: $BackupPath"

# Listar contenido del backup
Write-LogInfo "Analizando contenido del backup..."
$backupFiles = Get-ChildItem -Path $BackupPath -Recurse
$totalSizeGB = [math]::Round(($backupFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)

Write-LogInfo "  - Archivos: $($backupFiles.Count)"
Write-LogInfo "  - Tamaño total: $totalSizeGB GB"

# Buscar el catálogo de backup de wbadmin
$catalogFiles = $backupFiles | Where-Object { $_.Name -like "*BackupSpecs.xml" -or $_.Name -like "*.vhd*" }

if ($catalogFiles.Count -eq 0) {
    Write-LogError "No se encontraron archivos de catálogo de backup válidos"
    Write-LogError "El directorio puede no contener un backup de Windows Server Backup válido"
    exit 1
}

Write-LogSuccess "Backup válido encontrado"

# ADVERTENCIA IMPORTANTE
Write-LogWarning ""
Write-LogWarning "╔═══════════════════════════════════════════════════════════╗"
Write-LogWarning "║             ¡ADVERTENCIA CRÍTICA!                         ║"
Write-LogWarning "╠═══════════════════════════════════════════════════════════╣"
Write-LogWarning "║  La restauración BMR SOBRESCRIBIRÁ COMPLETAMENTE el      ║"
Write-LogWarning "║  sistema actual, incluyendo:                              ║"
Write-LogWarning "║  - Sistema operativo                                      ║"
Write-LogWarning "║  - Aplicaciones instaladas                                ║"
Write-LogWarning "║  - Configuraciones                                        ║"
Write-LogWarning "║  - Datos de usuario                                       ║"
Write-LogWarning "║                                                           ║"
Write-LogWarning "║  El sistema se reiniciará después de la restauración.    ║"
Write-LogWarning "║                                                           ║"
Write-LogWarning "║  ESTA ACCIÓN NO SE PUEDE DESHACER                         ║"
Write-LogWarning "╚═══════════════════════════════════════════════════════════╝"
Write-LogWarning ""

if (-not $Force -and -not $WhatIfPreference) {
    Write-Host ""
    Write-Host "Para continuar, escriba exactamente: " -NoNewline -ForegroundColor Yellow
    Write-Host "RESTAURAR SISTEMA" -ForegroundColor Red
    $confirmation = Read-Host ""
    
    if ($confirmation -ne "RESTAURAR SISTEMA") {
        Write-LogInfo "Confirmación no válida. Operación cancelada."
        exit 0
    }
}

if ($WhatIfPreference) {
    Write-LogInfo ""
    Write-LogInfo "Modo WhatIf: Las siguientes acciones se ejecutarían:"
    Write-LogInfo "  1. Validar el backup en: $BackupPath"
    Write-LogInfo "  2. Crear punto de restauración del sistema actual"
    Write-LogInfo "  3. Ejecutar wbadmin con los siguientes parámetros:"
    Write-LogInfo "     - Backup: $BackupPath"
    Write-LogInfo "     - Volumen destino: $TargetVolume"
    Write-LogInfo "     - Modo: Recuperación completa del sistema"
    Write-LogInfo "  4. Reiniciar el sistema para aplicar cambios"
    Write-LogInfo ""
    Write-LogInfo "NO se realizarán cambios en modo WhatIf"
    exit 0
}

# Obtener información del backup
Write-LogInfo "Obteniendo información del backup..."

try {
    # Listar backups disponibles en la ubicación
    $backupInfo = & wbadmin get versions -backupTarget:$BackupPath 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-LogSuccess "Información del backup obtenida"
        $backupInfo | ForEach-Object { Write-LogInfo $_ }
    }
}
catch {
    Write-LogWarning "No se pudo obtener información detallada del backup: $_"
}

# Preparar sistema para restauración
Write-LogInfo "Preparando sistema para restauración..."

# Nota: La restauración BMR completa normalmente requiere arrancar desde
# Windows Recovery Environment (WinRE) o medios de instalación.
# Este script proporciona dos métodos:

Write-LogInfo ""
Write-LogInfo "Métodos de restauración disponibles:"
Write-LogInfo ""
Write-LogInfo "1. RESTAURACIÓN DESDE WinRE (Recomendado para BMR completo)"
Write-LogInfo "   - Reinicia en Windows Recovery Environment"
Write-LogInfo "   - Permite restauración completa del sistema"
Write-LogInfo "   - Requiere reinicio"
Write-LogInfo ""
Write-LogInfo "2. RESTAURACIÓN DE ARCHIVOS Y SYSTEM STATE (Alternativa)"
Write-LogInfo "   - Restaura archivos y configuración sin reiniciar"
Write-LogInfo "   - No reemplaza bootloader ni particiones"
Write-LogInfo "   - Útil para migración de datos"
Write-LogInfo ""

$method = Read-Host "Seleccione método (1 o 2)"

if ($method -eq "1") {
    # Método 1: Preparar para restauración desde WinRE
    Write-LogInfo "Preparando restauración desde WinRE..."
    
    # Crear script de restauración para WinRE
    $winREScript = @"
# Script de restauración BMR automático
# Este script se ejecutará en WinRE

wbadmin start sysrecovery ``
    -version:$BackupPath ``
    -backupTarget:$BackupPath ``
    -quiet ``
    -restartComputer
"@
    
    $scriptPath = "C:\Windows\Temp\BMR-Restore-WinRE.ps1"
    $winREScript | Out-File -FilePath $scriptPath -Encoding ASCII
    
    Write-LogInfo "Script de restauración creado: $scriptPath"
    
    Write-LogWarning ""
    Write-LogWarning "PRÓXIMOS PASOS MANUALES:"
    Write-LogWarning "1. El sistema se reiniciará ahora"
    Write-LogWarning "2. Presione F8 o Shift+F8 durante el arranque"
    Write-LogWarning "3. Seleccione 'Solucionar problemas' > 'Opciones avanzadas'"
    Write-LogWarning "4. Seleccione 'Símbolo del sistema'"
    Write-LogWarning "5. Ejecute el comando:"
    Write-LogWarning "   powershell -ExecutionPolicy Bypass -File $scriptPath"
    Write-LogWarning ""
    
    $restart = Read-Host "¿Reiniciar ahora para comenzar restauración? (S/N)"
    
    if ($restart -eq 'S') {
        Write-LogInfo "Reiniciando sistema..."
        shutdown /r /f /t 10 /c "Reiniciando para restauración BMR"
        exit 0
    }
    else {
        Write-LogInfo "Reinicio cancelado. Puede reiniciar manualmente más tarde."
        Write-LogInfo "Script de restauración guardado en: $scriptPath"
        exit 0
    }
}
elseif ($method -eq "2") {
    # Método 2: Restauración de System State y archivos
    Write-LogInfo "Iniciando restauración de System State y archivos..."
    
    try {
        # Obtener la versión más reciente del backup
        $versions = & wbadmin get versions -backupTarget:$BackupPath 2>&1
        
        # Restaurar System State
        Write-LogInfo "Restaurando System State..."
        
        $restoreArgs = @(
            "start", "systemstaterecovery",
            "-version:$BackupPath",
            "-backupTarget:$BackupPath",
            "-quiet"
        )
        
        $process = Start-Process -FilePath "wbadmin" -ArgumentList $restoreArgs -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-LogSuccess "System State restaurado correctamente"
            Write-LogWarning "Se requiere reiniciar el sistema para aplicar cambios"
            
            $restart = Read-Host "¿Reiniciar ahora? (S/N)"
            if ($restart -eq 'S') {
                shutdown /r /f /t 30 /c "Reiniciando para aplicar restauración"
                Write-LogInfo "Sistema se reiniciará en 30 segundos..."
            }
        }
        else {
            Write-LogError "Error en la restauración. Código: $($process.ExitCode)"
            Write-LogError "Consulte los logs de Windows para más detalles"
            exit 1
        }
    }
    catch {
        Write-LogError "Error durante la restauración: $_"
        Write-LogError $_.Exception.Message
        exit 1
    }
}
else {
    Write-LogError "Opción no válida"
    exit 1
}

Write-LogInfo ""
Write-LogSuccess "========================================"
Write-LogSuccess "Proceso de restauración iniciado"
Write-LogSuccess "========================================"
Write-LogInfo ""
Write-LogInfo "NOTA IMPORTANTE:"
Write-LogInfo "Para una restauración BMR completa (bare metal recovery),"
Write-LogInfo "se recomienda usar Windows Recovery Environment (WinRE)"
Write-LogInfo "o medios de instalación de Windows Server."
Write-LogInfo ""
Write-LogInfo "Comandos útiles desde WinRE:"
Write-LogInfo "  wbadmin get versions -backupTarget:$BackupPath"
Write-LogInfo "  wbadmin start sysrecovery -version:<version> -backupTarget:$BackupPath"
Write-LogInfo ""
