# AUTOMATIZACION COMPLETA SIN RDP
# Ejecuta todos los procesos automaticamente

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       AUTOMATIZACION COMPLETA - SIN RDP" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$scriptPath = "C:\Users\Public\BMR-Backup-VPS"
$startTime = Get-Date

Write-Host "Inicio:" (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
Write-Host "Tiempo estimado total: 2-3 horas`n" -ForegroundColor Yellow

# FASE 1: HABILITAR PSREMOTING EN RESPALDO-1
Write-Host "`n=== FASE 1/4: HABILITAR PSREMOTING EN RESPALDO-1 ===" -ForegroundColor Green
Write-Host "Tiempo estimado: 2-5 minutos`n" -ForegroundColor Gray

$phase1Start = Get-Date
$phase1Result = & "$scriptPath\Habilitar-PSRemoting-Remoto.ps1"
$phase1Duration = [math]::Round(((Get-Date) - $phase1Start).TotalMinutes, 1)

if ($phase1Result) {
    Write-Host "`n[OK] Fase 1 completada en $phase1Duration minutos" -ForegroundColor Green
    $phase1Success = $true
} else {
    Write-Host "`n[ERROR] Fase 1 fallo" -ForegroundColor Red
    Write-Host "No se puede continuar sin PSRemoting en RESPALDO-1`n" -ForegroundColor Yellow
    $phase1Success = $false
}

# FASE 2: INSTALAR MACRIUM EN CIVER-TWO
Write-Host "`n`n=== FASE 2/4: INSTALAR MACRIUM EN CIVER-TWO ===" -ForegroundColor Green
Write-Host "Tiempo estimado: 5-10 minutos`n" -ForegroundColor Gray

$phase2Start = Get-Date
$phase2Result = & "$scriptPath\Instalar-Macrium-Remoto.ps1"
$phase2Duration = [math]::Round(((Get-Date) - $phase2Start).TotalMinutes, 1)

if ($phase2Result) {
    Write-Host "`n[OK] Fase 2 completada en $phase2Duration minutos" -ForegroundColor Green
    $phase2Success = $true
} else {
    Write-Host "`n[WARNING] Fase 2 tuvo problemas" -ForegroundColor Yellow
    $phase2Success = $false
}

# FASE 3: RESTAURAR BACKUP EN RESPALDO-1
if ($phase1Success) {
    Write-Host "`n`n=== FASE 3/4: RESTAURAR BACKUP EN RESPALDO-1 ===" -ForegroundColor Green
    Write-Host "Tiempo estimado: 45-60 minutos" -ForegroundColor Gray
    Write-Host "Transfiriendo archivos de backup...`n" -ForegroundColor Gray

    $phase3Start = Get-Date
    
    try {
        Write-Host "Iniciando restauracion..." -ForegroundColor Cyan
        & "$scriptPath\Restaurar-RESPALDO1-Simple.ps1"
        
        $phase3Duration = [math]::Round(((Get-Date) - $phase3Start).TotalMinutes, 1)
        Write-Host "`n[OK] Fase 3 completada en $phase3Duration minutos" -ForegroundColor Green
        $phase3Success = $true
    } catch {
        $phase3Duration = [math]::Round(((Get-Date) - $phase3Start).TotalMinutes, 1)
        Write-Host "`n[ERROR] Fase 3 fallo" -ForegroundColor Red
        $phase3Success = $false
    }
} else {
    Write-Host "`n[SKIP] Saltando Fase 3 - PSRemoting no disponible" -ForegroundColor Yellow
    $phase3Success = $false
    $phase3Duration = 0
}

# FASE 4: CREAR IMAGEN BOOTEABLE CON MACRIUM
if ($phase2Success) {
    Write-Host "`n`n=== FASE 4/4: CREAR IMAGEN BOOTEABLE CON MACRIUM ===" -ForegroundColor Green
    Write-Host "Tiempo estimado: 30-60 minutos`n" -ForegroundColor Gray

    $phase4Start = Get-Date
    
    try {
        Write-Host "Iniciando creacion de imagen booteable..." -ForegroundColor Cyan
        & "$scriptPath\Crear-ISO-Booteable-Macrium.ps1"
        
        $phase4Duration = [math]::Round(((Get-Date) - $phase4Start).TotalMinutes, 1)
        Write-Host "`n[OK] Fase 4 completada en $phase4Duration minutos" -ForegroundColor Green
        $phase4Success = $true
    } catch {
        $phase4Duration = [math]::Round(((Get-Date) - $phase4Start).TotalMinutes, 1)
        Write-Host "`n[ERROR] Fase 4 fallo" -ForegroundColor Red
        $phase4Success = $false
    }
} else {
    Write-Host "`n[SKIP] Saltando Fase 4 - Macrium no instalado" -ForegroundColor Yellow
    $phase4Success = $false
    $phase4Duration = 0
}

# RESUMEN FINAL
$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

Write-Host "`n`n============================================================" -ForegroundColor Cyan
Write-Host "           RESUMEN DE AUTOMATIZACION" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

Write-Host "Tiempo total: $totalDuration minutos`n" -ForegroundColor White

Write-Host "Resultados por fase:" -ForegroundColor Cyan
Write-Host "  [1] Habilitar PSRemoting:" $(if($phase1Success){'OK'}else{'FALLO'}) -ForegroundColor $(if($phase1Success){'Green'}else{'Red'})
Write-Host "      Duracion: $phase1Duration minutos" -ForegroundColor Gray

Write-Host "  [2] Instalar Macrium:" $(if($phase2Success){'OK'}else{'FALLO'}) -ForegroundColor $(if($phase2Success){'Green'}else{'Red'})
Write-Host "      Duracion: $phase2Duration minutos" -ForegroundColor Gray

Write-Host "  [3] Restaurar backup:" $(if($phase3Success){'OK'}else{'FALLO'}) -ForegroundColor $(if($phase3Success){'Green'}else{'Red'})
Write-Host "      Duracion: $phase3Duration minutos" -ForegroundColor Gray

Write-Host "  [4] Crear imagen booteable:" $(if($phase4Success){'OK'}else{'SKIP'}) -ForegroundColor $(if($phase4Success){'Green'}else{'Yellow'})
Write-Host "      Duracion: $phase4Duration minutos" -ForegroundColor Gray

# Verificar estado final
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "VERIFICANDO ESTADO FINAL" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

Start-Sleep -Seconds 2
& "$scriptPath\Verificar-Estado-Procesos.ps1"

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "           AUTOMATIZACION COMPLETADA" -ForegroundColor Green
Write-Host "============================================================`n" -ForegroundColor Green

Write-Host "Fin:" (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Gray
Read-Host
