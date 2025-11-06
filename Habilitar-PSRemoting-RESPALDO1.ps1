# ============================================================
# HABILITAR PSREMOTING EN RESPALDO-1
# ============================================================
# INSTRUCCIONES:
# 1. Conecta por RDP a RESPALDO-1 (216.238.84.243)
# 2. Abre PowerShell como Administrator
# 3. Ejecuta este script
# ============================================================

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "HABILITANDO PSREMOTING EN RESPALDO-1" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# Paso 1: Habilitar PSRemoting
Write-Host "[1/5] Habilitando PSRemoting..." -ForegroundColor Yellow
try {
    Enable-PSRemoting -Force -ErrorAction Stop
    Write-Host "  [OK] PSRemoting habilitado" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] $_" -ForegroundColor Red
    exit 1
}

# Paso 2: Configurar firewall
Write-Host "`n[2/5] Configurando reglas de firewall..." -ForegroundColor Yellow
try {
    Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any -ErrorAction Stop
    Write-Host "  [OK] Firewall configurado" -ForegroundColor Green
} catch {
    Write-Host "  [WARNING] No se pudo configurar firewall automáticamente" -ForegroundColor Yellow
}

# Paso 3: Configurar TrustedHosts (permitir conexión desde Civer-One)
Write-Host "`n[3/5] Configurando TrustedHosts..." -ForegroundColor Yellow
try {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "216.238.80.222" -Force -ErrorAction Stop
    Write-Host "  [OK] TrustedHosts configurado" -ForegroundColor Green
} catch {
    Write-Host "  [WARNING] $_" -ForegroundColor Yellow
}

# Paso 4: Reiniciar servicio WinRM
Write-Host "`n[4/5] Reiniciando servicio WinRM..." -ForegroundColor Yellow
try {
    Restart-Service WinRM -Force -ErrorAction Stop
    Write-Host "  [OK] WinRM reiniciado" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] $_" -ForegroundColor Red
}

# Paso 5: Verificar configuración
Write-Host "`n[5/5] Verificando configuración..." -ForegroundColor Yellow
$winrmService = Get-Service WinRM
$winrmConfig = Test-WSMan -ErrorAction SilentlyContinue

if ($winrmService.Status -eq "Running" -and $winrmConfig) {
    Write-Host "  [OK] WinRM está funcionando correctamente" -ForegroundColor Green
    Write-Host "`n================================================" -ForegroundColor Green
    Write-Host "PSREMOTING HABILITADO EXITOSAMENTE" -ForegroundColor Green
    Write-Host "================================================`n" -ForegroundColor Green
    Write-Host "Ahora puedes ejecutar el script de restauración desde Civer-One`n" -ForegroundColor White
} else {
    Write-Host "  [ERROR] WinRM no está funcionando correctamente" -ForegroundColor Red
    Write-Host "  Estado del servicio: $($winrmService.Status)" -ForegroundColor Yellow
}

# Mostrar información del sistema
Write-Host "`nInformación del sistema:" -ForegroundColor Cyan
Write-Host "  Hostname: $env:COMPUTERNAME" -ForegroundColor White
Write-Host "  IP: $(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*'} | Select-Object -First 1 -ExpandProperty IPAddress)" -ForegroundColor White
$disk = Get-PSDrive C
Write-Host "  Disco C: $([math]::Round($disk.Free/1GB,2)) GB libres de $([math]::Round(($disk.Used+$disk.Free)/1GB,2)) GB" -ForegroundColor White

Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Gray
Read-Host
