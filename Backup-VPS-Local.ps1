<#
.SYNOPSIS
    Script de Backup VPS - Ejecutar LOCALMENTE en el servidor origen
    
.DESCRIPTION
    Crea backup incremental de carpetas críticas y lo sube a Vultr Object Storage
    NO requiere disco externo ni herramientas especiales
    
.EXAMPLE
    .\Backup-VPS-Local.ps1
#>

param(
    [switch]$SkipUpload
)

$ErrorActionPreference = "Continue"

# Colores
function Write-Step { param($msg) Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Cyan }
function Write-OK { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "  [X] $msg" -ForegroundColor Red }

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "   BACKUP VPS - EJECUCIÓN LOCAL" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Configuración
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "$env:COMPUTERNAME-BACKUP-$timestamp"
$workDir = "C:\BackupTemp\$backupName"
$logFile = "$workDir\backup.log"

# Carpetas críticas a respaldar
$foldersToBackup = @(
    @{Path="C:\Users"; Name="Users"; Size="Variable"},
    @{Path="C:\ProgramData"; Name="ProgramData"; Size="~5GB"},
    @{Path="C:\Program Files\Common Files"; Name="ProgramFilesCommon"; Size="~2GB"},
    @{Path="C:\Windows\System32\config"; Name="SystemConfig"; Size="~100MB"}
)

# Crear directorio de trabajo
Write-Step "Preparando entorno..."
if(!(Test-Path $workDir)){
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    Write-OK "Directorio creado: $workDir"
} else {
    Write-OK "Usando directorio existente"
}

# Crear log
"Backup iniciado: $(Get-Date)" | Out-File $logFile

# Función para crear backup de una carpeta
function Backup-Folder {
    param($FolderPath, $FolderName)
    
    if(!(Test-Path $FolderPath)){
        Write-Warn "Carpeta no existe: $FolderPath"
        return $false
    }
    
    Write-Step "Respaldando: $FolderName"
    $destPath = "$workDir\$FolderName"
    
    try {
        # Usar robocopy (más eficiente que Copy-Item)
        $robocopyLog = "$workDir\robocopy_$FolderName.log"
        Write-Host "  Copiando archivos..." -ForegroundColor Gray
        
        robocopy $FolderPath $destPath /E /R:2 /W:5 /MT:4 /XJ /XD "*\AppData\Local\Temp" "*\Downloads" "*\Temporary Internet Files" /LOG:$robocopyLog /NP | Out-Null
        
        if(Test-Path $destPath){
            $size = (Get-ChildItem $destPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size/1MB, 2)
            Write-OK "Copiado: $sizeMB MB"
            "Carpeta ${FolderName}: $sizeMB MB" | Out-File $logFile -Append
            return $true
        } else {
            Write-Err "Fallo al copiar carpeta"
            return $false
        }
    } catch {
        Write-Err "Error: $_"
        return $false
    }
}

# Respaldar cada carpeta
$successCount = 0
foreach($folder in $foldersToBackup){
    if(Backup-Folder -FolderPath $folder.Path -FolderName $folder.Name){
        $successCount++
    }
}

Write-Step "Resumen de carpetas respaldadas"
Write-Host "  Total: $successCount de $($foldersToBackup.Count)" -ForegroundColor White

# Comprimir en partes
Write-Step "Comprimiendo backup..."
$7zipPath = "C:\Program Files\7-Zip\7z.exe"

if(!(Test-Path $7zipPath)){
    Write-Warn "7-Zip no instalado. Descargando..."
    $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
    $installer = "$env:TEMP\7zip.msi"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
        Write-OK "7-Zip instalado"
    } catch {
        Write-Err "No se pudo instalar 7-Zip. Omitiendo compresión."
        $7zipPath = $null
    }
}

