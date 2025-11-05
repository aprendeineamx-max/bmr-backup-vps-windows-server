# GUÍA RÁPIDA: Backup BMR Manual
# ===============================

## OPCIÓN 1: Ejecutar desde tu PC (Recomendado)

### Paso 1: Conectarse a la VPS
```powershell
cd "C:\Users\Public\BMR-Backup-VPS"
$config = Get-Content ".\config\credentials.json" -Raw | ConvertFrom-Json
$vps = $config.vpsOrigen
$pass = ConvertTo-SecureString $vps.password -AsPlainText -Force
$cred = New-Object PSCredential($vps.username, $pass)
Enter-PSSession -ComputerName $vps.ip -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
```

### Paso 2: Una vez conectado, ejecutar en la VPS:
```powershell
# Crear backup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "C:\BackupTemp\BMR-CIVER-$timestamp"
New-Item -Path $backupPath -ItemType Directory -Force

# Ejecutar Windows Server Backup
wbadmin start backup -backupTarget:$backupPath -include:C: -allCritical -quiet

# Verificar
Get-ChildItem $backupPath -Recurse | Measure-Object -Property Length -Sum
```

### Paso 3: Comprimir (opcional pero recomendado)
```powershell
$zipPath = "$backupPath.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($backupPath, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
```

### Paso 4: Subir a Object Storage
```powershell
# Configurar AWS CLI
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"

# Subir
$fileName = Split-Path $zipPath -Leaf
aws s3 cp $zipPath "s3://backups-bmr-civer/bmr-backups/$fileName" --endpoint-url https://lax1.vultrobjects.com
```

### Paso 5: Salir de la sesión
```powershell
Exit-PSSession
```

---

## OPCIÓN 2: Conectarse por RDP

1. Abrir Remote Desktop Connection (mstsc)
2. Conectar a: 216.238.80.222
3. Usuario: Administrator
4. Password: g#7UH-jM{otz9bd@

5. En la VPS, abrir PowerShell como Administrador y ejecutar:

```powershell
# Crear backup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "C:\BackupTemp\BMR-CIVER-$timestamp"
New-Item -Path $backupPath -ItemType Directory -Force

wbadmin start backup -backupTarget:$backupPath -include:C: -allCritical -quiet

# El backup tardará 20-40 minutos
# Cuando termine, comprimir:
$zipPath = "$backupPath.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($backupPath, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# Instalar AWS CLI si no está
# Descargar de: https://awscli.amazonaws.com/AWSCLIV2.msi

# Subir a Object Storage
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"

$fileName = Split-Path $zipPath -Leaf
aws s3 cp $zipPath "s3://backups-bmr-civer/bmr-backups/$fileName" --endpoint-url https://lax1.vultrobjects.com
```

---

## PARA RESTAURAR EN VPS DESTINO

### 1. Conectar a VPS Destino
- IP: 216.238.84.243
- Usuario: Administrador  
- Password: b[2)3]6{Agp_+C+

### 2. Descargar backup
```powershell
# Configurar AWS
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"

# Listar backups disponibles
aws s3 ls s3://backups-bmr-civer/bmr-backups/ --endpoint-url https://lax1.vultrobjects.com

# Descargar (reemplaza NOMBRE_DEL_BACKUP con el nombre real)
aws s3 cp s3://backups-bmr-civer/bmr-backups/NOMBRE_DEL_BACKUP.zip C:\BackupTemp\ --endpoint-url https://lax1.vultrobjects.com
```

### 3. Extraer
```powershell
$zipFile = "C:\BackupTemp\NOMBRE_DEL_BACKUP.zip"
$extractPath = $zipFile.Replace('.zip', '')

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractPath)
```

### 4. Restaurar
```powershell
# Ver versiones disponibles
wbadmin get versions -backupTarget:$extractPath

# Restaurar (esto reiniciará el servidor)
wbadmin start systemstaterecovery -version:FECHA -backupTarget:$extractPath -quiet
```

---

## NOTAS IMPORTANTES

- El backup tarda aprox. 20-40 minutos (tu VPS origen tiene solo 28 GB usados)
- La compresión tarda 10-20 minutos
- La subida a Object Storage tarda 20-40 minutos (dependiendo del tamaño final)
- **TOTAL: 1-2 horas aproximadamente**

## TIEMPOS REALES ESTIMADOS PARA TU CASO:
- Backup: ~15-20 min (solo 28 GB usados)
- Compresión: ~10 min
- Upload: ~15-20 min (archivo comprimido será más pequeño)
- **TOTAL: 40-50 minutos**
