# ========================================
# DESCARGAR BACKUP DESDE VULTR A RESPALDO-1
# ========================================
# Este script debe ejecutarse DIRECTAMENTE en RESPALDO-1 (216.238.84.243)
# No puede ejecutarse remotamente debido a restricciones de red

Write-Host "`n=== DESCARGANDO BACKUP DESDE VULTR ===" -ForegroundColor Cyan
Write-Host "VPS: RESPALDO-1 (216.238.84.243)" -ForegroundColor White
Write-Host "Backup: CIVER-TWO-BMR-COMPLETO (19.43 GB)`n" -ForegroundColor White

# Paso 1: Crear directorio temporal
Write-Host "[1/4] Creando directorios..." -ForegroundColor Yellow
New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\BackupTemp" -ItemType Directory -Force | Out-Null
Write-Host "      Directorios creados" -ForegroundColor Green

# Paso 2: Instalar AWS CLI si no existe
Write-Host "`n[2/4] Verificando AWS CLI..." -ForegroundColor Yellow
if (-not (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe")) {
    Write-Host "      Descargando AWS CLI (50 MB)..." -ForegroundColor Cyan
    $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $installer = "C:\Temp\AWSCLIV2.msi"
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $awsUrl -OutFile $installer -UseBasicParsing
    
    Write-Host "      Instalando AWS CLI..." -ForegroundColor Cyan
    Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet /norestart" -Wait -NoNewWindow
    Start-Sleep -Seconds 15
    Write-Host "      AWS CLI instalado" -ForegroundColor Green
} else {
    Write-Host "      AWS CLI ya instalado" -ForegroundColor Green
}

$awsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

# Paso 3: Configurar credenciales de Vultr Object Storage
Write-Host "`n[3/4] Configurando credenciales..." -ForegroundColor Yellow
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"
$env:AWS_DEFAULT_REGION = "us-east-1"
Write-Host "      Credenciales configuradas" -ForegroundColor Green

# Paso 4: Descargar backup desde Vultr
Write-Host "`n[4/4] Descargando backup..." -ForegroundColor Yellow
Write-Host "      Origen: s3://almacen-de-backups-cuenta-destino/backups/civer-two/" -ForegroundColor White
Write-Host "      Destino: C:\BackupTemp\" -ForegroundColor White
Write-Host "      Tamaño: 19.43 GB (20 archivos)" -ForegroundColor White
Write-Host "      Tiempo estimado: 3-5 minutos`n" -ForegroundColor Cyan

$startTime = Get-Date

& $awsCli s3 sync s3://almacen-de-backups-cuenta-destino/backups/civer-two/ C:\BackupTemp\ --endpoint-url https://lax1.vultrobjects.com

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalMinutes

# Verificar resultado
if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "DESCARGA COMPLETADA" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    $files = Get-ChildItem "C:\BackupTemp\*.7z.*"
    $totalGB = [math]::Round(($files | Measure-Object Length -Sum).Sum/1GB, 2)
    
    Write-Host "Archivos descargados: $($files.Count)" -ForegroundColor White
    Write-Host "Tamaño total: $totalGB GB" -ForegroundColor White
    Write-Host "Tiempo: $([math]::Round($duration, 2)) minutos" -ForegroundColor White
    Write-Host "Ubicación: C:\BackupTemp\`n" -ForegroundColor White
    
    Write-Host "Archivos:" -ForegroundColor Cyan
    $files | ForEach-Object {
        $sizeMB = [math]::Round($_.Length/1MB, 2)
        Write-Host "  $($_.Name) - $sizeMB MB" -ForegroundColor Gray
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SIGUIENTE PASO: EXTRAER BACKUP" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Para extraer el backup, ejecuta:" -ForegroundColor White
    Write-Host "  7z x C:\BackupTemp\CIVER-TWO-BMR-COMPLETO-20251104-195448.7z.001`n" -ForegroundColor Yellow
    
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "ERROR EN DESCARGA" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Host "Código de error: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Verifica:" -ForegroundColor White
    Write-Host "  - Conexión a internet" -ForegroundColor Gray
    Write-Host "  - Credenciales de Vultr" -ForegroundColor Gray
    Write-Host "  - Espacio en disco C:`n" -ForegroundColor Gray
}
