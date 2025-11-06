# ============================================================
# DESCARGAR BACKUP DESDE VULTR OBJECT STORAGE
# Ejecutar en RESPALDO-1 o cualquier VPS destino
# ============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DESCARGAR BACKUP DESDE VULTR" -ForegroundColor Cyan  
Write-Host "========================================`n" -ForegroundColor Cyan

# Configuración
$AccessKey = "G0LDHU6PIXWDEDJTAQ4B"
$SecretKey = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"
$Endpoint = "https://lax1.vultrobjects.com"
$BucketName = "almacen-de-backups-cuenta-destino"
$DestPath = "C:\BackupTemp"

# [1] Instalar AWS CLI
Write-Host "[1/4] Verificando AWS CLI..." -ForegroundColor Yellow
if (-not (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe")) {
    Write-Host "  Instalando AWS CLI..." -ForegroundColor Cyan
    $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $installer = "C:\Temp\AWSCLIV2.msi"
    New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $awsUrl -OutFile $installer -UseBasicParsing -TimeoutSec 300
    Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /quiet /norestart" -Wait -NoNewWindow
    Start-Sleep -Seconds 10
    
    if (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe") {
        Write-Host "  [OK] AWS CLI instalado" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] Instalación falló" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [OK] AWS CLI ya instalado" -ForegroundColor Green
}

$awsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

# [2] Configurar credenciales
Write-Host "`n[2/4] Configurando credenciales..." -ForegroundColor Yellow
$env:AWS_ACCESS_KEY_ID = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION = "us-east-1"
Write-Host "  [OK] Credenciales configuradas" -ForegroundColor Green

# [3] Listar archivos en Object Storage
Write-Host "`n[3/4] Listando archivos en Vultr Object Storage..." -ForegroundColor Yellow
$s3Path = "s3://$BucketName/backups/civer-two/"
$files = & $awsCli s3 ls $s3Path --endpoint-url $Endpoint 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] No se pudo listar archivos" -ForegroundColor Red
    Write-Host "  $files" -ForegroundColor Red
    exit 1
}

$fileList = $files | ForEach-Object {
    if ($_ -match "(\d+)\s+(\S+\.7z\.\d+)$") {
        [PSCustomObject]@{
            Size = [long]$Matches[1]
            Name = $Matches[2]
        }
    }
}

$totalSizeGB = [math]::Round(($fileList | Measure-Object Size -Sum).Sum/1GB, 2)
Write-Host "  [OK] $($fileList.Count) archivos encontrados ($totalSizeGB GB)" -ForegroundColor Green

# [4] Descargar archivos
Write-Host "`n[4/4] Descargando archivos..." -ForegroundColor Yellow
New-Item -Path $DestPath -ItemType Directory -Force | Out-Null

$startTime = Get-Date
Write-Host "  Destino: $DestPath`n" -ForegroundColor White

& $awsCli s3 sync $s3Path $DestPath --endpoint-url $Endpoint

if ($LASTEXITCODE -eq 0) {
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalMinutes
    
    # Verificar archivos descargados
    $downloadedFiles = Get-ChildItem "$DestPath\*.7z.*" | Sort-Object Name
    $downloadedSize = ($downloadedFiles | Measure-Object Length -Sum).Sum
    $downloadedGB = [math]::Round($downloadedSize/1GB, 2)
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "DESCARGA COMPLETADA" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "Archivos descargados: $($downloadedFiles.Count)" -ForegroundColor White
    Write-Host "Tamaño total: $downloadedGB GB" -ForegroundColor White
    Write-Host "Tiempo: $([math]::Round($duration, 2)) minutos" -ForegroundColor White
    Write-Host "Ubicación: $DestPath`n" -ForegroundColor White
    
    # [5] Extraer backup
    Write-Host "¿Deseas extraer el backup ahora? (S/N): " -ForegroundColor Yellow -NoNewline
    $respuesta = Read-Host
    
    if ($respuesta -eq "S" -or $respuesta -eq "s") {
        Write-Host "`nExtrayendo backup..." -ForegroundColor Cyan
        
        $sevenZip = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZip)) {
            Write-Host "[ERROR] 7-Zip no instalado" -ForegroundColor Red
            Write-Host "Descarga desde: https://www.7-zip.org/download.html" -ForegroundColor Yellow
        } else {
            $firstPart = $downloadedFiles | Where-Object { $_.Name -match "\.001$" } | Select-Object -First 1
            
            if ($firstPart) {
                Write-Host "Extrayendo: $($firstPart.FullName)" -ForegroundColor White
                & $sevenZip x $firstPart.FullName -o"$DestPath\" -y
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n[OK] Backup extraído exitosamente" -ForegroundColor Green
                    Write-Host "Carpetas extraídas en: $DestPath" -ForegroundColor White
                    
                    # Mostrar carpetas extraídas
                    Get-ChildItem $DestPath -Directory | ForEach-Object {
                        $size = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum
                        $sizeGB = [math]::Round($size/1GB, 2)
                        Write-Host "  $($_.Name): $sizeGB GB" -ForegroundColor Cyan
                    }
                } else {
                    Write-Host "[ERROR] Extracción falló" -ForegroundColor Red
                }
            }
        }
    }
    
    Write-Host "`n========================================`n" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] Descarga falló" -ForegroundColor Red
    exit 1
}
