# ============================================================
# SUBIR BACKUP A VULTR OBJECT STORAGE
# ============================================================

param(
    [string]$BackupPath = "C:\BackupTemp\CIVER-TWO-BMR-COMPLETO-20251104-195448.7z.*",
    [string]$BucketName = "almacen-de-backups-cuenta-destino"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUBIR BACKUP A VULTR OBJECT STORAGE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Configuración S3
$AccessKey = "G0LDHU6PIXWDEDJTAQ4B"
$SecretKey = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"
$Endpoint = "https://lax1.vultrobjects.com"
$Region = "us-east-1"  # Vultr usa us-east-1 para firma

# [1] Verificar archivos locales
Write-Host "[1/5] Verificando archivos locales..." -ForegroundColor Yellow
$files = Get-ChildItem $BackupPath | Sort-Object Name
if (-not $files) {
    Write-Host "[ERROR] No se encontraron archivos: $BackupPath" -ForegroundColor Red
    exit 1
}

$totalSize = ($files | Measure-Object Length -Sum).Sum
$totalGB = [math]::Round($totalSize/1GB, 2)
Write-Host "  [OK] $($files.Count) archivos encontrados ($totalGB GB)" -ForegroundColor Green

# [2] Instalar AWS CLI (compatible con S3)
Write-Host "`n[2/5] Instalando AWS CLI..." -ForegroundColor Yellow
$awsInstaller = "C:\Temp\AWSCLIV2.msi"

if (-not (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe")) {
    Write-Host "  Descargando AWS CLI..." -ForegroundColor Cyan
    $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $awsUrl -OutFile $awsInstaller -UseBasicParsing -TimeoutSec 300
        
        Write-Host "  Instalando..." -ForegroundColor Cyan
        Start-Process msiexec.exe -ArgumentList "/i `"$awsInstaller`" /quiet /norestart" -Wait -NoNewWindow
        
        Start-Sleep -Seconds 10
        
        if (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe") {
            Write-Host "  [OK] AWS CLI instalado" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Instalación falló" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [OK] AWS CLI ya instalado" -ForegroundColor Green
}

$awsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

# [3] Configurar credenciales
Write-Host "`n[3/5] Configurando credenciales..." -ForegroundColor Yellow
$env:AWS_ACCESS_KEY_ID = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION = $Region

# Verificar conexión
Write-Host "  Verificando conexión al bucket..." -ForegroundColor Cyan
$testResult = & $awsCli s3 ls "s3://$BucketName" --endpoint-url $Endpoint 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Conexión exitosa" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] No se pudo listar bucket (puede no existir aún)" -ForegroundColor Yellow
    Write-Host "  Creando bucket..." -ForegroundColor Cyan
    & $awsCli s3 mb "s3://$BucketName" --endpoint-url $Endpoint 2>&1 | Out-Null
}

# [4] Subir archivos
Write-Host "`n[4/5] Subiendo archivos a Vultr Object Storage..." -ForegroundColor Yellow
Write-Host "  Bucket: $BucketName" -ForegroundColor White
Write-Host "  Endpoint: $Endpoint" -ForegroundColor White
Write-Host "  Total a subir: $totalGB GB`n" -ForegroundColor White

$startTime = Get-Date
$uploadedCount = 0
$failedCount = 0

foreach ($file in $files) {
    $fileName = $file.Name
    $fileSizeMB = [math]::Round($file.Length/1MB, 2)
    
    Write-Host "  [$($uploadedCount + 1)/$($files.Count)] $fileName ($fileSizeMB MB)..." -ForegroundColor Cyan -NoNewline
    
    $s3Path = "s3://$BucketName/backups/civer-two/$fileName"
    
    try {
        & $awsCli s3 cp $file.FullName $s3Path --endpoint-url $Endpoint --no-progress 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " [OK]" -ForegroundColor Green
            $uploadedCount++
        } else {
            Write-Host " [ERROR]" -ForegroundColor Red
            $failedCount++
        }
    } catch {
        Write-Host " [ERROR] $_" -ForegroundColor Red
        $failedCount++
    }
}

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalMinutes

# [5] Verificar archivos subidos
Write-Host "`n[5/5] Verificando archivos en Object Storage..." -ForegroundColor Yellow
$s3Files = & $awsCli s3 ls "s3://$BucketName/backups/civer-two/" --endpoint-url $Endpoint 2>&1

if ($LASTEXITCODE -eq 0) {
    $s3FileCount = ($s3Files | Measure-Object).Count
    Write-Host "  [OK] $s3FileCount archivos en Object Storage" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] No se pudo verificar" -ForegroundColor Yellow
}

# Resumen
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMEN DE SUBIDA" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Archivos subidos exitosamente: $uploadedCount / $($files.Count)" -ForegroundColor $(if($uploadedCount -eq $files.Count){'Green'}else{'Yellow'})
if ($failedCount -gt 0) {
    Write-Host "Archivos fallidos: $failedCount" -ForegroundColor Red
}
Write-Host "Tiempo total: $([math]::Round($duration, 2)) minutos" -ForegroundColor White
Write-Host "Tamaño total: $totalGB GB" -ForegroundColor White

Write-Host "`nUbicación en Object Storage:" -ForegroundColor Cyan
Write-Host "  s3://$BucketName/backups/civer-two/" -ForegroundColor White

Write-Host "`nPara descargar desde otra VPS:" -ForegroundColor Cyan
Write-Host '  aws s3 sync s3://almacen-de-backups-cuenta-destino/backups/civer-two/ C:\BackupTemp\ --endpoint-url https://lax1.vultrobjects.com' -ForegroundColor White

Write-Host "`n========================================`n" -ForegroundColor Cyan

if ($uploadedCount -eq $files.Count) {
    Write-Host "[OK] BACKUP SUBIDO EXITOSAMENTE A VULTR!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[WARNING] Algunos archivos no se subieron" -ForegroundColor Yellow
    exit 1
}
