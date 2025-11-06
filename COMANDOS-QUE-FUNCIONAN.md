# COMANDOS QUE FUNCIONAN - BMR BACKUP SYSTEM

## ✅ HABILITAR PSREMOTING EN VPS (Windows Server 2025)

### Comando completo que SÍ FUNCIONA:

```powershell
# Paso 1: Deshabilitar firewall temporalmente
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Paso 2: Configurar autenticación básica
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force

# Paso 3: Habilitar PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Paso 4: Configurar TrustedHosts (aceptar todas las IPs)
winrm set winrm/config/client '@{TrustedHosts="*"}'

# Paso 5: Permitir conexiones sin cifrar (para PSRemoting entre VPS)
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Paso 6: Habilitar servicios necesarios
Set-Service -Name WinRM -StartupType Automatic
Start-Service WinRM
Set-Service -Name RemoteRegistry -StartupType Automatic
Start-Service RemoteRegistry

# Paso 7: Habilitar reglas de firewall para WMI y Remote Event Log
netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes
netsh advfirewall firewall set rule group="Remote Event Log Management" new enable=yes

# Paso 8: Reiniciar WinRM
Restart-Service WinRM -Force

# Paso 9: Verificar configuración
Test-WSMan
Get-Service WinRM,RemoteRegistry | Select Name,Status
```

### Resultado esperado de Test-WSMan:
```
wsmid           : http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd
ProtocolVersion : http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd
ProductVendor   : Microsoft Corporation
ProductVersion  : OS: 0.0.0 SP: 0.0 Stack: 3.0
```

### Resultado esperado de Get-Service:
```
Name            Status
----            ------
RemoteRegistry Running
WinRM          Running
```

---

## ✅ VERIFICAR CONEXIÓN REMOTA DESDE OTRA VPS

```powershell
# Crear credencial
$pass = ConvertTo-SecureString "PASSWORD_AQUI" -AsPlainText -Force
$cred = New-Object PSCredential("Administrator", $pass)

# Intentar conectar
$session = New-PSSession -ComputerName "IP_DESTINO" -Credential $cred -ErrorAction Stop

# Si funciona, ejecutar comando remoto
Invoke-Command -Session $session -ScriptBlock {
    Write-Host "Hostname: $env:COMPUTERNAME"
    $disk = Get-PSDrive C
    Write-Host "Disco C: $([math]::Round($disk.Free/1GB,2)) GB libres"
}

# Cerrar sesión
Remove-PSSession $session
```

---

## ❌ COMANDOS QUE NO FUNCIONARON

### 1. PsExec remoto (sin PSRemoting previo):
```powershell
# NO FUNCIONA: PsExec necesita RemoteRegistry habilitado primero
.\PsExec.exe \\IP_REMOTA -u Administrator -p PASSWORD powershell -Command "Enable-PSRemoting -Force"
# Error: Access Denied (exit code 5 o 6)
```

### 2. WMI remoto (con firewall por defecto):
```powershell
# NO FUNCIONA: RPC bloqueado por firewall
Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList "powershell.exe -Command 'Enable-PSRemoting -Force'" -ComputerName IP_REMOTA -Credential $cred
# Error: The RPC server is unavailable
```

### 3. Instalación silenciosa de Macrium Reflect Free:
```powershell
# NO FUNCIONA: Instalador requiere interacción GUI para registro
Start-Process -FilePath "MacriumReflect.exe" -ArgumentList "/VERYSILENT /NORESTART" -Wait
# Resultado: Proceso se cuelga o no completa instalación
```

---

## 📋 APLICADO EN:

### VPS: RESPALDO-1
- **IP:** 216.238.84.243
- **Usuario:** Administrator
- **Password:** VL0jh-eDuT7+ftUz
- **Fecha aplicado:** 2025-11-05
- **Resultado:** ✅ PSRemoting habilitado exitosamente
- **Configuración:**
  - TrustedHosts: `*`
  - AllowUnencrypted: `true`
  - Auth.Basic: `true`
  - Firewall: Deshabilitado (Domain, Public, Private)
  - WMI Rules: Habilitadas
  - Remote Event Log: Habilitado

### VPS: Civer-Two
- **IP:** 216.238.88.126
- **Usuario:** Administrator
- **Password:** 6K#fVnH-arJG-(wT
- **Fecha:** Ya tenía PSRemoting habilitado desde antes
- **Estado Macrium:** Instalación en progreso/fallida (requiere GUI)

