<#
.SYNOPSIS
    Sube el backup BMR a Vultr Object Storage (S3-compatible).

.DESCRIPTION
    Transfiere el archivo de backup comprimido desde la VPS local
    hacia Vultr Object Storage para almacenamiento seguro.

.PARAMETER BackupPath
    Ruta del archivo de backup a subir.

.PARAMETER ConfigPath
    Ruta del archivo de configuración con credenciales.

.EXAMPLE
    .\Upload-ToObjectStorage.ps1 -BackupPath "C:\BackupTemp\BMR-Backup-Server1-20250104.zip"

.NOTES
    Requiere AWS CLI instalado y configurado.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    
    [string]$ConfigPath = "..\..\config\credentials.json",
    
    [string]$S3Prefix = "bmr-backups",
    
    [switch]$DeleteAfterUpload
)

# Importar utilidades
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "..\utils\Logger.ps1")
. (Join-Path $scriptPath "..\utils\S3-Helper.ps1")

Initialize-Logger -LogName "upload-backup"

Write-LogInfo "========================================"
Write-LogInfo "Subiendo Backup a Object Storage"
Write-LogInfo "========================================"

# Verificar que el archivo existe
if (-not (Test-Path $BackupPath)) {
    Write-LogError "Archivo de backup no encontrado: $BackupPath"
    exit 1
}

$backupFile = Get-Item $BackupPath
$backupSizeGB = [math]::Round($backupFile.Length / 1GB, 2)

Write-LogInfo "Archivo de backup: $($backupFile.Name)"
Write-LogInfo "Tamaño: $backupSizeGB GB"

# Cargar configuración
$configFullPath = Join-Path $scriptPath $ConfigPath
if (-not (Test-Path $configFullPath)) {
    Write-LogError "Archivo de configuración no encontrado: $configFullPath"
    exit 1
}

Write-LogInfo "Cargando configuración..."
$config = Get-Content $configFullPath -Raw | ConvertFrom-Json

if (-not $config.objectStorage.enabled) {
    Write-LogError "Object Storage no está habilitado en la configuración"
    exit 1
}

$s3Config = $config.objectStorage

Write-LogInfo "Configuración de Object Storage:"
Write-LogInfo "  - Endpoint: $($s3Config.endpoint)"
Write-LogInfo "  - Bucket: $($s3Config.bucket)"
Write-LogInfo "  - Región: $($s3Config.region)"

# Verificar e instalar herramientas S3
Write-LogInfo "Verificando herramientas S3..."
$tools = Test-S3Tools

if (-not $tools.HasAny) {
    Write-LogWarning "AWS CLI no encontrado. Instalando..."
    if (-not (Install-AWSCLI)) {
        Write-LogError "No se pudo instalar AWS CLI"
        exit 1
    }
    
    # Recargar PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
}

# Configurar credenciales S3
Write-LogInfo "Configurando credenciales S3..."
Initialize-S3Config -S3Config @{
    accessKey = $s3Config.accessKey
    secretKey = $s3Config.secretKey
    region    = $s3Config.region
}

# Verificar que el bucket existe
Write-LogInfo "Verificando bucket S3..."
$bucketExists = Test-S3Bucket -Endpoint $s3Config.endpoint -Bucket $s3Config.bucket

if (-not $bucketExists) {
    Write-LogWarning "Bucket no existe. Creando..."
    $created = New-S3Bucket -Endpoint $s3Config.endpoint -Bucket $s3Config.bucket
    
    if (-not $created) {
        Write-LogError "No se pudo crear el bucket"
        exit 1
    }
}

Write-LogSuccess "Bucket verificado: $($s3Config.bucket)"

# Preparar clave S3 (ruta dentro del bucket)
$s3Key = "$S3Prefix/$($backupFile.Name)"

Write-LogInfo ""
Write-LogInfo "Iniciando transferencia a Object Storage..."
Write-LogInfo "  - Origen: $BackupPath"
Write-LogInfo "  - Destino: s3://$($s3Config.bucket)/$s3Key"
Write-LogInfo ""
Write-LogWarning "Esta operación puede tardar 20-40 minutos dependiendo del tamaño del archivo y el ancho de banda"
Write-LogInfo ""

