# Troubleshooting Guide - Sistema de Backup BMR

## Problemas Comunes y Soluciones

### 1. Error de Conexión WinRM

**Síntoma:**
```
Error conectando a VPS: Connecting to remote server failed...
```

**Soluciones:**

#### En la VPS (Ejecutar como Administrador):
```powershell
# Habilitar PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Configurar TrustedHosts
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Iniciar servicio WinRM
Start-Service WinRM
Set-Service WinRM -StartupType Automatic

# Permitir en firewall
Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
```

#### En tu PC Local:
```powershell
# Configurar TrustedHosts
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# O específico para tu VPS
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "216.238.80.222,216.238.84.243" -Force
```

---

### 2. Windows Server Backup No Instalado

**Síntoma:**
```
Windows Server Backup no está instalado
```

**Solución:**
```powershell
# Instalar Windows Server Backup
Install-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature

# Verificar instalación
Get-WindowsFeature -Name Windows-Server-Backup
```

---

### 3. Espacio Insuficiente en Disco

**Síntoma:**
```
Espacio en disco puede ser insuficiente
```

**Soluciones:**

```powershell
# Limpiar archivos temporales
Remove-Item C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item C:\Temp\* -Recurse -Force -ErrorAction SilentlyContinue

# Limpiar Windows Update
Dism.exe /online /Cleanup-Image /StartComponentCleanup

# Desactivar hibernación (libera espacio igual a RAM)
powercfg -h off

# Verificar espacio
Get-PSDrive C | Select-Object Used,Free
```

---

### 4. Error Subiendo a Object Storage

**Síntoma:**
```
Error subiendo archivo a Object Storage
```

**Soluciones:**

#### Verificar AWS CLI:
```powershell
# Verificar instalación
aws --version

# Si no está instalado, descarga desde:
# https://awscli.amazonaws.com/AWSCLIV2.msi
```

#### Verificar Credenciales:
```powershell
# Probar conexión
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"

aws s3 ls s3://backups-bmr-civer --endpoint-url https://lax1.vultrobjects.com
```

#### Verificar Conectividad:
```powershell
Test-NetConnection -ComputerName lax1.vultrobjects.com -Port 443
```

---

### 5. Backup Muy Lento

**Síntomas:**
- El backup tarda más de 2 horas
- Transferencia muy lenta a Object Storage

**Soluciones:**

#### Optimizar Compresión:
```powershell
# Usar compresión rápida en lugar de máxima
.\Start-BMRBackup.ps1 -CompressLevel Fast
```

#### Excluir Archivos Innecesarios:
Editar `config\backup-config.json`:
```json
{
  "backup": {
    "excludeFolders": [
      "C:\\Windows\\Temp",
      "C:\\Temp",
      "C:\\Users\\*\\AppData\\Local\\Temp",
      "C:\\pagefile.sys",
      "C:\\hiberfil.sys"
    ]
  }
}
```

#### Usar Almacenamiento Local Temporal:
Si tienes otra VPS con más espacio, usa Hub-de-Backups en lugar de Object Storage directamente.

---

### 6. Error de Restauración

**Síntoma:**
```
Error en la restauración. Código: X
```

**Soluciones:**

#### Método 1: Restauración desde WinRE (Recomendado)

1. Reiniciar la VPS
2. Presionar F8 o Shift+F8 durante arranque
3. Seleccionar "Troubleshoot" > "Advanced Options" > "Command Prompt"
4. Ejecutar:
```cmd
diskpart
list disk
select disk 0
clean
exit

wbadmin start sysrecovery -version:XX/XX/XXXX-XX:XX -backupTarget:C:\BackupTemp\BMR-Backup-XXX -restartComputer
```

#### Método 2: Restauración Manual de Archivos

```powershell
# Montar VHD del backup
$vhdPath = "C:\BackupTemp\BMR-Backup-XXX\WindowsImageBackup\XXX.vhdx"
Mount-DiskImage -ImagePath $vhdPath

# Copiar archivos manualmente
# (no recomendado para BMR completo)
```

---

### 7. Archivo Corrupto en Descarga

**Síntoma:**
```
Checksum no coincide!
```

