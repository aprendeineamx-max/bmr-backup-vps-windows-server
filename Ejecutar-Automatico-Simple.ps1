# AUTOMATIZACION COMPLETA - METODO ALTERNATIVO
# Usa PowerShell remoting directo si esta disponible, sino usa metodos WMI

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "   AUTOMATIZACION COMPLETA - METODO SIMPLIFICADO" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$scriptPath = "C:\Users\Public\BMR-Backup-VPS"

# Configuracion
$respaldo1 = @{
    IP = "216.238.84.243"
    User = "Administrator"
    Pass = "VL0jh-eDuT7+ftUz"
}

$civerTwo = @{
    IP = "216.238.88.126"
    User = "Administrator"
    Pass = "6K#fVnH-arJG-(wT"
}

Write-Host "NOTA IMPORTANTE:" -ForegroundColor Yellow
Write-Host "Este script intentara conectarse remotamente." -ForegroundColor White
Write-Host "Si PSRemoting NO esta habilitado en los servidores," -ForegroundColor White
Write-Host "necesitaras habilitarlo manualmente primero.`n" -ForegroundColor White

Write-Host "Presiona Enter para continuar o Ctrl+C para cancelar..." -ForegroundColor Cyan
Read-Host

$startTime = Get-Date

# VERIFICAR RESPALDO-1
Write-Host "`n=== VERIFICANDO RESPALDO-1 ===" -ForegroundColor Green
$pass1 = ConvertTo-SecureString $respaldo1.Pass -AsPlainText -Force
$cred1 = New-Object PSCredential($respaldo1.User, $pass1)

try {
    $session1 = New-PSSession -ComputerName $respaldo1.IP -Credential $cred1 -ErrorAction Stop
    Write-Host "[OK] PSRemoting YA habilitado en RESPALDO-1" -ForegroundColor Green
    Remove-PSSession $session1
    $respaldo1Ready = $true
} catch {
    Write-Host "[INFO] PSRemoting NO disponible en RESPALDO-1" -ForegroundColor Yellow
    Write-Host "Necesitas habilitarlo manualmente:" -ForegroundColor White
    Write-Host "  1. RDP a 216.238.84.243" -ForegroundColor Gray
    Write-Host "  2. PowerShell: Enable-PSRemoting -Force`n" -ForegroundColor Cyan
    $respaldo1Ready = $false
}

# VERIFICAR CIVER-TWO
Write-Host "`n=== VERIFICANDO CIVER-TWO ===" -ForegroundColor Green
$pass2 = ConvertTo-SecureString $civerTwo.Pass -AsPlainText -Force
$cred2 = New-Object PSCredential($civerTwo.User, $pass2)

try {
    $session2 = New-PSSession -ComputerName $civerTwo.IP -Credential $cred2 -ErrorAction Stop
    Write-Host "[OK] PSRemoting funciona en Civer-Two" -ForegroundColor Green
    
    # Verificar Macrium
    $macriumCheck = Invoke-Command -Session $session2 -ScriptBlock {
        Test-Path "C:\Program Files\Macrium\Reflect\Reflect.exe"
    }
    
    if ($macriumCheck) {
        Write-Host "[OK] Macrium Reflect YA instalado" -ForegroundColor Green
        $macriumReady = $true
    } else {
        Write-Host "[INFO] Macrium NO instalado" -ForegroundColor Yellow
        $macriumReady = $false
    }
    
    Remove-PSSession $session2
    $civerTwoReady = $true
} catch {
    Write-Host "[ERROR] No se puede conectar a Civer-Two: $_" -ForegroundColor Red
    $civerTwoReady = $false
    $macriumReady = $false
}

# DECISION
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "ESTADO DE PREREQUISITOS" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

Write-Host "RESPALDO-1 (PSRemoting):" $(if($respaldo1Ready){'OK'}else{'NO DISPONIBLE'}) -ForegroundColor $(if($respaldo1Ready){'Green'}else{'Red'})
Write-Host "CIVER-TWO (PSRemoting):" $(if($civerTwoReady){'OK'}else{'NO DISPONIBLE'}) -ForegroundColor $(if($civerTwoReady){'Green'}else{'Red'})
Write-Host "Macrium Reflect:" $(if($macriumReady){'INSTALADO'}else{'NO INSTALADO'}) -ForegroundColor $(if($macriumReady){'Green'}else{'Yellow'})

# PROCESOS DISPONIBLES
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "PROCESOS DISPONIBLES" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$canRestore = $respaldo1Ready
$canCreateImage = $civerTwoReady -and $macriumReady

