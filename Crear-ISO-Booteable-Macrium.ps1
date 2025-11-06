# ============================================================
# CREAR ISO BOOTEABLE CON MACRIUM REFLECT
# Ejecutar desde Civer-One hacia Civer-Two
# ============================================================

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "CREACION DE ISO BOOTEABLE CON MACRIUM REFLECT" -ForegroundColor Cyan
Write-Host "======================================================`n" -ForegroundColor Cyan

# Configuración
$civerTwoIP = "216.238.88.126"
$civerTwoUser = "Administrator"
$civerTwoPass = "6K#fVnH-arJG-(wT"

Write-Host "[1/6] Conectando a Civer-Two..." -ForegroundColor Yellow
$pass = ConvertTo-SecureString $civerTwoPass -AsPlainText -Force
$cred = New-Object PSCredential($civerTwoUser, $pass)

try {
    $session = New-PSSession -ComputerName $civerTwoIP -Credential $cred -ErrorAction Stop
    Write-Host "  [OK] Conectado a Civer-Two" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] No se pudo conectar: $_" -ForegroundColor Red
    exit 1
}

# Verificar Macrium Reflect
Write-Host "`n[2/6] Verificando instalación de Macrium Reflect..." -ForegroundColor Yellow
$macriumInfo = Invoke-Command -Session $session -ScriptBlock {
    $result = @{
        InstallerPath = $null
        InstallPath = $null
        IsInstalled = $false
    }
    
    # Buscar instalador
    $installerLocations = @(
        "C:\Users\Administrator\Desktop\MacriumReflect.exe",
        "C:\Users\Administrator\Downloads\MacriumReflect.exe",
        "C:\Temp\MacriumReflect.exe"
    )
    
    foreach ($loc in $installerLocations) {
        if (Test-Path $loc) {
            $result.InstallerPath = $loc
            break
        }
    }
    
    # Buscar instalación existente
    $programPaths = @(
        "C:\Program Files\Macrium\Reflect\Reflect.exe",
        "C:\Program Files (x86)\Macrium\Reflect\Reflect.exe"
    )
    
    foreach ($path in $programPaths) {
        if (Test-Path $path) {
            $result.InstallPath = $path
            $result.IsInstalled = $true
            break
        }
    }
    
    return $result
}

if ($macriumInfo.IsInstalled) {
    Write-Host "  [OK] Macrium Reflect ya está instalado" -ForegroundColor Green
    Write-Host "  Ruta: $($macriumInfo.InstallPath)" -ForegroundColor White
    $macriumExe = $macriumInfo.InstallPath
} elseif ($macriumInfo.InstallerPath) {
    Write-Host "  [INFO] Instalador encontrado en: $($macriumInfo.InstallerPath)" -ForegroundColor Yellow
    Write-Host "  [ACCION REQUERIDA] Necesitas instalar Macrium primero" -ForegroundColor Yellow
    Write-Host "`n  Para instalar via RDP:" -ForegroundColor Cyan
    Write-Host "    1. Conecta a Civer-Two (216.238.88.126)" -ForegroundColor White
    Write-Host "    2. Ejecuta: $($macriumInfo.InstallerPath)" -ForegroundColor White
    Write-Host "    3. Sigue el asistente (instalación típica)" -ForegroundColor White
    Write-Host "    4. Vuelve a ejecutar este script`n" -ForegroundColor White
    
    Remove-PSSession $session
    Write-Host "Presiona Enter para cerrar..." -ForegroundColor Gray
    Read-Host
    exit 0
} else {
    Write-Host "  [ERROR] Macrium Reflect no encontrado" -ForegroundColor Red
    Write-Host "  Descárgalo desde: https://www.macrium.com/reflectfree" -ForegroundColor Yellow
    Remove-PSSession $session
    exit 1
}

# Crear script de creación de imagen en Civer-Two
Write-Host "`n[3/6] Preparando creación de imagen de disco..." -ForegroundColor Yellow

$imageScript = @'
param($OutputPath, $MacriumPath)

Write-Host "`n=== CREANDO IMAGEN DE DISCO ===" -ForegroundColor Cyan

