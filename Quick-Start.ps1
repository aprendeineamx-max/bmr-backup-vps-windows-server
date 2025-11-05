<#
.SYNOPSIS
    Script de inicio rápido para el sistema de backup BMR.

.DESCRIPTION
    Guía interactiva para configurar y ejecutar el primer backup.

.EXAMPLE
    .\Quick-Start.ps1
#>

[CmdletBinding()]
param()

Clear-Host

$logo = @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ██████╗ ███╗   ███╗██████╗     ██████╗  █████╗  ██████╗██╗ ║
║   ██╔══██╗████╗ ████║██╔══██╗    ██╔══██╗██╔══██╗██╔════╝██║ ║
║   ██████╔╝██╔████╔██║██████╔╝    ██████╔╝███████║██║     ██║ ║
║   ██╔══██╗██║╚██╔╝██║██╔══██╗    ██╔══██╗██╔══██║██║     ██║ ║
║   ██████╔╝██║ ╚═╝ ██║██║  ██║    ██████╔╝██║  ██║╚██████╗██║ ║
║   ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝ ║
║                                                               ║
║          Sistema de Backup BMR para Windows Server           ║
║                     Vultr VPS Edition                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"@

Write-Host $logo -ForegroundColor Cyan
Write-Host ""

Write-Host "¡Bienvenido al Sistema de Backup BMR!" -ForegroundColor Green
Write-Host ""
Write-Host "Este asistente te guiará paso a paso para:" -ForegroundColor White
Write-Host "  1. Verificar la configuración" -ForegroundColor Gray
Write-Host "  2. Probar las conexiones" -ForegroundColor Gray
Write-Host "  3. Ejecutar tu primer backup" -ForegroundColor Gray
Write-Host ""

# Paso 1: Verificar configuración
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " PASO 1: Verificar Configuración" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$configPath = Join-Path $PSScriptRoot "config\credentials.json"

if (Test-Path $configPath) {
    Write-Host "✓ Archivo de configuración encontrado" -ForegroundColor Green
    
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "Configuración actual:" -ForegroundColor White
    Write-Host "  VPS Origen:" -ForegroundColor Yellow
    Write-Host "    - Nombre: $($config.vpsOrigen.name)" -ForegroundColor Gray
    Write-Host "    - IP: $($config.vpsOrigen.ip)" -ForegroundColor Gray
    Write-Host "    - Usuario: $($config.vpsOrigen.username)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  VPS Destino:" -ForegroundColor Yellow
    Write-Host "    - Nombre: $($config.vpsDestino.name)" -ForegroundColor Gray
    Write-Host "    - IP: $($config.vpsDestino.ip)" -ForegroundColor Gray
    Write-Host "    - Usuario: $($config.vpsDestino.username)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Object Storage:" -ForegroundColor Yellow
    Write-Host "    - Endpoint: $($config.objectStorage.endpoint)" -ForegroundColor Gray
    Write-Host "    - Bucket: $($config.objectStorage.bucket)" -ForegroundColor Gray
    Write-Host ""
    
    $confirmConfig = Read-Host "¿La configuración es correcta? (S/N)"
    
    if ($confirmConfig -ne 'S') {
        Write-Host ""
        Write-Host "Por favor, edita el archivo: $configPath" -ForegroundColor Yellow
        Write-Host "Luego ejecuta este script nuevamente." -ForegroundColor Yellow
        exit 0
    }
}
else {
    Write-Host "✗ Archivo de configuración no encontrado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Copiando plantilla de configuración..." -ForegroundColor Yellow
    
    $examplePath = Join-Path $PSScriptRoot "config\credentials.example.json"
    Copy-Item $examplePath $configPath
    
    Write-Host "✓ Plantilla copiada a: $configPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Por favor:" -ForegroundColor Yellow
    Write-Host "  1. Abre el archivo: $configPath" -ForegroundColor White
    Write-Host "  2. Configura tus credenciales" -ForegroundColor White
    Write-Host "  3. Ejecuta este script nuevamente" -ForegroundColor White
    exit 0
}

# Paso 2: Probar conexiones
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " PASO 2: Probar Conexiones" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$testConnection = Read-Host "¿Deseas probar la conexión a las VPS? (S/N) [Recomendado]"