# Calcular checksum antes de subir
Write-LogInfo "Calculando checksum del archivo..."
$md5Hash = Get-FileHash -Path $BackupPath -Algorithm MD5
Write-LogInfo "MD5: $($md5Hash.Hash)"

# Subir archivo
$uploadSuccess = Send-FileToS3 `
    -FilePath $BackupPath `
    -Endpoint $s3Config.endpoint `
    -Bucket $s3Config.bucket `
    -S3Key $s3Key `
    -ShowProgress

if (-not $uploadSuccess) {
    Write-LogError "Error subiendo archivo a Object Storage"
    exit 1
}

Write-LogSuccess "Archivo subido correctamente"

# Verificar que el archivo está en S3
Write-LogInfo "Verificando archivo en Object Storage..."
$s3Objects = Get-S3Objects -Endpoint $s3Config.endpoint -Bucket $s3Config.bucket -Prefix $S3Prefix

if ($s3Objects -match $backupFile.Name) {
    Write-LogSuccess "Archivo verificado en Object Storage"
}
else {
    Write-LogWarning "No se pudo verificar el archivo en Object Storage"
}

# Generar metadata del backup
$metadataPath = "$BackupPath.meta.json"
$metadata = @{
    UploadDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    FileName       = $backupFile.Name
    SizeGB         = $backupSizeGB
    MD5            = $md5Hash.Hash
    S3Bucket       = $s3Config.bucket
    S3Key          = $s3Key
    S3Endpoint     = $s3Config.endpoint
    SourceHostname = $env:COMPUTERNAME
    SourceIP       = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
}

$metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath $metadataPath -Encoding UTF8
Write-LogInfo "Metadata guardada en: $metadataPath"

# Subir metadata también
$metadataS3Key = "$s3Key.meta.json"
Write-LogInfo "Subiendo metadata..."
Send-FileToS3 `
    -FilePath $metadataPath `
    -Endpoint $s3Config.endpoint `
    -Bucket $s3Config.bucket `
    -S3Key $metadataS3Key | Out-Null

# Eliminar backup local si se solicita
if ($DeleteAfterUpload) {
    Write-LogWarning "Eliminando backup local..."
    
    try {
        Remove-Item -Path $BackupPath -Force
        Write-LogInfo "Backup local eliminado: $BackupPath"
        
        # Eliminar directorio del backup si existe
        $backupDir = $BackupPath -replace '\.zip$', ''
        if (Test-Path $backupDir) {
            Remove-Item -Path $backupDir -Recurse -Force
            Write-LogInfo "Directorio de backup eliminado: $backupDir"
        }
    }
    catch {
        Write-LogError "Error eliminando backup local: $_"
    }
}

Write-LogInfo ""
Write-LogSuccess "========================================"
Write-LogSuccess "Upload completado exitosamente"
Write-LogSuccess "========================================"
Write-LogInfo ""
Write-LogInfo "Información del backup en Object Storage:"
Write-LogInfo "  - Bucket: $($s3Config.bucket)"
Write-LogInfo "  - Key: $s3Key"
Write-LogInfo "  - Endpoint: https://$($s3Config.endpoint)"
Write-LogInfo "  - Tamaño: $backupSizeGB GB"
Write-LogInfo "  - MD5: $($md5Hash.Hash)"
Write-LogInfo ""
Write-LogInfo "Para descargar el backup en otra VPS, use:"
Write-LogInfo "  .\Download-FromObjectStorage.ps1 -S3Key '$s3Key'"
Write-LogInfo ""

# Retornar información
return @{
    Success    = $true
    S3Bucket   = $s3Config.bucket
    S3Key      = $s3Key
    S3Endpoint = $s3Config.endpoint
    SizeGB     = $backupSizeGB
    MD5        = $md5Hash.Hash
}
