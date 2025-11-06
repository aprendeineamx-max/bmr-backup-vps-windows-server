# ============================================================================
# HABILITAR ACCESO REMOTO COMPLETO EN BACKUP-1
# ============================================================================
# EJECUTAR ESTE SCRIPT EN BACKUP-1 (216.238.84.243) COMO ADMINISTRADOR
# Esto permitirá que Civer-One ejecute comandos remotamente

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CONFIGURANDO ACCESO REMOTO EN BACKUP-1" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. DESHABILITAR FIREWALL COMPLETAMENTE
Write-Host "[1/8] Deshabilitando Firewall..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
Write-Host "      Firewall deshabilitado" -ForegroundColor Green

# 2. HABILITAR PSREMOTING
Write-Host "`n[2/8] Habilitando PSRemoting..." -ForegroundColor Yellow
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Write-Host "      PSRemoting habilitado" -ForegroundColor Green

# 3. HABILITAR WINRM
Write-Host "`n[3/8] Configurando WinRM..." -ForegroundColor Yellow
winrm quickconfig -quiet -force
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client '@{TrustedHosts="*"}'
winrm set winrm/config/client '@{AllowUnencrypted="true"}'
Set-Service WinRM -StartupType Automatic
Restart-Service WinRM -Force
Write-Host "      WinRM configurado" -ForegroundColor Green

# 4. HABILITAR REMOTE REGISTRY
Write-Host "`n[4/8] Habilitando Remote Registry..." -ForegroundColor Yellow
Set-Service RemoteRegistry -StartupType Automatic
Start-Service RemoteRegistry
Write-Host "      Remote Registry habilitado" -ForegroundColor Green

# 5. HABILITAR ADMIN$ SHARE
Write-Host "`n[5/8] Habilitando Admin$ Share..." -ForegroundColor Yellow
# Verificar si existe
$adminShare = Get-SmbShare -Name "ADMIN$" -ErrorAction SilentlyContinue
if (-not $adminShare) {
    New-SmbShare -Name "ADMIN$" -Path "C:\Windows" -FullAccess "Everyone"
    Write-Host "      Admin$ share creado" -ForegroundColor Green
} else {
    Write-Host "      Admin$ share ya existe" -ForegroundColor Green
}

# Configurar política de compartición
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareWks" -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareServer" -Value 1 -Force

# 6. HABILITAR WMI
Write-Host "`n[6/8] Configurando WMI..." -ForegroundColor Yellow
# Habilitar reglas de firewall para WMI (aunque firewall está deshabilitado)
Enable-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)"
Set-Service Winmgmt -StartupType Automatic
Restart-Service Winmgmt -Force
Write-Host "      WMI configurado" -ForegroundColor Green

# 7. DESHABILITAR UAC REMOTO
Write-Host "`n[7/8] Deshabilitando UAC para acceso remoto..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Force
Write-Host "      UAC remoto deshabilitado" -ForegroundColor Green

# 8. VERIFICAR CONFIGURACIÓN
Write-Host "`n[8/8] Verificando configuración..." -ForegroundColor Yellow
Write-Host "`n      Estado de servicios:" -ForegroundColor White
Get-Service WinRM, RemoteRegistry, Winmgmt | Format-Table Name, Status, StartType -AutoSize

Write-Host "`n      Configuración WinRM:" -ForegroundColor White
Write-Host "        - AllowUnencrypted: " -NoNewline -ForegroundColor Gray
Write-Host (Get-Item WSMan:\localhost\Service\AllowUnencrypted).Value -ForegroundColor Cyan
Write-Host "        - Auth.Basic: " -NoNewline -ForegroundColor Gray
Write-Host (Get-Item WSMan:\localhost\Service\Auth\Basic).Value -ForegroundColor Cyan
Write-Host "        - TrustedHosts: " -NoNewline -ForegroundColor Gray
Write-Host (Get-Item WSMan:\localhost\Client\TrustedHosts).Value -ForegroundColor Cyan

Write-Host "`n      Admin$ Share:" -ForegroundColor White
Get-SmbShare -Name "ADMIN$" | Format-Table Name, Path, Description -AutoSize

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "CONFIGURACIÓN COMPLETADA" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "BACKUP-1 está listo para recibir comandos remotos desde Civer-One" -ForegroundColor White
Write-Host "`nPrueba de conexión desde Civer-One:" -ForegroundColor Yellow
Write-Host '  Test-WSMan -ComputerName "216.238.84.243"' -ForegroundColor Cyan
Write-Host "`nNOTA: Es posible que necesites reiniciar el servidor" -ForegroundColor Yellow
Write-Host "para que todos los cambios surtan efecto.`n" -ForegroundColor Yellow

# Preguntar si reiniciar
$restart = Read-Host "¿Deseas reiniciar BACKUP-1 ahora? (S/N)"
if ($restart -eq "S" -or $restart -eq "s") {
    Write-Host "`nReiniciando en 10 segundos..." -ForegroundColor Yellow
    shutdown /r /t 10 /c "Reinicio para aplicar configuración de acceso remoto"
} else {
    Write-Host "`nRecuerda reiniciar manualmente cuando puedas.`n" -ForegroundColor Cyan
}
