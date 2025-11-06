# ============================================================
# HABILITAR PSREMOTING REMOTAMENTE (SIN RDP)
# Usando WMI y sc.exe para configurar WinRM
# ============================================================

param(
    [string]$RemoteHost = "216.238.84.243",
    [string]$Username = "Administrator",
    [string]$Password = "VL0jh-eDuT7+ftUz"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "HABILITANDO PSREMOTING REMOTAMENTE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Servidor: $RemoteHost" -ForegroundColor White
Write-Host "Método: WMI + sc.exe (sin RDP)`n" -ForegroundColor White

# Crear credenciales
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)

# Método 1: Usando PsExec (más confiable)
Write-Host "[1/4] Verificando PsExec..." -ForegroundColor Yellow
$psexecPath = "C:\Windows\Temp\PsExec64.exe"

if (-not (Test-Path $psexecPath)) {
    Write-Host "  Descargando PsExec..." -ForegroundColor Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://live.sysinternals.com/PsExec64.exe" -OutFile $psexecPath -UseBasicParsing
        Write-Host "  [OK] PsExec descargado" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudo descargar PsExec: $_" -ForegroundColor Red
        exit 1
    }
}

# Método 2: Habilitar WinRM remotamente usando PsExec
Write-Host "`n[2/4] Habilitando WinRM en $RemoteHost..." -ForegroundColor Yellow

$commands = @(
    "winrm quickconfig -quiet -force",
    "winrm set winrm/config/service @{AllowUnencrypted=`"true`"}",
    "winrm set winrm/config/service/auth @{Basic=`"true`"}",
    "netsh advfirewall firewall add rule name=`"WinRM-HTTP`" dir=in action=allow protocol=TCP localport=5985",
    "net start winrm"
)

foreach ($cmd in $commands) {
    Write-Host "  Ejecutando: $cmd" -ForegroundColor Gray
    
    $psexecArgs = @(
        "\\$RemoteHost",
        "-u", $Username,
        "-p", $Password,
        "-accepteula",
        "-nobanner",
        "cmd.exe", "/c", $cmd
    )
    
    try {
        $result = & $psexecPath $psexecArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK]" -ForegroundColor Green
        } else {
            Write-Host "  [WARNING] Exit code: $LASTEXITCODE" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARNING] $_" -ForegroundColor Yellow
    }
    
    Start-Sleep -Seconds 2
}

# Método 3: Configurar TrustedHosts localmente
Write-Host "`n[3/4] Configurando TrustedHosts local..." -ForegroundColor Yellow
try {
    $currentHosts = Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue
    if ($currentHosts.Value -notlike "*$RemoteHost*") {
        if ([string]::IsNullOrEmpty($currentHosts.Value)) {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $RemoteHost -Force
        } else {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$($currentHosts.Value),$RemoteHost" -Force
        }
        Write-Host "  [OK] TrustedHosts actualizado" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Ya está en TrustedHosts" -ForegroundColor Green
    }
} catch {
    Write-Host "  [WARNING] $_" -ForegroundColor Yellow
}

# Método 4: Verificar conexión PSRemoting
Write-Host "`n[4/4] Verificando PSRemoting..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$maxRetries = 5
$retryCount = 0
$connected = $false

while ($retryCount -lt $maxRetries -and -not $connected) {
    try {
        Write-Host "  Intento $($retryCount + 1) de $maxRetries..." -ForegroundColor Gray
        
        $session = New-PSSession -ComputerName $RemoteHost -Credential $cred -ErrorAction Stop
        
        $info = Invoke-Command -Session $session -ScriptBlock {
            $os = Get-CimInstance Win32_OperatingSystem
            $disk = Get-PSDrive C
            
            return @{
                Hostname = $env:COMPUTERNAME
                OS = $os.Caption
                FreeGB = [math]::Round($disk.Free/1GB, 2)
                UsedGB = [math]::Round($disk.Used/1GB, 2)
            }
        }
        
        Write-Host "`n  [OK] PSRemoting habilitado exitosamente!" -ForegroundColor Green
        Write-Host "`n  Información del servidor:" -ForegroundColor Cyan
        Write-Host "    Hostname: $($info.Hostname)" -ForegroundColor White
        Write-Host "    OS: $($info.OS)" -ForegroundColor White
        Write-Host "    Disco C: $($info.UsedGB) GB usados, $($info.FreeGB) GB libres" -ForegroundColor White
        
        Remove-PSSession $session
        $connected = $true
        
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        $retryCount++
        
        if ($retryCount -lt $maxRetries) {
            Write-Host "  Esperando 5 segundos antes de reintentar..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
}

if ($connected) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "PSREMOTING HABILITADO EXITOSAMENTE" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    return $true
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "NO SE PUDO HABILITAR PSREMOTING" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Host "Posibles causas:" -ForegroundColor Yellow
    Write-Host "  1. Firewall bloqueando puerto 5985" -ForegroundColor White
    Write-Host "  2. Credenciales incorrectas" -ForegroundColor White
    Write-Host "  3. WinRM no disponible en el servidor`n" -ForegroundColor White
    return $false
}