# Verificar espacio disponible
$drive = Get-PSDrive C
$freeGB = [math]::Round($drive.Free/1GB, 2)
$usedGB = [math]::Round($drive.Used/1GB, 2)

Write-Host "Disco C:" -ForegroundColor White
Write-Host "  Usado: $usedGB GB" -ForegroundColor White
Write-Host "  Libre: $freeGB GB" -ForegroundColor White

if ($freeGB -lt 20) {
    Write-Host "`n[WARNING] Espacio libre bajo. Puede no ser suficiente." -ForegroundColor Yellow
}

# Crear directorio de salida
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$imageName = "CIVER-TWO-BOOTEABLE-$timestamp"
$imageDir = Join-Path $OutputPath $imageName
New-Item -Path $imageDir -ItemType Directory -Force | Out-Null

Write-Host "`nDirectorio de imagen: $imageDir" -ForegroundColor Cyan

# Verificar si Macrium tiene CLI disponible
$macriumCLI = Join-Path (Split-Path $MacriumPath) "ReflectCLI.exe"

if (Test-Path $macriumCLI) {
    Write-Host "`n[OK] CLI de Macrium encontrado" -ForegroundColor Green
    
    # Crear imagen usando CLI
    Write-Host "`nIniciando creación de imagen (esto puede tardar 30-60 minutos)..." -ForegroundColor Yellow
    Write-Host "NOTA: Este proceso continuará aunque cierres esta ventana`n" -ForegroundColor Cyan
    
    $xmlDef = @"
<?xml version="1.0" encoding="UTF-8"?>
<backupset>
  <backup>
    <source>
      <partition>C:</partition>
    </source>
    <destination>
      <filename>$imageDir\$imageName.mrimg</filename>
      <verify>true</verify>
    </destination>
  </backup>
</backupset>
"@
    
    $xmlPath = Join-Path $imageDir "backup-definition.xml"
    $xmlDef | Out-File -FilePath $xmlPath -Encoding UTF8
    
    Write-Host "Ejecutando: $macriumCLI -e -w $xmlPath" -ForegroundColor Gray
    
    $process = Start-Process -FilePath $macriumCLI -ArgumentList "-e -w `"$xmlPath`"" -NoNewWindow -PassThru -Wait
    
    if ($process.ExitCode -eq 0) {
        Write-Host "`n[OK] Imagen creada exitosamente" -ForegroundColor Green
        
        $imageFile = Get-ChildItem $imageDir -Filter "*.mrimg" | Select-Object -First 1
        if ($imageFile) {
            $sizeGB = [math]::Round($imageFile.Length/1GB, 2)
            Write-Host "Archivo: $($imageFile.FullName)" -ForegroundColor White
            Write-Host "Tamaño: $sizeGB GB" -ForegroundColor White
            return @{Success=$true; Path=$imageFile.FullName; SizeGB=$sizeGB}
        }
    } else {
        Write-Host "`n[ERROR] Error al crear imagen. Código: $($process.ExitCode)" -ForegroundColor Red
        return @{Success=$false}
    }
    
} else {
    Write-Host "`n[INFO] CLI no disponible. Usa la interfaz gráfica:" -ForegroundColor Yellow
    Write-Host "  1. Abre Macrium Reflect" -ForegroundColor White
    Write-Host "  2. Selecciona disco C:" -ForegroundColor White
    Write-Host "  3. Click en 'Image this disk...'" -ForegroundColor White
    Write-Host "  4. Selecciona destino: $imageDir" -ForegroundColor White
    Write-Host "  5. Opciones: Comprimir (Medium), Verificar imagen" -ForegroundColor White
    Write-Host "  6. Click 'Next' y 'Finish'`n" -ForegroundColor White
    
    # Abrir Macrium GUI
    Write-Host "Abriendo Macrium Reflect..." -ForegroundColor Cyan
    Start-Process -FilePath $MacriumPath
    
    return @{Success=$false; Message="Manual GUI required"}
}
'@

Write-Host "  [OK] Script preparado" -ForegroundColor Green