if($7zipPath -and (Test-Path $7zipPath)){
    $zipFile = "C:\BackupTemp\$backupName.7z"
    Write-Host "  Archivo: $zipFile" -ForegroundColor Gray
    Write-Host "  Compresión: Media (más rápido)" -ForegroundColor Gray
    Write-Host "  Dividiendo en partes de 1GB..." -ForegroundColor Yellow
    
    # Comprimir en partes de 1GB para facilitar subida
    & $7zipPath a -t7z -mx=3 -mmt=on -v1g $zipFile "$workDir\*" | Out-Null
    
    if($LASTEXITCODE -eq 0){
        $parts = Get-ChildItem "C:\BackupTemp\$backupName.7z.*"
        Write-OK "Backup comprimido en $($parts.Count) partes"
        $parts | ForEach-Object {
            $partSize = [math]::Round($_.Length/1MB, 2)
            Write-Host "    - $($_.Name): $partSize MB" -ForegroundColor Gray
        }
    } else {
        Write-Warn "Compresión falló, pero archivos sin comprimir están disponibles"
    }
}

# Subir a Object Storage
if(!$SkipUpload){
    Write-Step "Subiendo a Object Storage..."
    
    # Configurar AWS CLI
    $awsDir = "$env:USERPROFILE\.aws"
    if(!(Test-Path $awsDir)){
        New-Item -Path $awsDir -ItemType Directory -Force | Out-Null
    }
    
    $configContent = @"
[default]
region = us-west-1
output = json
"@
    
    $credentialsContent = @"
[default]
aws_access_key_id = G0LDHU6PIXWDEDJTAQ4B
aws_secret_access_key = a9Vg7EMOomETgQ5V6bJlXPzMR6DhCEonUXBqcpRo
"@
    
    Set-Content -Path "$awsDir\config" -Value $configContent -Force
    Set-Content -Path "$awsDir\credentials" -Value $credentialsContent -Force
    
    $awsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    
    if(Test-Path $awsPath){
        Write-OK "AWS CLI configurado"
        
        # Subir cada parte
        $parts = Get-ChildItem "C:\BackupTemp\$backupName.7z.*" -ErrorAction SilentlyContinue
        if($parts){
            foreach($part in $parts){
                Write-Host "  Subiendo: $($part.Name)" -ForegroundColor Gray
                & $awsPath s3 cp $part.FullName "s3://backups-bmr-civer/backups/$($part.Name)" --endpoint-url https://lax1.vultrobjects.com
                if($LASTEXITCODE -eq 0){
                    Write-OK "Subido: $($part.Name)"
                } else {
                    Write-Err "Error al subir: $($part.Name)"
                }
            }
        } else {
            Write-Warn "No hay partes comprimidas. Subiendo carpeta completa..."
            & $awsPath s3 sync $workDir "s3://backups-bmr-civer/backups/$backupName/" --endpoint-url https://lax1.vultrobjects.com
        }
    } else {
        Write-Warn "AWS CLI no instalado. Instálalo para subir automáticamente"
        Write-Host "`n  Descarga: https://awscli.amazonaws.com/AWSCLIV2.msi" -ForegroundColor Cyan
    }
} else {
    Write-Warn "Subida omitida (-SkipUpload)"
}

# Resumen final
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "   BACKUP COMPLETADO" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Ubicación local:" -ForegroundColor White
Write-Host "  $workDir`n" -ForegroundColor Cyan

$totalSize = (Get-ChildItem "C:\BackupTemp\$backupName.7z.*" -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
if($totalSize -gt 0){
    $totalGB = [math]::Round($totalSize/1GB, 2)
    Write-Host "Tamaño total: $totalGB GB" -ForegroundColor White
}

Write-Host "`nPara restaurar:" -ForegroundColor Yellow
Write-Host "  1. Descargar partes desde Object Storage" -ForegroundColor Gray
Write-Host "  2. Combinar: 7z x $backupName.7z.001" -ForegroundColor Gray
Write-Host "  3. Copiar archivos a ubicaciones originales`n" -ForegroundColor Gray

"Backup completado: $(Get-Date)" | Out-File $logFile -Append
Write-Host "Log: $logFile" -ForegroundColor Cyan