### VPS: Civer-One
- **IP:** 216.238.80.222
- **Usuario:** Administrator
- **Password:** g#7UH-jM{otz9bd@
- **Rol:** VPS desde donde se ejecutan los scripts remotos
- **Estado:** PSRemoting habilitado, tiene backup completo (19.43 GB, 20 archivos)

---

## 🔧 TROUBLESHOOTING

### Error: "Access is denied" al intentar New-PSSession

**Solución:**
1. En el servidor destino, ejecutar todos los comandos de arriba
2. Asegurarse que `AllowUnencrypted = true`
3. Verificar que firewall permita puerto 5985 (WinRM HTTP)
4. Reiniciar servicio WinRM: `Restart-Service WinRM -Force`

### Error: "The hostname pattern is invalid: '*'"

**Causa:** Ya existe un valor en TrustedHosts y usaste `-Concatenate`

**Solución:**
```powershell
# Reemplazar en vez de concatenar
winrm set winrm/config/client '@{TrustedHosts="*"}'
```

### Error: "The RPC server is unavailable"

**Causa:** Firewall bloqueando RPC (puerto 135 + dinámicos)

**Solución:**
```powershell
# En el servidor destino
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```

---

## 📝 NOTAS IMPORTANTES

1. **Seguridad:** `AllowUnencrypted` y firewall deshabilitado son para LAB/TEST. En producción usar certificados y HTTPS.

2. **TrustedHosts `*`:** Permite conexiones desde cualquier IP. Más seguro: especificar IPs exactas.

3. **Macrium Reflect:** La versión FREE no soporta instalación silenciosa completa. Usar:
   - Macrium Reflect Server Edition (licencia pagada)
   - O instalar manualmente via RDP

4. **Backup actual disponible:**
   - Ubicación: `C:\BackupTemp\` en Civer-One
   - Nombre: `CIVER-TWO-BMR-COMPLETO-20251104-195448.7z.001` a `.020`
   - Tamaño: 19.43 GB (20 archivos)
   - Contenido: Users (16.49GB), ProgramData (1.35GB), Program Files (5.19GB), Config (0.11GB)
   - Tipo: File-level backup (no booteable directamente)

---

## ✅ PRÓXIMOS PASOS

Una vez RESPALDO-1 esté conectado:

```powershell
# Ejecutar desde Civer-One
& "C:\Users\Public\BMR-Backup-VPS\Restaurar-RESPALDO1-Simple.ps1"
```

Esto transferirá y extraerá automáticamente el backup completo en RESPALDO-1.

---

## ✅ TRANSFERIR VIA VULTR OBJECT STORAGE (FUNCIONANDO)

### Subir backup desde Civer-One:
```powershell
& "C:\Users\Public\BMR-Backup-VPS\Subir-A-Vultr-ObjectStorage.ps1"
```

**Resultado:**
- ✅ 20 archivos (19.43 GB) subidos en 2.55 minutos
- Ubicación: `s3://almacen-de-backups-cuenta-destino/backups/civer-two/`

### Descargar en cualquier VPS:
```powershell
# Instalar AWS CLI
$awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
Invoke-WebRequest -Uri $awsUrl -OutFile "C:\Temp\AWSCLIV2.msi" -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i C:\Temp\AWSCLIV2.msi /quiet /norestart" -Wait

# Configurar credenciales
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"

# Descargar
& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" s3 sync s3://almacen-de-backups-cuenta-destino/backups/civer-two/ C:\BackupTemp\ --endpoint-url https://lax1.vultrobjects.com
```

---

## ❌ PSREMOTING ENTRE CIVER-ONE Y RESPALDO-1 (NO FUNCIONA)

**Problema:** Aún con todas las configuraciones, "Access Denied"

**Configurado:**
- ✅ Firewall deshabilitado en ambos
- ✅ AllowUnencrypted = true en ambos
- ✅ TrustedHosts = * en ambos
- ✅ Auth.Basic = true en ambos
- ❌ Conexión sigue fallando

**Posible causa:** Diferencia de dominio/workgroup o política de seguridad adicional de Vultr

**Workaround:** Usar Object Storage (funciona perfecto)

---

**Última actualización:** 2025-11-05 21:15
**Probado en:** Windows Server 2025 Standard
**PowerShell Version:** 5.1
**Vultr Object Storage:** ✅ FUNCIONANDO
**PSRemoting Civer-One → RESPALDO-1:** ❌ BLOQUEADO