# Ejecutar creación de imagen
Write-Host "`n[4/6] Iniciando creación de imagen en Civer-Two..." -ForegroundColor Yellow
Write-Host "  NOTA: Este proceso puede tardar 30-60 minutos" -ForegroundColor Cyan
Write-Host "  Puedes monitorear el progreso via RDP a Civer-Two`n" -ForegroundColor Cyan

$result = Invoke-Command -Session $session -ScriptBlock ([ScriptBlock]::Create($imageScript)) -ArgumentList @("C:\BackupTemp", $macriumExe)

if ($result.Success) {
    Write-Host "`n[5/6] Creando medio de rescate booteable..." -ForegroundColor Yellow
    
    # Crear rescue media
    $rescueScript = @'
param($MacriumPath, $OutputPath)

$macriumDir = Split-Path $MacriumPath
$rescueCLI = Join-Path $macriumDir "RescueMediaBuilder.exe"

if (Test-Path $rescueCLI) {
    $isoPath = Join-Path $OutputPath "Macrium-Rescue-Media.iso"
    Write-Host "Creando ISO de rescate en: $isoPath" -ForegroundColor Cyan
    
    # Ejecutar creador de medio de rescate
    $process = Start-Process -FilePath $rescueCLI -ArgumentList "/iso `"$isoPath`" /quiet" -NoNewWindow -PassThru -Wait
    
    if ($process.ExitCode -eq 0 -and (Test-Path $isoPath)) {
        $sizeGB = [math]::Round((Get-Item $isoPath).Length/1GB, 2)
        Write-Host "[OK] ISO de rescate creado: $sizeGB GB" -ForegroundColor Green
        return @{Success=$true; Path=$isoPath; SizeGB=$sizeGB}
    } else {
        Write-Host "[WARNING] No se pudo crear ISO automáticamente" -ForegroundColor Yellow
        return @{Success=$false}
    }
} else {
    Write-Host "[INFO] Crea el medio de rescate manualmente:" -ForegroundColor Yellow
    Write-Host "  1. En Macrium Reflect, click 'Other Tasks'" -ForegroundColor White
    Write-Host "  2. Click 'Create Rescue Media'" -ForegroundColor White
    Write-Host "  3. Selecciona 'Windows PE 10 (x64)'" -ForegroundColor White
    Write-Host "  4. Guarda en: C:\BackupTemp\Macrium-Rescue-Media.iso" -ForegroundColor White
    return @{Success=$false}
}
'@
    
    $rescueResult = Invoke-Command -Session $session -ScriptBlock ([ScriptBlock]::Create($rescueScript)) -ArgumentList @($macriumExe, "C:\BackupTemp")
    
    if ($rescueResult.Success) {
        Write-Host "`n[6/6] Proceso completado exitosamente" -ForegroundColor Green
        Write-Host "`n======================================================" -ForegroundColor Green
        Write-Host "ISO BOOTEABLE CREADO EXITOSAMENTE" -ForegroundColor Green
        Write-Host "======================================================`n" -ForegroundColor Green
        
        Write-Host "Archivos creados en Civer-Two:" -ForegroundColor Cyan
        Write-Host "  1. Imagen de disco: $($result.Path) ($($result.SizeGB) GB)" -ForegroundColor White
        Write-Host "  2. ISO de rescate: $($rescueResult.Path) ($($rescueResult.SizeGB) GB)" -ForegroundColor White
        
        Write-Host "`nPara usar el ISO booteable:" -ForegroundColor Cyan
        Write-Host "  1. Descarga el ISO de rescate desde Civer-Two" -ForegroundColor White
        Write-Host "  2. En Vultr, sube el ISO a 'ISO Library'" -ForegroundColor White
        Write-Host "  3. Crea nueva VPS seleccionando tu ISO personalizado" -ForegroundColor White
        Write-Host "  4. La VPS arrancará con el entorno de rescate de Macrium" -ForegroundColor White
        Write-Host "  5. Desde ahí, restaura la imagen del disco`n" -ForegroundColor White
    } else {
        Write-Host "`n[INFO] Imagen creada pero ISO de rescate requiere creación manual" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[INFO] Continúa el proceso manualmente via RDP en Civer-Two" -ForegroundColor Yellow
}

Remove-PSSession $session

Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Gray
Read-Host
