# GUÍA: RESTAURACIÓN AUTOMÁTICA + ISO BOOTEABLE EN PARALELO

## 📋 RESUMEN

Vamos a realizar 2 procesos en paralelo:
1. **Habilitar PSRemoting en RESPALDO-1** → Restauración automática del backup
2. **Instalar Macrium en Civer-Two** → Crear ISO booteable

**Tiempo estimado total:** 2-3 horas (procesos en paralelo)

---

## 🔧 PROCESO 1: HABILITAR PSREMOTING EN RESPALDO-1

### Paso 1A: Conectar a RESPALDO-1 por RDP

```
Host: 216.238.84.243
Usuario: Administrator
Password: VL0jh-eDuT7+ftUz
```

### Paso 1B: Ejecutar script de habilitación

1. En RESPALDO-1, abre **PowerShell como Administrator**
2. Ejecuta:

```powershell
# Descargar script desde Civer-One
$source = "\\216.238.80.222\C$\Users\Public\BMR-Backup-VPS\Habilitar-PSRemoting-RESPALDO1.ps1"
$dest = "C:\Temp\Habilitar-PSRemoting-RESPALDO1.ps1"

# Si no puedes acceder a Civer-One, ejecuta estos comandos directamente:
Enable-PSRemoting -Force
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "216.238.80.222" -Force
Restart-Service WinRM -Force
```

### Paso 1C: Verificar configuración

```powershell
Test-WSMan
Get-Service WinRM
```

**Resultado esperado:** 
- WinRM: Running
- Test-WSMan: Muestra información XML

---

## 💿 PROCESO 2: CREAR ISO BOOTEABLE EN CIVER-TWO

### Paso 2A: Conectar a Civer-Two por RDP

```
Host: 216.238.88.126
Usuario: Administrator
Password: 6K#fVnH-arJG-(wT
```

### Paso 2B: Instalar Macrium Reflect

1. En el escritorio encontrarás: **MacriumReflect.exe**
2. **Doble click** para iniciar instalación
3. Opciones de instalación:
   - ✅ **Free Edition** (es suficiente)
   - ✅ **Typical Installation**
   - ✅ **Instalar Windows PE components** (para crear rescue media)
4. Click **Install**
5. **Tiempo:** 5-10 minutos

### Paso 2C: Crear imagen del disco

Una vez instalado Macrium Reflect:

#### Opción A: Usar interfaz gráfica (RECOMENDADO)

1. Abre **Macrium Reflect** desde el escritorio
2. Verás el disco **C:** listado
3. Click en **"Image this disk..."** (botón bajo el disco C:)
4. **Configurar backup:**
   - Destination folder: `C:\BackupTemp\CIVER-TWO-IMAGE-BOOTEABLE`
   - Click **Next**
5. **Opciones avanzadas:**
   - Compression: **Medium** (balance entre tamaño y velocidad)
   - ✅ **Verify image** (verificar integridad)
   - Click **Next**
6. **Nombre del backup:** `CIVER-TWO-BOOTEABLE-2025-11-05`
7. Click **Finish** y luego **OK**

**⏱️ TIEMPO:** 30-60 minutos (dependiendo del tamaño de datos)

#### Opción B: Usar script automatizado

En PowerShell de Civer-One (donde estás ahora):

```powershell
& "C:\Users\Public\BMR-Backup-VPS\Crear-ISO-Booteable-Macrium.ps1"
```

### Paso 2D: Crear Rescue Media (ISO booteable)

Mientras se crea la imagen, o después:

1. En Macrium Reflect, click **"Other Tasks"** (menú superior)
2. Click **"Create Rescue Media"**
3. Opciones:
   - ✅ **Windows PE 10.0 x64** (recomendado)
   - ✅ **Include Macrium Reflect** (para poder restaurar)
4. Click **Next**
5. **Output type:** ISO Image File
6. **Guardar en:** `C:\BackupTemp\Macrium-Rescue-Media.iso`
7. Click **Build**

**⏱️ TIEMPO:** 10-15 minutos

---

## 🔄 PROCESO 3: RESTAURACIÓN AUTOMÁTICA (después del Paso 1)

Una vez que RESPALDO-1 tenga PSRemoting habilitado:

### Paso 3A: Desde Civer-One, ejecutar restauración

```powershell
& "C:\Users\Public\BMR-Backup-VPS\Restaurar-RESPALDO1-Simple.ps1"
```

Este script:
1. ✅ Verifica los 20 archivos de backup en Civer-One (19.43 GB)
2. ✅ Conecta a RESPALDO-1 (ahora funcionará)
3. ✅ Transfiere los 20 archivos (toma ~30 minutos)
4. ✅ Extrae el backup completo
5. ✅ Analiza bootabilidad

**⏱️ TIEMPO TOTAL:** 45-60 minutos

---

## 📊 MONITOREO DE PROGRESO

### Ver progreso de Macrium (Civer-Two)
En Civer-Two, Macrium mostrará:
- ⏳ Porcentaje completado
- 📊 Velocidad de backup (MB/s)
- ⏱️ Tiempo estimado restante

