<#
.SYNOPSIS
    Prueba la conexión remota a las VPS configuradas.

.DESCRIPTION
    Verifica conectividad RDP y WinRM a las VPS configuradas,
    y muestra información del sistema remoto.

.PARAMETER Target
    VPS a probar: Origen, Destino, Hub, Recuperacion

.EXAMPLE
    .\Test-RemoteConnection.ps1 -Target Origen

.NOTES
    Útil para diagnosticar problemas de conectividad.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Origen', 'Destino', 'Hub', 'Recuperacion')]
    [string]$Target
)

$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $scriptRoot "config\credentials.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Archivo de configuración no encontrado: $configPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$vpsConfig = switch ($Target) {
    'Origen'       { $config.vpsOrigen }
    'Destino'      { $config.vpsDestino }
    'Hub'          { $config.hubBackups }
    'Recuperacion' { $config.servidorRecuperacion }
}

if (-not $vpsConfig.enabled -and $Target -in @('Hub', 'Recuperacion')) {
    Write-Host "$Target no está habilitado en la configuración" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Probando conexión a: $($vpsConfig.name)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "IP: $($vpsConfig.ip)" -ForegroundColor White
Write-Host "Usuario: $($vpsConfig.username)" -ForegroundColor White
Write-Host "Ubicación: $($vpsConfig.location)" -ForegroundColor White
Write-Host ""

# Test 1: Ping
Write-Host "[1/4] Probando PING..." -ForegroundColor Yellow
try {
    $ping = Test-Connection -ComputerName $vpsConfig.ip -Count 2 -ErrorAction Stop
    $avgTime = ($ping | Measure-Object -Property ResponseTime -Average).Average
    Write-Host "  ✓ PING exitoso - Tiempo promedio: $([math]::Round($avgTime, 2)) ms" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ PING falló: $_" -ForegroundColor Red
}

# Test 2: RDP Port
Write-Host "[2/4] Probando puerto RDP (3389)..." -ForegroundColor Yellow
try {
    $rdpTest = Test-NetConnection -ComputerName $vpsConfig.ip -Port 3389 -WarningAction SilentlyContinue
    if ($rdpTest.TcpTestSucceeded) {
        Write-Host "  ✓ Puerto RDP abierto" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Puerto RDP cerrado o bloqueado" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ Error probando RDP: $_" -ForegroundColor Red
}

# Test 3: WinRM Port
Write-Host "[3/4] Probando puerto WinRM (5985)..." -ForegroundColor Yellow
try {
    $winrmTest = Test-NetConnection -ComputerName $vpsConfig.ip -Port 5985 -WarningAction SilentlyContinue
    if ($winrmTest.TcpTestSucceeded) {
        Write-Host "  ✓ Puerto WinRM abierto" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Puerto WinRM cerrado - Intentando HTTPS (5986)" -ForegroundColor Yellow
        
        $winrmHttpsTest = Test-NetConnection -ComputerName $vpsConfig.ip -Port 5986 -WarningAction SilentlyContinue
        if ($winrmHttpsTest.TcpTestSucceeded) {
            Write-Host "  ✓ Puerto WinRM HTTPS abierto" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ WinRM no disponible" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "  ✗ Error probando WinRM: $_" -ForegroundColor Red
}

# Test 4: PSRemoting
Write-Host "[4/4] Probando PowerShell Remoting..." -ForegroundColor Yellow
try {
    $securePassword = ConvertTo-SecureString $vpsConfig.password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vpsConfig.username, $securePassword)
    
    $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
    $session = New-PSSession -ComputerName $vpsConfig.ip -Credential $credential -SessionOption $sessionOption -ErrorAction Stop
    
    Write-Host "  ✓ Sesión PowerShell establecida" -ForegroundColor Green
    
    # Obtener información del sistema
    $info = Invoke-Command -Session $session -ScriptBlock {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $disk = Get-PSDrive C
        
        @{
            Hostname         = $env:COMPUTERNAME
            OS               = $os.Caption
            Version          = $os.Version
            Architecture     = $os.OSArchitecture
            TotalRAM_GB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            DiskTotal_GB     = [math]::Round(($disk.Used + $disk.Free) / 1GB, 2)
            DiskUsed_GB      = [math]::Round($disk.Used / 1GB, 2)
            DiskFree_GB      = [math]::Round($disk.Free / 1GB, 2)
            LastBoot         = $os.LastBootUpTime
            PSVersion        = $PSVersionTable.PSVersion.ToString()
            WSBInstalled     = (Get-WindowsFeature -Name Windows-Server-Backup).Installed
        }
    }
    
    Write-Host ""
    Write-Host "Información del Sistema Remoto:" -ForegroundColor Cyan
    Write-Host "  - Hostname: $($info.Hostname)" -ForegroundColor White
    Write-Host "  - OS: $($info.OS)" -ForegroundColor White
    Write-Host "  - Versión: $($info.Version)" -ForegroundColor White
    Write-Host "  - Arquitectura: $($info.Architecture)" -ForegroundColor White
    Write-Host "  - RAM Total: $($info.TotalRAM_GB) GB" -ForegroundColor White
    Write-Host "  - Disco C:" -ForegroundColor White
    Write-Host "      Total: $($info.DiskTotal_GB) GB" -ForegroundColor White
    Write-Host "      Usado: $($info.DiskUsed_GB) GB" -ForegroundColor White
    Write-Host "      Libre: $($info.DiskFree_GB) GB" -ForegroundColor White
    Write-Host "  - Último arranque: $($info.LastBoot)" -ForegroundColor White
    Write-Host "  - PowerShell: $($info.PSVersion)" -ForegroundColor White
    Write-Host "  - Windows Server Backup: $(if($info.WSBInstalled){'Instalado'}else{'NO instalado'})" -ForegroundColor $(if($info.WSBInstalled){'Green'}else{'Yellow'})
    
    Remove-PSSession $session
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Todos los tests completados exitosamente" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Error conectando por PSRemoting: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Posibles soluciones:" -ForegroundColor Yellow
    Write-Host "  1. Verificar credenciales en config\credentials.json" -ForegroundColor White
    Write-Host "  2. Habilitar PSRemoting en la VPS:" -ForegroundColor White
    Write-Host "     Enable-PSRemoting -Force" -ForegroundColor Gray
    Write-Host "  3. Configurar TrustedHosts:" -ForegroundColor White
    Write-Host "     Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force" -ForegroundColor Gray
    Write-Host "  4. Verificar firewall en la VPS" -ForegroundColor White
}

Write-Host ""
