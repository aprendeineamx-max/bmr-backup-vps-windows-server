# Backup VPS Local - Version Simplificada
# Ejecutar como Administrador

param([switch]$SkipUpload)

$ErrorActionPreference = "Continue"
Write-Host "`n========================================"  -ForegroundColor Green
Write-Host "BACKUP VPS - EJECUCION LOCAL" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Configuracion
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$computerName = $env:COMPUTERNAME
$backupName = "$computerName-BACKUP-$timestamp"
$workDir = "C:\BackupTemp\$backupName"
$logFile = "$workDir\backup.log"

# Crear directorio
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Preparando entorno..." -ForegroundColor Cyan
if(!(Test-Path $workDir)){
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    Write-Host "  [OK] Directorio creado: $workDir" -ForegroundColor Green
}

# Log
"Backup iniciado: $(Get-Date)" | Out-File $logFile

# Carpetas a respaldar
$folders = @(
    @{Path="C:\Users"; Name="Users"},
    @{Path="C:\ProgramData"; Name="ProgramData"},
    @{Path="C:\Program Files\Common Files"; Name="ProgramFilesCommon"},
    @{Path="C:\Windows\System32\config"; Name="SystemConfig"}
)

# Respaldar carpetas
$successCount = 0
foreach($folder in $folders){
    $sourcePath = $folder.Path
    $folderName = $folder.Name
    
    if(!(Test-Path $sourcePath)){
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] [!] Carpeta no existe: $sourcePath" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Respaldando: $folderName" -ForegroundColor Cyan
    $destPath = Join-Path $workDir $folderName
    
    try {
        $robocopyLog = Join-Path $workDir "robocopy_$folderName.log"
        Write-Host "  Copiando archivos..." -ForegroundColor Gray
        
        robocopy $sourcePath $destPath /E /R:2 /W:5 /MT:4 /XJ /XD "*\AppData\Local\Temp" "*\Downloads" "*\Temporary Internet Files" /LOG:$robocopyLog /NP | Out-Null
        
        if(Test-Path $destPath){
            $size = (Get-ChildItem $destPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size/1MB, 2)
            Write-Host "  [OK] Copiado: $sizeMB MB" -ForegroundColor Green
            "Carpeta $folderName copiada: $sizeMB MB" | Out-File $logFile -Append
            $successCount++
        }
    } catch {
        Write-Host "  [X] Error: $_" -ForegroundColor Red
    }
}

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Resumen: $successCount de $($folders.Count) carpetas respaldadas" -ForegroundColor White

# Comprimir
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Comprimiendo backup..." -ForegroundColor Cyan
$7zipPath = "C:\Program Files\7-Zip\7z.exe"

if(!(Test-Path $7zipPath)){
    Write-Host "  [!] 7-Zip no instalado. Descargando..." -ForegroundColor Yellow
    $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
    $installer = "$env:TEMP\7zip.msi"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
        Write-Host "  [OK] 7-Zip instalado" -ForegroundColor Green
    } catch {
        Write-Host "  [X] No se pudo instalar 7-Zip" -ForegroundColor Red
        $7zipPath = $null
    }
}

if($7zipPath -and (Test-Path $7zipPath)){
    $zipFile = "C:\BackupTemp\$backupName.7z"
    Write-Host "  Archivo: $zipFile" -ForegroundColor Gray
    Write-Host "  Dividiendo en partes de 1GB..." -ForegroundColor Gray
    
    $sourceDir = $workDir + "\*"
    & $7zipPath a -t7z -mx=3 -mmt=on -v1g $zipFile $sourceDir | Out-Null
    
    if($LASTEXITCODE -eq 0){
        $pattern = $backupName + ".7z.*"
        $parts = Get-ChildItem "C:\BackupTemp\$pattern" -ErrorAction SilentlyContinue
        if($parts){
            Write-Host "  [OK] Backup comprimido en $($parts.Count) partes" -ForegroundColor Green
            foreach($part in $parts){
                $partSize = [math]::Round($part.Length/1MB, 2)
                Write-Host "    - $($part.Name): $partSize MB" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "  [!] Compresion fallo" -ForegroundColor Yellow
    }
}

# Subir a Object Storage
if(!$SkipUpload){
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Subiendo a Object Storage..." -ForegroundColor Cyan
    
    $awsDir = "$env:USERPROFILE\.aws"
    if(!(Test-Path $awsDir)){
        New-Item -Path $awsDir -ItemType Directory -Force | Out-Null
    }
    
    $configFile = Join-Path $awsDir "config"
    $credFile = Join-Path $awsDir "credentials"
    
    "[default]`nregion = us-west-1`noutput = json" | Set-Content $configFile -Force
    "[default]`naws_access_key_id = G0LDHU6PIXWDEDJTAQ4B`naws_secret_access_key = a9Vg7EMOomETgQ5V6bJlXPzMR6DhCEonUXBqcpRo" | Set-Content $credFile -Force
    
    $awsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    
    if(Test-Path $awsPath){
        Write-Host "  [OK] AWS CLI configurado" -ForegroundColor Green
        
        $pattern = $backupName + ".7z.*"
        $parts = Get-ChildItem "C:\BackupTemp\$pattern" -ErrorAction SilentlyContinue
        if($parts){
            foreach($part in $parts){
                Write-Host "  Subiendo: $($part.Name)" -ForegroundColor Gray
                $s3Path = "s3://backups-bmr-civer/backups/$($part.Name)"
                & $awsPath s3 cp $part.FullName $s3Path --endpoint-url https://lax1.vultrobjects.com
                if($LASTEXITCODE -eq 0){
                    Write-Host "  [OK] Subido: $($part.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  [X] Error al subir: $($part.Name)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  [!] No hay partes comprimidas. Subiendo carpeta completa..." -ForegroundColor Yellow
            $s3Path = "s3://backups-bmr-civer/backups/$backupName/"
            & $awsPath s3 sync $workDir $s3Path --endpoint-url https://lax1.vultrobjects.com
        }
    } else {
        Write-Host "  [!] AWS CLI no instalado" -ForegroundColor Yellow
        Write-Host "  Descarga: https://awscli.amazonaws.com/AWSCLIV2.msi" -ForegroundColor Cyan
    }
} else {
    Write-Host "`n[!] Subida omitida (-SkipUpload)" -ForegroundColor Yellow
}

# Resumen
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BACKUP COMPLETADO" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Ubicacion local:" -ForegroundColor White
Write-Host "  $workDir`n" -ForegroundColor Cyan

$pattern = $backupName + ".7z.*"
$parts = Get-ChildItem "C:\BackupTemp\$pattern" -ErrorAction SilentlyContinue
if($parts){
    $totalSize = ($parts | Measure-Object -Property Length -Sum).Sum
    $totalGB = [math]::Round($totalSize/1GB, 2)
    Write-Host "Tamano total: $totalGB GB`n" -ForegroundColor White
}

Write-Host "Log: $logFile" -ForegroundColor Cyan

"Backup completado: $(Get-Date)" | Out-File $logFile -Append