if ($testConnection -eq 'S') {
    Write-Host ""
    Write-Host "Probando conexión a VPS Origen..." -ForegroundColor Yellow
    Write-Host ""
    
    & (Join-Path $PSScriptRoot "scripts\local\Test-RemoteConnection.ps1") -Target Origen
    
    Write-Host ""
    $testDestino = Read-Host "¿Probar también conexión a VPS Destino? (S/N)"
    
    if ($testDestino -eq 'S') {
        Write-Host ""
        Write-Host "Probando conexión a VPS Destino..." -ForegroundColor Yellow
        Write-Host ""
        
        & (Join-Path $PSScriptRoot "scripts\local\Test-RemoteConnection.ps1") -Target Destino
    }
    
    Write-Host ""
    $continueAfterTest = Read-Host "¿Las conexiones funcionaron correctamente? (S/N)"
    
    if ($continueAfterTest -ne 'S') {
        Write-Host ""
        Write-Host "Por favor, revisa la guía de troubleshooting:" -ForegroundColor Yellow
        Write-Host "  docs\troubleshooting.md" -ForegroundColor White
        exit 0
    }
}

# Paso 3: Ejecutar backup
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " PASO 3: Ejecutar Backup" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Estás a punto de crear un backup BMR completo de:" -ForegroundColor White
Write-Host "  $($config.vpsOrigen.name) ($($config.vpsOrigen.ip))" -ForegroundColor Yellow
Write-Host ""
Write-Host "El backup se almacenará en:" -ForegroundColor White
Write-Host "  Object Storage: $($config.objectStorage.bucket)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Tiempo estimado: 2-4 horas" -ForegroundColor Gray
Write-Host ""

Write-Host "⚠️  NOTAS IMPORTANTES:" -ForegroundColor Yellow
Write-Host "  • El proceso tomará entre 2-4 horas" -ForegroundColor White
Write-Host "  • No cierres esta ventana durante el proceso" -ForegroundColor White
Write-Host "  • La VPS origen seguirá funcionando normalmente" -ForegroundColor White
Write-Host "  • Se consumirá ancho de banda para subir a Object Storage" -ForegroundColor White
Write-Host ""

$executeBackup = Read-Host "¿Deseas iniciar el backup ahora? (S/N)"

if ($executeBackup -eq 'S') {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host " Iniciando Backup BMR..." -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    # Opciones de backup
    Write-Host "Opciones de backup:" -ForegroundColor Yellow
    Write-Host "  1. Backup estándar (compresión máxima, conservar backup local)" -ForegroundColor White
    Write-Host "  2. Backup optimizado (compresión rápida, eliminar backup local)" -ForegroundColor White
    Write-Host "  3. Backup personalizado" -ForegroundColor White
    Write-Host ""
    
    $backupOption = Read-Host "Selecciona una opción (1-3)"
    
    $params = @{}
    
    switch ($backupOption) {
        "1" {
            $params.CompressLevel = "Maximum"
            Write-Host ""
            Write-Host "Configuración: Compresión máxima, conservar backup local" -ForegroundColor Cyan
        }
        "2" {
            $params.CompressLevel = "Fast"
            $params.DeleteLocalBackup = $true
            Write-Host ""
            Write-Host "Configuración: Compresión rápida, eliminar backup local" -ForegroundColor Cyan
        }
        "3" {
            Write-Host ""
            $compress = Read-Host "Nivel de compresión (None/Fast/Maximum)"
            $params.CompressLevel = $compress
            
            $deleteLocal = Read-Host "¿Eliminar backup local después de subir? (S/N)"
            if ($deleteLocal -eq 'S') {
                $params.DeleteLocalBackup = $true
            }
        }
        default {
            $params.CompressLevel = "Maximum"
        }
    }
    
    Write-Host ""
    Write-Host "Iniciando..." -ForegroundColor Green
    Write-Host ""
    
    # Ejecutar backup
    & (Join-Path $PSScriptRoot "Start-BMRBackup.ps1") @params -Verbose
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host " Proceso Completado" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Próximos pasos:" -ForegroundColor Yellow
    Write-Host "  • Revisa los logs en: logs\" -ForegroundColor White
    Write-Host "  • Verifica el backup en Object Storage" -ForegroundColor White
    Write-Host "  • Para restaurar, ejecuta: .\Start-BMRRestore.ps1" -ForegroundColor White
    Write-Host ""
}
else {
    Write-Host ""
    Write-Host "Backup cancelado." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Puedes ejecutar el backup manualmente cuando estés listo:" -ForegroundColor White
    Write-Host "  .\Start-BMRBackup.ps1" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Asistente de Inicio Finalizado" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Documentación adicional:" -ForegroundColor Yellow
Write-Host "  • Guía completa: README.md" -ForegroundColor White
Write-Host "  • Inicio rápido: docs\quick-start.md" -ForegroundColor White
Write-Host "  • Troubleshooting: docs\troubleshooting.md" -ForegroundColor White
Write-Host ""
Write-Host "¡Gracias por usar el Sistema de Backup BMR!" -ForegroundColor Green
Write-Host ""
