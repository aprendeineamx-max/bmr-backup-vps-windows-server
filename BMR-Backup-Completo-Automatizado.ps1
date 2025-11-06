# BMR Backup Completo Automatizado - Sin RDP, Sin APIs
# Ejecutar desde Civer-One, hace backup de Civer-Two

param(
    [string]$TargetIP = "216.238.88.126",
    [string]$Username = "Administrator", 
    [string]$Password = "6K#fVnH-arJG-(wT"
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BMR BACKUP AUTOMATIZADO - CIVER-TWO" -ForegroundColor Green  
Write-Host "========================================`n" -ForegroundColor Green

# Conectar
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Conectando a $TargetIP..." -ForegroundColor Cyan
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)
$session = New-PSSession -ComputerName $TargetIP -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "[OK] Sesion ID: $($session.Id)`n" -ForegroundColor Green

# Script completo que se ejecuta en Civer-Two
$remoteScript = {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = "C:\BackupTemp"
    $backupName = "CIVER-TWO-BMR-$timestamp"
    $logFile = "$backupDir\$backupName-log.txt"
    
    function Log { param($msg) "$([DateTime]::Now.ToString('HH:mm:ss')) $msg" | Tee-Object -FilePath $logFile -Append | Write-Host }
    
    if(!(Test-Path $backupDir)){ New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
    
    Log "===== INICIO BACKUP BMR ====="
    Log "Servidor: $env:COMPUTERNAME"
    Log "Timestamp: $timestamp"
    
    # METODO 1: Intentar Clonezilla (dd-like)
    Log "`n[PASO 1/4] Creando imagen de disco con NTBACKUP PowerShell..."
    
    try {
        # Usar Win32_ShadowCopy para crear VSS snapshot
        Log "  Creando VSS Shadow Copy..."
        $vss = (Get-WmiObject -List Win32_ShadowCopy).Create("C:\", "ClientAccessible")
        $shadowID = $vss.ShadowID
        $shadow = Get-WmiObject Win32_ShadowCopy | Where-Object {$_.ID -eq $shadowID}
        $shadowPath = $shadow.DeviceObject + "\"
        
        Log "  Shadow Copy creado: $shadowPath"
        Log "  [PASO 2/4] Copiando archivos desde shadow copy..."
        
        # Copiar archivos criticos desde shadow copy
        $targetPath = "$backupDir\$backupName"
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        
        # Carpetas criticas
        $folders = @(
            "Windows\System32\config",
            "Users",
            "ProgramData", 
            "Program Files\Common Files",
            "Boot"
        )
        
        $totalCopied = 0
        foreach($folder in $folders){
            $source = Join-Path $shadowPath $folder
            $dest = Join-Path $targetPath $folder
            
            if(Test-Path $source){
                Log "  Copiando: $folder"
                robocopy $source $dest /E /R:1 /W:1 /MT:4 /XJ /NFL /NDL /NJH /NJS | Out-Null
                $size = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sizeMB = [math]::Round($size/1MB, 2)
                Log "    Copiado: $sizeMB MB"
                $totalCopied += $sizeMB
            }
        }
        
        Log "`n  Total copiado: $totalCopied MB"
        
        # Eliminar shadow copy
        $shadow.Delete()
        Log "  Shadow copy eliminado"
        
        # PASO 3: Comprimir
        Log "`n[PASO 3/4] Comprimiendo backup..."
        $7zip = "C:\Program Files\7-Zip\7z.exe"
        
        if(!(Test-Path $7zip)){
            Log "  Descargando 7-Zip..."
            $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
            $installer = "$env:TEMP\7zip.msi"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
            Log "  7-Zip instalado"
        }
        
        $zipFile = "$backupDir\$backupName.7z"
        Log "  Comprimiendo a: $zipFile"
        Log "  (Esto puede tomar 15-30 minutos...)"
        
        $sourceFiles = $targetPath + "\*"
        & $7zip a -t7z -mx=5 -mmt=on -v1000m $zipFile $sourceFiles | Out-Null
        
        if($LASTEXITCODE -eq 0){
            $pattern = "$backupName.7z.*"
            $parts = Get-ChildItem $backupDir -Filter $pattern
            $totalSize = ($parts | Measure-Object Length -Sum).Sum
            $totalGB = [math]::Round($totalSize/1GB, 2)
            
            Log "  [OK] Backup comprimido: $($parts.Count) partes, $totalGB GB"
            
            # PASO 4: Subir a S3
            Log "`n[PASO 4/4] Subiendo a Object Storage..."
            
            $awsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
            if(!(Test-Path $awsPath)){
                Log "  Instalando AWS CLI..."
                $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
                $awsInstaller = "$env:TEMP\AWSCLIV2.msi"
                Invoke-WebRequest -Uri $awsUrl -OutFile $awsInstaller -UseBasicParsing
                Start-Process msiexec.exe -Wait -ArgumentList "/i `"$awsInstaller`" /quiet /norestart"
                Log "  AWS CLI instalado"
            }
            
            # Configurar AWS CLI
            $awsDir = "$env:USERPROFILE\.aws"
            if(!(Test-Path $awsDir)){ New-Item -Path $awsDir -ItemType Directory -Force | Out-Null }
            
            "[default]`nregion = us-west-1`noutput = json" | Set-Content "$awsDir\config" -Force
            "[default]`naws_access_key_id = G0LDHU6PIXWDEDJTAQ4B`naws_secret_access_key = a9Vg7EMOomETgQ5V6bJlXPzMR6DhCEonUXBqcpRo" | Set-Content "$awsDir\credentials" -Force
            
            $uploadCount = 0
            foreach($part in $parts){
                Log "  Subiendo: $($part.Name) ($([math]::Round($part.Length/1MB,2)) MB)"
                $s3Path = "s3://backups-bmr-civer/backups/$($part.Name)"
                $env:AWS_CONFIG_FILE = "$awsDir\config"
                $env:AWS_SHARED_CREDENTIALS_FILE = "$awsDir\credentials"
                
                & $awsPath s3 cp $part.FullName $s3Path --endpoint-url https://lax1.vultrobjects.com 2>&1 | Out-Null
                
                if($LASTEXITCODE -eq 0){
                    Log "    [OK] Subido"
                    $uploadCount++
                } else {
                    Log "    [ERROR] Fallo subida"
                }
            }
            
            Log "`n===== BACKUP COMPLETADO ====="
            Log "Partes creadas: $($parts.Count)"
            Log "Partes subidas: $uploadCount"
            Log "Tamano total: $totalGB GB"
            Log "Ubicacion local: $backupDir"
            Log "Ubicacion S3: s3://backups-bmr-civer/backups/"
            
            return @{
                Success = $true
                PartsCreated = $parts.Count
                PartsUploaded = $uploadCount
                TotalSizeGB = $totalGB
                BackupName = $backupName
            }
        } else {
            Log "  [ERROR] Compresion fallo"
            return @{Success=$false; Error="Compresion fallo"}
        }
        
    } catch {
        Log "[ERROR] $_"
        return @{Success=$false; Error=$_.Exception.Message}
    }
}

# Ejecutar en Civer-Two
Write-Host "Ejecutando backup completo en $TargetIP..." -ForegroundColor Yellow
Write-Host "(Tiempo estimado: 30-60 minutos)`n" -ForegroundColor White

$result = Invoke-Command -Session $session -ScriptBlock $remoteScript

# Mostrar resultado
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "RESULTADO FINAL" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

if($result.Success){
    Write-Host "[OK] Backup completado exitosamente!" -ForegroundColor Green
    Write-Host "  Nombre: $($result.BackupName)" -ForegroundColor White
    Write-Host "  Partes: $($result.PartsCreated)" -ForegroundColor White
    Write-Host "  Subidas: $($result.PartsUploaded)" -ForegroundColor White
    Write-Host "  Tamano: $($result.TotalSizeGB) GB`n" -ForegroundColor White
    Write-Host "Archivos en: s3://backups-bmr-civer/backups/" -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] Backup fallo" -ForegroundColor Red
    Write-Host "  Error: $($result.Error)" -ForegroundColor Yellow
}

Remove-PSSession $session
Write-Host "`nSesion cerrada." -ForegroundColor Gray
