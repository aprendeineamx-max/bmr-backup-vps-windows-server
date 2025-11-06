# INSTALACION SILENCIOSA DE MACRIUM REFLECT - VERSION SIMPLE
# Ejecuta instalacion remota en Civer-Two

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "INSTALACION REMOTA DE MACRIUM REFLECT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Configuracion
$remoteHost = "216.238.88.126"
$username = "Administrator"
$password = "6K#fVnH-arJG-(wT"

# Conectar
Write-Host "[1/4] Conectando a Civer-Two..." -ForegroundColor Yellow
$secPass = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object PSCredential($username, $secPass)

try {
    $session = New-PSSession -ComputerName $remoteHost -Credential $cred -ErrorAction Stop
    Write-Host "  [OK] Conectado" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] No se pudo conectar" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

# Verificar si ya esta instalado
Write-Host "`n[2/4] Verificando instalacion existente..." -ForegroundColor Yellow
$alreadyInstalled = Invoke-Command -Session $session -ScriptBlock {
    Test-Path "C:\Program Files\Macrium\Reflect\Reflect.exe"
}

if ($alreadyInstalled) {
    Write-Host "  [OK] Macrium ya esta instalado!" -ForegroundColor Green
    Remove-PSSession $session
    exit 0
}

# Buscar instalador
Write-Host "`n[3/4] Buscando instalador..." -ForegroundColor Yellow
$installerPath = Invoke-Command -Session $session -ScriptBlock {
    $paths = @(
        "C:\Users\Administrator\Desktop\MacriumReflect.exe",
        "C:\Users\Administrator\Downloads\MacriumReflect.exe"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

if (-not $installerPath) {
    Write-Host "  [ERROR] Instalador no encontrado" -ForegroundColor Red
    Write-Host "  Descarga Macrium Reflect desde: https://www.macrium.com/reflectfree" -ForegroundColor Yellow
    Remove-PSSession $session
    exit 1
}

Write-Host "  [OK] Encontrado: $installerPath" -ForegroundColor Green

# Instalar
Write-Host "`n[4/4] Instalando Macrium..." -ForegroundColor Yellow
Write-Host "  NOTA: Instalacion silenciosa puede tardar 5-10 minutos" -ForegroundColor Cyan
Write-Host "  Por favor espera...`n" -ForegroundColor Gray

$installSuccess = Invoke-Command -Session $session -ScriptBlock {
    param($InstallerPath)
    
    try {
        # Argumentos de instalacion silenciosa
        $installArgs = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL"
        
        Write-Host "  Ejecutando: $InstallerPath $installArgs" -ForegroundColor Gray
        
        # Iniciar instalacion
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        Write-Host "  Exit Code: $($proc.ExitCode)" -ForegroundColor Gray
        
        # Esperar y verificar
        Start-Sleep -Seconds 10
        
        $installed = Test-Path "C:\Program Files\Macrium\Reflect\Reflect.exe"
        
        if ($installed) {
            Write-Host "  [OK] Instalacion completada" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [WARNING] No se encontro ejecutable despues de instalacion" -ForegroundColor Yellow
            return $false
        }
        
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        return $false
    }
} -ArgumentList $installerPath

Remove-PSSession $session

if ($installSuccess) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "MACRIUM REFLECT INSTALADO EXITOSAMENTE" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "INSTALACION FALLO O REQUIERE MANUAL" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Host "Prueba instalacion manual:" -ForegroundColor Yellow
    Write-Host "  1. RDP a 216.238.88.126" -ForegroundColor White
    Write-Host "  2. Ejecuta: $installerPath`n" -ForegroundColor White
    exit 1
}
