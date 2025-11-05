<#
.SYNOPSIS
    Script simplificado para backup BMR - Ejecuta todo paso a paso.
#>

param(
    [ValidateSet('None', 'Fast', 'Maximum')]
    [string]$CompressLevel = 'Maximum'
)

$ErrorActionPreference = "Stop"

# Configuración
$configPath = ".\config\credentials.json"
$logPath = ".\logs"

if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logPath "backup-simple-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $logMessage = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   BACKUP BMR - VPS WINDOWS SERVER 2025" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Cargar config
Write-Log "Cargando configuración..."
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$vpsOrigen = $config.vpsOrigen

Write-Log "VPS Origen: $($vpsOrigen.name) ($($vpsOrigen.ip))" "SUCCESS"

# Conectar
Write-Log "Conectando a VPS origen..."
$securePassword = ConvertTo-SecureString $vpsOrigen.password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($vpsOrigen.username, $securePassword)
$sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck

try {
    $session = New-PSSession -ComputerName $vpsOrigen.ip -Credential $credential -SessionOption $sessionOption -ErrorAction Stop
    Write-Log "Conexión establecida" "SUCCESS"
}
catch {
    Write-Log "Error conectando: $_" "ERROR"
    exit 1
}

# Paso 1: Instalar Windows Server Backup
Write-Log ""
Write-Log "PASO 1: Verificando Windows Server Backup..." "INFO"

$wsbInstalled = Invoke-Command -Session $session -ScriptBlock {
    $feature = Get-WindowsFeature -Name Windows-Server-Backup
    if (-not $feature.Installed) {
        Write-Host "Instalando Windows Server Backup..."
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature | Out-Null
        return "Instalado"
    }
    return "Ya instalado"
}

Write-Log "Windows Server Backup: $wsbInstalled" "SUCCESS"

# Paso 2: Instalar AWS CLI
Write-Log ""
Write-Log "PASO 2: Verificando AWS CLI..." "INFO"

$awsInstalled = Invoke-Command -Session $session -ScriptBlock {
    $aws = Get-Command aws -ErrorAction SilentlyContinue
    if (-not $aws) {
        try {
            $url = "https://awscli.amazonaws.com/AWSCLIV2.msi"
            $output = "$env:TEMP\AWSCLIV2.msi"
            Write-Host "Descargando AWS CLI..."
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
            Write-Host "Instalando AWS CLI..."
            Start-Process msiexec.exe -ArgumentList "/i `"$output`" /quiet /norestart" -Wait -NoNewWindow
            Remove-Item $output -Force
            
            # Recargar PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            return "Instalado"
        }
        catch {
            return "Error: $_"
        }
    }
    return "Ya instalado"
}

Write-Log "AWS CLI: $awsInstalled" "SUCCESS"

# Paso 3: Crear directorio de backup
Write-Log ""
Write-Log "PASO 3: Preparando directorio de backup..." "INFO"

Invoke-Command -Session $session -ScriptBlock {
    $backupPath = "C:\BackupTemp"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }
    
    $freeSpace = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    Write-Host "Espacio libre: $freeSpace GB"
}

Write-Log "Directorio preparado" "SUCCESS"

# Paso 4: Crear backup BMR
Write-Log ""
Write-Log "══════════════════════════════════════════════════════════" "WARNING"
Write-Log "PASO 4: Creando Backup BMR" "WARNING"
Write-Log "══════════════════════════════════════════════════════════" "WARNING"
Write-Log "NOTA: Este paso puede tardar 30-60 minutos..." "WARNING"
Write-Log ""

$backupResult = Invoke-Command -Session $session -ScriptBlock {
    param($compress)
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "BMR-Backup-$env:COMPUTERNAME-$timestamp"
    $backupPath = "C:\BackupTemp"
    $backupTarget = Join-Path $backupPath $backupName
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Iniciando wbadmin..."
    Write-Host "Backup: $backupTarget"
    
    # Crear backup con wbadmin
    $result = wbadmin start backup `
        -backupTarget:$backupTarget `
        -include:C: `
        -allCritical `
        -quiet `
        2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Backup completado"
        
        # Comprimir
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Comprimiendo backup..."
        $zipPath = "$backupTarget.zip"
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $backupTarget,
            $zipPath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )
        
        $zipSize = [math]::Round((Get-Item $zipPath).Length / 1GB, 2)
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ZIP creado: $zipSize GB"
        
        return @{
            Success = $true
            ZipPath = $zipPath
            SizeGB  = $zipSize
        }
    }
    else {
        return @{
            Success = $false
            Error   = "wbadmin falló con código: $LASTEXITCODE"
        }
    }
} -ArgumentList $CompressLevel

if ($backupResult.Success) {
    Write-Log "Backup creado: $($backupResult.SizeGB) GB" "SUCCESS"
}
else {
    Write-Log "Error en backup: $($backupResult.Error)" "ERROR"
    Remove-PSSession $session
    exit 1
}

# Paso 5: Subir a Object Storage
Write-Log ""
Write-Log "══════════════════════════════════════════════════════════" "WARNING"
Write-Log "PASO 5: Subiendo a Object Storage" "WARNING"
Write-Log "══════════════════════════════════════════════════════════" "WARNING"
Write-Log "NOTA: Este paso puede tardar 20-40 minutos..." "WARNING"
Write-Log ""

$s3Config = $config.objectStorage

$uploadResult = Invoke-Command -Session $session -ScriptBlock {
    param($zipPath, $endpoint, $bucket, $accessKey, $secretKey)
    
    # Configurar AWS
    $env:AWS_ACCESS_KEY_ID = $accessKey
    $env:AWS_SECRET_ACCESS_KEY = $secretKey
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    
    # Crear bucket si no existe
    $checkBucket = aws s3 ls "s3://$bucket" --endpoint-url "https://$endpoint" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creando bucket..."
        aws s3 mb "s3://$bucket" --endpoint-url "https://$endpoint" | Out-Null
    }
    
    # Subir archivo
    $fileName = Split-Path $zipPath -Leaf
    $s3Key = "bmr-backups/$fileName"
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Subiendo a s3://$bucket/$s3Key"
    
    aws s3 cp $zipPath "s3://$bucket/$s3Key" --endpoint-url "https://$endpoint"
    
    if ($LASTEXITCODE -eq 0) {
        return @{
            Success = $true
            S3Key   = $s3Key
            Bucket  = $bucket
        }
    }
    else {
        return @{ Success = $false }
    }
} -ArgumentList $backupResult.ZipPath, $s3Config.endpoint, $s3Config.bucket, $s3Config.accessKey, $s3Config.secretKey

if ($uploadResult.Success) {
    Write-Log "Upload completado" "SUCCESS"
    Write-Log "S3 Key: $($uploadResult.S3Key)" "INFO"
}
else {
    Write-Log "Error en upload" "ERROR"
}

# Limpiar
Remove-PSSession $session

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "   BACKUP COMPLETADO EXITOSAMENTE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Para restaurar en VPS destino:" -ForegroundColor Yellow
Write-Host "  .\Start-BMRRestore-Simple.ps1 -S3Key '$($uploadResult.S3Key)'" -ForegroundColor Cyan
Write-Host ""
