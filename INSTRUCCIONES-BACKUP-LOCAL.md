# 🚀 INSTRUCCIONES PARA EJECUTAR BACKUP LOCAL

## ⚡ MÉTODO RÁPIDO

### Desde Civer-One (donde estás ahora):

```powershell
# 1. Copiar script a Civer-Two
$session = New-PSSession -ComputerName 216.238.88.126 -Credential (New-Object PSCredential("Administrator", (ConvertTo-SecureString "6K#fVnH-arJG-(wT" -AsPlainText -Force)))

Copy-Item "C:\Users\Public\BMR-Backup-VPS\Backup-VPS-Local.ps1" -Destination "C:\Users\Administrator\Desktop\" -ToSession $session

# 2. Ejecutar remotamente
Invoke-Command -Session $session -ScriptBlock {
    Set-Location C:\Users\Administrator\Desktop
    .\Backup-VPS-Local.ps1
}
```

---

## 📋 MÉTODO MANUAL (si el remoto falla)

### 1. Conéctate a Civer-Two por RDP

- **IP:** 216.238.88.126
- **Usuario:** Administrator
- **Contraseña:** 6K#fVnH-arJG-(wT)

### 2. Descarga el script

Opción A - Si tienes acceso a Civer-One:
```powershell
\\216.238.80.222\C$\Users\Public\BMR-Backup-VPS\Backup-VPS-Local.ps1
```

Opción B - Crear el archivo manualmente:
```powershell
# Pegar el contenido de Backup-VPS-Local.ps1
notepad C:\Backup-VPS-Local.ps1
```

### 3. Ejecuta el backup

```powershell
# Abrir PowerShell como Administrador
cd C:\
.\Backup-VPS-Local.ps1
```

### 4. Monitor el progreso

El script mostrará:
- ✓ Carpetas respaldadas
- ✓ Tamaño de cada parte
- ✓ Progreso de subida a Object Storage

---

## 🎯 ¿QUÉ HACE EL SCRIPT?

1. **Crea backup de carpetas críticas:**
   - `C:\Users` (documentos, configuraciones)
   - `C:\ProgramData` (datos de aplicaciones)
   - `C:\Program Files\Common Files` (archivos compartidos)
   - `C:\Windows\System32\config` (configuración del sistema)

2. **Comprime en partes de 1GB:**
   - Facilita la transferencia
   - Permite reintentos por partes

3. **Sube a Vultr Object Storage:**
   - Automáticamente si AWS CLI está disponible
   - Usa credenciales ya configuradas

4. **Genera log detallado:**
   - Ubicación: `C:\BackupTemp\[NOMBRE-BACKUP]\backup.log`

---

## 📦 RESTAURACIÓN

### En RESPALDO-1 (VPS destino):

```powershell
# 1. Descargar backup desde Object Storage
aws s3 sync s3://backups-bmr-civer/backups/CIVER-TWO-BACKUP-XXXXXXX C:\Restore --endpoint-url https://lax1.vultrobjects.com

# 2. Si está en partes (. 7z.001, .7z.002, etc.)
cd C:\Restore
7z x CIVER-TWO-BACKUP-XXXXXXX.7z.001

# 3. Copiar archivos a sus ubicaciones
robocopy C:\Restore\Users C:\Users /E /R:2 /W:5
robocopy C:\Restore\ProgramData C:\ProgramData /E /R:2 /W:5
# ... etc
```

---

## ⚙️ OPCIONES DEL SCRIPT

```powershell
# Ejecutar sin subir a Object Storage (solo crear backup local)
.\Backup-VPS-Local.ps1 -SkipUpload
```

---

## 🔍 VERIFICACIÓN

### Después de ejecutar, verifica:

```powershell
# Ver archivos creados
Get-ChildItem C:\BackupTemp\*BACKUP* -Recurse

# Ver tamaño total
(Get-ChildItem C:\BackupTemp\*BACKUP*.7z.* | Measure-Object -Property Length -Sum).Sum / 1GB

# Verificar en Object Storage
aws s3 ls s3://backups-bmr-civer/backups/ --endpoint-url https://lax1.vultrobjects.com
```

---

## ⏱️ TIEMPO ESTIMADO

- **Copia de archivos:** 10-15 minutos
- **Compresión:** 15-20 minutos
- **Subida (dependiendo de ancho de banda):** 30-60 minutos
- **TOTAL:** 1-1.5 horas aproximadamente

---

## 🆘 SOLUCIÓN DE PROBLEMAS

### Error: "7-Zip no encontrado"
```powershell
# El script lo instalará automáticamente
# O descarga manual: https://www.7-zip.org/download.html
```

### Error: "AWS CLI no encontrado"
```powershell
# Descarga e instala:
https://awscli.amazonaws.com/AWSCLIV2.msi

# Luego ejecuta nuevamente el script
```

### Error: "Permisos insuficientes"
```powershell
# Asegúrate de ejecutar PowerShell como Administrador
# Click derecho en PowerShell → "Ejecutar como administrador"
```

### El backup es muy grande
```powershell
# Edita el script y comenta carpetas que no necesites:
# Busca $foldersToBackup y elimina líneas no necesarias
```

---

## 📞 CONTACTO

Si el script falla, revisa:
1. El log: `C:\BackupTemp\[NOMBRE-BACKUP]\backup.log`
2. Los logs de robocopy: `C:\BackupTemp\[NOMBRE-BACKUP]\robocopy_*.log`

El backup local estará en: `C:\BackupTemp\CIVER-TWO-BACKUP-[TIMESTAMP]`