if ($canRestore) {
    Write-Host "[DISPONIBLE] Restauracion de backup a RESPALDO-1" -ForegroundColor Green
} else {
    Write-Host "[NO DISPONIBLE] Restauracion de backup - Requiere PSRemoting en RESPALDO-1" -ForegroundColor Red
}

if ($canCreateImage) {
    Write-Host "[DISPONIBLE] Creacion de imagen booteable con Macrium" -ForegroundColor Green
} else {
    if (-not $civerTwoReady) {
        Write-Host "[NO DISPONIBLE] Imagen booteable - No hay conexion a Civer-Two" -ForegroundColor Red
    } elseif (-not $macriumReady) {
        Write-Host "[NO DISPONIBLE] Imagen booteable - Macrium no instalado" -ForegroundColor Yellow
    }
}

# EJECUTAR PROCESOS DISPONIBLES
if ($canRestore -or $canCreateImage) {
    Write-Host "`nDeseas ejecutar los procesos disponibles? (S/N)" -ForegroundColor Cyan
    $response = Read-Host
    
    if ($response -eq 'S' -or $response -eq 's') {
        # RESTAURACION
        if ($canRestore) {
            Write-Host "`n`n=== RESTAURACION A RESPALDO-1 ===" -ForegroundColor Green
            Write-Host "Iniciando transferencia de 20 archivos (19.43 GB)..." -ForegroundColor Gray
            Write-Host "Tiempo estimado: 45-60 minutos`n" -ForegroundColor Yellow
            
            $restoreStart = Get-Date
            try {
                & "$scriptPath\Restaurar-RESPALDO1-Simple.ps1"
                $restoreDuration = [math]::Round(((Get-Date) - $restoreStart).TotalMinutes, 1)
                Write-Host "`n[OK] Restauracion completada en $restoreDuration minutos" -ForegroundColor Green
            } catch {
                Write-Host "`n[ERROR] Restauracion fallo: $_" -ForegroundColor Red
            }
        }
        
        # IMAGEN BOOTEABLE
        if ($canCreateImage) {
            Write-Host "`n`n=== CREACION DE IMAGEN BOOTEABLE ===" -ForegroundColor Green
            Write-Host "Iniciando creacion de imagen de disco..." -ForegroundColor Gray
            Write-Host "Tiempo estimado: 30-60 minutos`n" -ForegroundColor Yellow
            
            $imageStart = Get-Date
            try {
                & "$scriptPath\Crear-ISO-Booteable-Macrium.ps1"
                $imageDuration = [math]::Round(((Get-Date) - $imageStart).TotalMinutes, 1)
                Write-Host "`n[OK] Imagen completada en $imageDuration minutos" -ForegroundColor Green
            } catch {
                Write-Host "`n[ERROR] Imagen fallo: $_" -ForegroundColor Red
            }
        }
        
        $totalDuration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        Write-Host "`n`nTiempo total: $totalDuration minutos" -ForegroundColor White
    }
} else {
    Write-Host "`n[ERROR] No hay procesos disponibles para ejecutar" -ForegroundColor Red
    Write-Host "`nACCIONES REQUERIDAS:" -ForegroundColor Yellow
    
    if (-not $respaldo1Ready) {
        Write-Host "`n1. Habilitar PSRemoting en RESPALDO-1:" -ForegroundColor Cyan
        Write-Host "   RDP a: 216.238.84.243" -ForegroundColor White
        Write-Host "   Usuario: Administrator" -ForegroundColor White
        Write-Host "   Password: VL0jh-eDuT7+ftUz" -ForegroundColor White
        Write-Host "   Ejecutar: Enable-PSRemoting -Force" -ForegroundColor Cyan
    }
    
    if (-not $macriumReady -and $civerTwoReady) {
        Write-Host "`n2. Instalar Macrium en Civer-Two:" -ForegroundColor Cyan
        Write-Host "   Puedes intentar instalacion remota:" -ForegroundColor White
        Write-Host "   & '$scriptPath\Instalar-Macrium-Remoto.ps1'" -ForegroundColor Cyan
        Write-Host "   O instalacion manual via RDP" -ForegroundColor White
    }
}

# VERIFICACION FINAL
Write-Host "`n`n============================================================" -ForegroundColor Green
Write-Host "VERIFICACION FINAL" -ForegroundColor Green
Write-Host "============================================================`n" -ForegroundColor Green

& "$scriptPath\Verificar-Estado-Procesos.ps1"

Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Gray
Read-Host
