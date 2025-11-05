# Script para ejecutar backup BMR - Versión todo en uno
# Ejecutar desde: C:\Users\Public\BMR-Backup-VPS

Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   BACKUP BMR - Proceso Completo" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Cargar config
$config = Get-Content ".\config\credentials.json" -Raw | ConvertFrom-Json
$vps = $config.vpsOrigen

Write-Host "VPS Origen: $($vps.name) ($($vps.ip))" -ForegroundColor Green

# 2. Crear credenciales
$secPass = ConvertTo-SecureString $vps.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($vps.username, $secPass)

# 3. Conectar
Write-Host "Conectando a VPS..." -ForegroundColor Yellow
$session = New-PSSession -ComputerName $vps.ip -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "✓ Conectado`n" -ForegroundColor Green

# 4. Ejecutar backup en VPS
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "CREANDO BACKUP BMR EN VPS REMOTA" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "NOTA: Este proceso puede tardar 20-40 minutos" -ForegroundColor Yellow
Write-Host "      No cierre esta ventana`n" -ForegroundColor Yellow

$result = Invoke-Command -Session $session -ScriptBlock {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "BMR-CIVER-ONE-$timestamp"
    $backupTarget = "C:\BackupTemp\$backupName"
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creando directorio de backup..."
    New-Item -Path $backupTarget -ItemType Directory -Force | Out-Null
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Iniciando wbadmin (Windows Server Backup)..."
    Write-Host "                                Volumen: C:"
    Write-Host "                                Destino: $backupTarget"
    Write-Host ""
    
    # Ejecutar wbadmin
    $wbResult = wbadmin start backup -backupTarget:$backupTarget -include:C: -allCritical -quiet 2>&1
    
    if($LASTEXITCODE -eq 0){
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] ✓ Backup completado exitosamente!" -ForegroundColor Green
        
        # Obtener tamaño
        $files = Get-ChildItem $backupTarget -Recurse -ErrorAction SilentlyContinue
        $sizeGB = [math]::Round(($files | Measure-Object Length -Sum).Sum/1GB, 2)
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Tamaño del backup: $sizeGB GB" -ForegroundColor Cyan
        
        return @{
            Success = $true
            Path = $backupTarget
            SizeGB = $sizeGB
            Name = $backupName
        }
    }else{
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] ✗ Error en el backup" -ForegroundColor Red
        Write-Host $wbResult
        return @{Success = $false; Error = "wbadmin failed"}
    }
}

if($result.Success){
    Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "BACKUP CREADO EXITOSAMENTE" -ForegroundColor Green
    Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green
    
    Write-Host "Información del backup:" -ForegroundColor Cyan
    Write-Host "  - Nombre: $($result.Name)" -ForegroundColor White
    Write-Host "  - Ubicación en VPS: $($result.Path)" -ForegroundColor White
    Write-Host "  - Tamaño: $($result.SizeGB) GB" -ForegroundColor White
    
    Write-Host "`n¿Desea comprimir y subir a Object Storage ahora? (S/N): " -ForegroundColor Yellow -NoNewline
    $upload = Read-Host
    
    if($upload -eq 'S'){
        Write-Host "`nComprimiendo y subiendo a Object Storage..." -ForegroundColor Cyan
        Write-Host "NOTA: Este proceso puede tardar 30-60 minutos`n" -ForegroundColor Yellow
        
        $s3Config = $config.objectStorage
        
        $uploadResult = Invoke-Command -Session $session -ScriptBlock {
            param($backupPath, $endpoint, $bucket, $accessKey, $secretKey)
            
            # Comprimir
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Comprimiendo backup..."
            $zipPath = "$backupPath.zip"
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory(
                $backupPath,
                $zipPath,
                [System.IO.Compression.CompressionLevel]::Optimal,
                $false
            )
            
            $zipSize = [math]::Round((Get-Item $zipPath).Length/1GB, 2)
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✓ ZIP creado: $zipSize GB" -ForegroundColor Green
            
            # Configurar AWS
            $env:AWS_ACCESS_KEY_ID = $accessKey
            $env:AWS_SECRET_ACCESS_KEY = $secretKey
            
            # Subir a S3
            $fileName = Split-Path $zipPath -Leaf
            $s3Key = "bmr-backups/$fileName"
            
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Subiendo a Object Storage..."
            Write-Host "                                s3://$bucket/$s3Key"
            
            aws s3 cp $zipPath "s3://$bucket/$s3Key" --endpoint-url "https://$endpoint"
            
            if($LASTEXITCODE -eq 0){
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✓ Upload completado!" -ForegroundColor Green
                return @{Success=$true; S3Key=$s3Key; ZipSize=$zipSize}
            }else{
                return @{Success=$false}
            }
        } -ArgumentList $result.Path, $s3Config.endpoint, $s3Config.bucket, $s3Config.accessKey, $s3Config.secretKey
        
        if($uploadResult.Success){
            Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Green
            Write-Host "PROCESO COMPLETADO EXITOSAMENTE" -ForegroundColor Green
            Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green
            
            Write-Host "Backup disponible en Object Storage:" -ForegroundColor Cyan
            Write-Host "  - Bucket: $($s3Config.bucket)" -ForegroundColor White
            Write-Host "  - Key: $($uploadResult.S3Key)" -ForegroundColor White
            Write-Host "  - Tamaño: $($uploadResult.ZipSize) GB" -ForegroundColor White
            
            Write-Host "`nPara restaurar en VPS destino, use:" -ForegroundColor Yellow
            Write-Host "  .\Restore-FromS3.ps1 -S3Key '$($uploadResult.S3Key)'" -ForegroundColor Cyan
        }
    }
}

# Limpiar
Remove-PSSession $session
Write-Host "`n✓ Sesión remota cerrada" -ForegroundColor Green