### Ver progreso de restauración (RESPALDO-1)
El script mostrará:
```
[2/4] Conectando a RESPALDO-1...
[OK] Conectado a RESPALDO-1
Espacio libre: XX.XX GB

[3/4] Transfiriendo archivos (0/20)...
  Transferring: CIVER-TWO-BMR-COMPLETO-20251104-195448.7z.001...
  [OK] 0.98 GB transferido
  ...
```

---

## ✅ RESULTADO FINAL

Después de completar ambos procesos tendrás:

### En RESPALDO-1:
- ✅ **Backup completo restaurado** (23 GB de datos)
- ✅ Carpetas: Users, ProgramData, Program Files, Windows Config
- ✅ Listo para copiar a sus ubicaciones originales

### En Civer-Two:
- ✅ **Imagen de disco booteable** (.mrimg file)
- ✅ **ISO de rescate** (Macrium-Rescue-Media.iso)
- ✅ Listo para crear nueva VPS booteable

---

## 🚀 USAR EL ISO BOOTEABLE

### Método 1: En Vultr (crear nueva VPS)
1. En Vultr Dashboard → **ISO Library**
2. Click **"Add ISO"** → Upload URL o file
3. Sube: `Macrium-Rescue-Media.iso`
4. Crear nueva VPS → **Custom ISO** → Selecciona tu ISO
5. La VPS arrancará con Macrium Rescue
6. Desde Macrium Rescue → **Restore** → Selecciona imagen
7. **Restore to:** Disco C: de la nueva VPS

### Método 2: Restaurar en VPS existente
1. En RESPALDO-1 (o cualquier VPS)
2. Instala Macrium Reflect
3. **File → Restore Image**
4. Selecciona el archivo `.mrimg` desde Civer-Two
5. **Restore to:** Disco local
6. Reinicia el servidor

---

## 🔍 DIFERENCIAS ENTRE LOS DOS BACKUPS

| Característica | Backup Robocopy (19.43 GB) | Imagen Macrium |
|----------------|---------------------------|----------------|
| **Tipo** | Archivos individuales | Imagen de disco completa |
| **Booteable** | ❌ NO | ✅ SÍ |
| **Incluye** | Users, ProgramData, Programs | TODO el disco C: |
| **Restauración** | Copia manual de archivos | Restauración automática |
| **Tiempo restore** | 2-4 horas (manual) | 30-60 min (automático) |
| **Arranca directo** | ❌ NO (necesita Windows instalado) | ✅ SÍ (arranca sin nada) |
| **Tamaño** | Más pequeño (comprimido) | Más grande (todo el disco) |
| **Uso ideal** | Migrar datos/configs | Clonar servidor completo |

---

## 📞 COMANDOS RÁPIDOS

### Verificar estado PSRemoting (RESPALDO-1)
```powershell
Test-WSMan
Get-Service WinRM | Select Status
```

### Verificar progreso Macrium (Civer-Two)
Abre Macrium Reflect GUI y ve la pestaña **"Backup Progress"**

### Verificar archivos de backup (Civer-One)
```powershell
$files = Get-ChildItem "C:\BackupTemp\CIVER-TWO-BMR-COMPLETO-20251104-195448.7z.*"
$totalGB = [math]::Round(($files | Measure-Object Length -Sum).Sum/1GB, 2)
Write-Host "Total: $($files.Count) archivos = $totalGB GB"
```

---

## ⚠️ TROUBLESHOOTING

### PSRemoting sigue sin funcionar
```powershell
# En RESPALDO-1, verificar firewall
Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" | Select DisplayName, Enabled

# Permitir todo tráfico WinRM temporalmente
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in action=allow protocol=TCP localport=5985
```

### Macrium no encuentra suficiente espacio
```powershell
# Limpiar archivos temporales
Remove-Item C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item C:\Users\Administrator\AppData\Local\Temp\* -Recurse -Force -ErrorAction SilentlyContinue

# Verificar espacio nuevamente
Get-PSDrive C | Select @{N="FreeGB";E={[math]::Round($_.Free/1GB,2)}}
```

### Transferencia muy lenta a RESPALDO-1
```powershell
# Comprimir antes de transferir (si no lo hiciste)
# Los archivos .7z ya están comprimidos, deberían transferir rápido
```

---

## 📝 NOTAS IMPORTANTES

1. **Procesos en paralelo:** Puedes ejecutar Macrium y restauración simultáneamente
2. **No cierres sesiones RDP** durante procesos largos
3. **Macrium Free** es suficiente para crear ISO booteable
4. **El ISO de rescate** necesita los drivers de red de Vultr para conectar y descargar la imagen
5. **Alternativa simple:** Si Macrium es complejo, usa el backup de Robocopy + instalación limpia de Windows

---

## ⏭️ PRÓXIMOS PASOS

1. **AHORA:** Conecta a RESPALDO-1 y habilita PSRemoting (5 minutos)
2. **AHORA:** Conecta a Civer-Two e instala Macrium (10 minutos)
3. **DESPUÉS:** Inicia imagen de disco en Macrium (30-60 min background)
4. **DESPUÉS:** Ejecuta restauración a RESPALDO-1 (45-60 min background)
5. **AL FINAL:** Crea rescue media ISO (10-15 minutos)

**Total aproximado:** 2-3 horas (la mayoría en background)

---

¿Necesitas ayuda con algún paso específico? 🚀
