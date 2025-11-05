<#
.SYNOPSIS
    Descarga un backup BMR desde Vultr Object Storage.

.DESCRIPTION
    Transfiere el archivo de backup desde Object Storage a la VPS local
    para preparar la restauración.

.PARAMETER S3Key
    Clave (path) del archivo en Object Storage.

.PARAMETER DestinationPath
    Ruta local donde descargar el backup.

.PARAMETER ConfigPath
    Ruta del archivo de configuración con credenciales.

.EXAMPLE
    .\Download-FromObjectStorage.ps1 -S3Key "bmr-backups/BMR-Backup-Server1-20250104.zip"

.NOTES
    Requiere AWS CLI instalado y configurado.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$S3Key,
    
    [string]$DestinationPath = "C:\BackupTemp",
    
    [string]$ConfigPath = "..\..\config\credentials.json",
    
    [switch]$VerifyChecksum,
    
    [switch]$AutoExtract
)

# Importar utilidades
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "..\utils\Logger.ps1")
. (Join-Path $scriptPath "..\utils\S3-Helper.ps1")

Initialize-Logger -LogName "download-backup"

Write-LogInfo "========================================"
Write-LogInfo "Descargando Backup desde Object Storage"
Write-LogInfo "========================================"

# Crear directorio de destino si no existe
if (-not (Test-Path $DestinationPath)) {
    Write-LogInfo "Creando directorio de destino: $DestinationPath"
    New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
}

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

# Verificar herramientas S3
Write-LogInfo "Verificando herramientas S3..."
$tools = Test-S3Tools

if (-not $tools.HasAny) {
    Write-LogWarning "AWS CLI no encontrado. Instalando..."
    if (-not (Install-AWSCLI)) {
        Write-LogError "No se pudo instalar AWS CLI"
        exit 1
    }
    
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
}

# Configurar credenciales S3
Write-LogInfo "Configurando credenciales S3..."
Initialize-S3Config -S3Config @{
    accessKey = $s3Config.accessKey
    secretKey = $s3Config.secretKey
    region    = $s3Config.region
}

# Verificar que el archivo existe en S3
Write-LogInfo "Verificando archivo en Object Storage..."
$s3Objects = Get-S3Objects -Endpoint $s3Config.endpoint -Bucket $s3Config.bucket -Prefix (Split-Path $S3Key -Parent)

$fileName = Split-Path $S3Key -Leaf
if (-not ($s3Objects -match $fileName)) {
    Write-LogError "Archivo no encontrado en Object Storage: $S3Key"
    Write-LogInfo "Archivos disponibles:"
    $s3Objects | ForEach-Object { Write-LogInfo "  - $_" }
    exit 1
}

Write-LogSuccess "Archivo encontrado en Object Storage"

# Preparar ruta de descarga
$downloadPath = Join-Path $DestinationPath $fileName

Write-LogInfo ""
Write-LogInfo "Iniciando descarga..."
Write-LogInfo "  - Origen: s3://$($s3Config.bucket)/$S3Key"
Write-LogInfo "  - Destino: $downloadPath"
Write-LogInfo ""
Write-LogWarning "Esta operación puede tardar 20-40 minutos dependiendo del tamaño y el ancho de banda"
Write-LogInfo ""

# Descargar metadata primero si existe
$metadataS3Key = "$S3Key.meta.json"
$metadataPath = "$downloadPath.meta.json"

Write-LogInfo "Intentando descargar metadata..."
$metadataDownloaded = Get-FileFromS3 `
    -S3Key $metadataS3Key `
    -Endpoint $s3Config.endpoint `
    -Bucket $s3Config.bucket `
    -DestinationPath $metadataPath

if ($metadataDownloaded -and (Test-Path $metadataPath)) {
    $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
    Write-LogSuccess "Metadata descargada"
    Write-LogInfo "  - Tamaño original: $($metadata.SizeGB) GB"
    Write-LogInfo "  - MD5: $($metadata.MD5)"
    Write-LogInfo "  - Hostname origen: $($metadata.SourceHostname)"
    Write-LogInfo "  - Fecha de upload: $($metadata.UploadDate)"
}

# Descargar archivo principal
$downloadSuccess = Get-FileFromS3 `
    -S3Key $S3Key `
    -Endpoint $s3Config.endpoint `
    -Bucket $s3Config.bucket `
    -DestinationPath $downloadPath `
    -ShowProgress

if (-not $downloadSuccess) {
    Write-LogError "Error descargando archivo desde Object Storage"
    exit 1
}

Write-LogSuccess "Archivo descargado correctamente"

# Verificar checksum si se solicitó
if ($VerifyChecksum -and $metadata) {
    Write-LogInfo "Verificando integridad del archivo..."
    
    $downloadedHash = Get-FileHash -Path $downloadPath -Algorithm MD5
    
    if ($downloadedHash.Hash -eq $metadata.MD5) {
        Write-LogSuccess "Checksum verificado correctamente"
    }
    else {
        Write-LogError "Checksum no coincide!"
        Write-LogError "  - Esperado: $($metadata.MD5)"
        Write-LogError "  - Obtenido: $($downloadedHash.Hash)"
        Write-LogError "El archivo puede estar corrupto"
        exit 1
    }
}

# Verificar espacio en disco
$downloadedFile = Get-Item $downloadPath
$downloadedSizeGB = [math]::Round($downloadedFile.Length / 1GB, 2)

Write-LogInfo "Archivo descargado:"
Write-LogInfo "  - Tamaño: $downloadedSizeGB GB"
Write-LogInfo "  - Ubicación: $downloadPath"

# Extraer archivo ZIP si se solicitó
if ($AutoExtract -and $fileName -match '\.zip$') {
    Write-LogInfo "Extrayendo archivo ZIP..."
    
    $extractPath = $downloadPath -replace '\.zip$', ''
    
    if (Test-Path $extractPath) {
        Write-LogWarning "Directorio de extracción ya existe: $extractPath"
        Write-LogWarning "Eliminando contenido previo..."
        Remove-Item -Path $extractPath -Recurse -Force
    }
    
    try {
        Write-LogInfo "Destino de extracción: $extractPath"
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $extractPath)
        
        Write-LogSuccess "Archivo extraído correctamente"
        Write-LogInfo "Ubicación: $extractPath"
        
        # Listar contenido
        $extractedFiles = Get-ChildItem -Path $extractPath -Recurse
        Write-LogInfo "Archivos extraídos: $($extractedFiles.Count)"
        
        return @{
            Success      = $true
            DownloadPath = $downloadPath
            ExtractPath  = $extractPath
            SizeGB       = $downloadedSizeGB
        }
    }
    catch {
        Write-LogError "Error extrayendo archivo: $_"
        Write-LogWarning "El archivo ZIP se descargó pero no se pudo extraer"
    }
}

Write-LogInfo ""
Write-LogSuccess "========================================"
Write-LogSuccess "Descarga completada exitosamente"
Write-LogSuccess "========================================"
Write-LogInfo ""
Write-LogInfo "Archivo descargado: $downloadPath"
Write-LogInfo ""
Write-LogInfo "Próximos pasos:"
if ($fileName -match '\.zip$' -and -not $AutoExtract) {
    Write-LogInfo "  1. Extraer el archivo ZIP"
    Write-LogInfo "  2. Ejecutar Restore-BMRBackup.ps1 para restaurar"
}
else {
    Write-LogInfo "  1. Ejecutar Restore-BMRBackup.ps1 para restaurar el sistema"
}
Write-LogInfo ""

# Retornar información
return @{
    Success      = $true
    DownloadPath = $downloadPath
    SizeGB       = $downloadedSizeGB
}
