<#
.SYNOPSIS
    Script simple para probar conexión a VPS.
#>

param([string]$Target = "Origen")

$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $scriptRoot "config\credentials.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Error: No se encuentra config\credentials.json" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$vpsConfig = if ($Target -eq "Origen") { $config.vpsOrigen } else { $config.vpsDestino }

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Probando conexión a: $($vpsConfig.name)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
Write-Host "IP: $($vpsConfig.ip)" -ForegroundColor White
Write-Host "Usuario: $($vpsConfig.username)" -ForegroundColor White
Write-Host ""

# Test básico de conectividad
Write-Host "[1/3] Probando conectividad básica..." -ForegroundColor Yellow
$pingTest = Test-Connection -ComputerName $vpsConfig.ip -Count 1 -Quiet
if ($pingTest) {
    Write-Host "  ✓ Servidor responde a PING" -ForegroundColor Green
} else {
    Write-Host "  ⚠ PING no responde (puede estar bloqueado)" -ForegroundColor Yellow
}

# Test puerto RDP
Write-Host "`n[2/3] Probando puerto RDP (3389)..." -ForegroundColor Yellow
$rdpTest = Test-NetConnection -ComputerName $vpsConfig.ip -Port 3389 -WarningAction SilentlyContinue
if ($rdpTest.TcpTestSucceeded) {
    Write-Host "  ✓ Puerto RDP abierto" -ForegroundColor Green
} else {
    Write-Host "  ✗ Puerto RDP no accesible" -ForegroundColor Red
}

# Test PowerShell Remoting
Write-Host "`n[3/3] Probando PowerShell Remoting..." -ForegroundColor Yellow
try {
    $securePassword = ConvertTo-SecureString $vpsConfig.password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vpsConfig.username, $securePassword)
    
    $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
    $session = New-PSSession -ComputerName $vpsConfig.ip -Credential $credential -SessionOption $sessionOption -ErrorAction Stop
    
    Write-Host "  ✓ Sesión PowerShell establecida exitosamente" -ForegroundColor Green
    
    # Obtener info básica
    $info = Invoke-Command -Session $session -ScriptBlock {
        @{
            Hostname    = $env:COMPUTERNAME
            FreeSpaceGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
            UsedSpaceGB = [math]::Round((Get-PSDrive C).Used / 1GB, 2)
        }
    }
    
    Write-Host "`n  Información del servidor:" -ForegroundColor Cyan
    Write-Host "    - Hostname: $($info.Hostname)" -ForegroundColor White
    Write-Host "    - Espacio libre en C:: $($info.FreeSpaceGB) GB" -ForegroundColor White
    Write-Host "    - Espacio usado en C:: $($info.UsedSpaceGB) GB" -ForegroundColor White
    
    Remove-PSSession $session
    
    Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Conexión exitosa - Todo listo para continuar" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Green
    
    return $true
}
catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
    Write-Host "`n  Posibles soluciones:" -ForegroundColor Yellow
    Write-Host "    1. Verificar credenciales en config\credentials.json" -ForegroundColor White
    Write-Host "    2. Habilitar WinRM en la VPS con: Enable-PSRemoting -Force" -ForegroundColor White
    Write-Host "`n" -ForegroundColor White
    return $false
}