**Soluciones:**

```powershell
# Descargar nuevamente
.\Download-FromObjectStorage.ps1 -S3Key "bmr-backups/XXX.zip" -VerifyChecksum

# Si persiste, verificar en Object Storage
aws s3api head-object --bucket backups-bmr-civer --key "bmr-backups/XXX.zip" --endpoint-url https://lax1.vultrobjects.com
```

---

### 8. Credenciales Inválidas

**Síntoma:**
```
Access Denied
```

**Soluciones:**

#### Verificar Credenciales en `config\credentials.json`:
```json
{
  "vpsOrigen": {
    "username": "Administrator",
    "password": "TU_PASSWORD_CORRECTO"
  }
}
```

#### Probar Manualmente:
```powershell
# Probar RDP
mstsc /v:216.238.80.222

# Probar PSRemoting
$cred = Get-Credential
Enter-PSSession -ComputerName 216.238.80.222 -Credential $cred
```

---

### 9. Object Storage Bucket No Existe

**Síntoma:**
```
Bucket no existe. Creando...
Error: Access Denied
```

**Soluciones:**

#### Crear Bucket Manualmente en Vultr:
1. Ir a https://my.vultr.com/
2. Products > Cloud Storage > Object Storage
3. Seleccionar tu Object Storage: almacen-de-backups-cuenta-destino
4. Click en "Buckets"
5. Crear bucket: `backups-bmr-civer`

#### O usar AWS CLI:
```powershell
aws s3 mb s3://backups-bmr-civer --endpoint-url https://lax1.vultrobjects.com
```

---

### 10. Error: "No se puede completar el backup"

**Síntomas:**
- wbadmin falla con error genérico
- Backup se interrumpe sin mensaje claro

**Soluciones:**

#### Verificar Logs de Windows:
```powershell
# Ver eventos de Windows Backup
Get-WinEvent -LogName "Microsoft-Windows-Backup" -MaxEvents 50 | Format-List

# Ver errores del sistema
Get-EventLog -LogName System -EntryType Error -Newest 20
```

#### Verificar Servicio VSS:
```powershell
# Reiniciar Volume Shadow Copy
Restart-Service VSS
Get-Service VSS

# Listar shadow copies
vssadmin list shadows
```

#### Liberar Shadow Copies Antiguas:
```powershell
vssadmin delete shadows /all /quiet
```

---

## Comandos Útiles de Diagnóstico

### Ver Backups Existentes:
```powershell
wbadmin get versions
```

### Ver Status del Último Backup:
```powershell
wbadmin get status
```

### Ver Información del Disco:
```powershell
Get-Volume
Get-Disk
```

### Verificar Conectividad S3:
```powershell
aws s3 ls --endpoint-url https://lax1.vultrobjects.com
```

### Monitorear Transferencia de Red:
```powershell
Get-NetAdapter | Get-NetAdapterStatistics
```

### Ver Procesos de Backup:
```powershell
Get-Process | Where-Object {$_.Name -like "*wbadmin*" -or $_.Name -like "*backup*"}
```

---

## Logs y Archivos Importantes

| Ubicación | Descripción |
|-----------|-------------|
| `C:\BMR-Backup-VPS\logs\` | Logs del sistema de backup |
| `C:\Windows\Logs\WindowsServerBackup\` | Logs de Windows Server Backup |
| `C:\BackupTemp\` | Backups temporales |
| `C:\BMR-Backup-System\` | Scripts en VPS remota |

---

## Contacto y Soporte

Si después de revisar esta guía sigues teniendo problemas:

1. Revisa los logs en `logs/`
2. Ejecuta el test de conexión: `.\scripts\local\Test-RemoteConnection.ps1`
3. Verifica tu configuración en `config\credentials.json`

---

## Referencias Útiles

- [Documentación Windows Server Backup](https://docs.microsoft.com/en-us/windows-server/administration/windows-server-backup/windows-server-backup-overview)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [Vultr Object Storage](https://www.vultr.com/docs/vultr-object-storage/)
- [PowerShell Remoting](https://docs.microsoft.com/en-us/powershell/scripting/learn/remoting/running-remote-commands)
