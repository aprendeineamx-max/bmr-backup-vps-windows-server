# Guía de Inicio Rápido - Sistema de Backup BMR

## ⚡ Inicio Rápido en 3 Pasos

### Paso 1: Verificar Configuración (2 minutos)

1. Abrir el archivo `config\credentials.json`
2. Verificar que las credenciales sean correctas
3. Las credenciales ya están pre-configuradas con tus datos

### Paso 2: Probar Conexión (1 minuto)

```powershell
# Probar conexión a VPS origen
.\scripts\local\Test-RemoteConnection.ps1 -Target Origen

# Probar conexión a VPS destino
.\scripts\local\Test-RemoteConnection.ps1 -Target Destino
```

### Paso 3: Ejecutar Backup (60-90 minutos)

```powershell
# Crear backup completo
.\Start-BMRBackup.ps1
```

¡Eso es todo! El sistema se encargará de:
- Instalar prerequisitos
- Crear backup BMR
- Comprimir el backup
- Subir a Object Storage
- Verificar integridad

---

## 🔄 Restaurar en VPS Destino

```powershell
# Listar backups disponibles
.\Start-BMRRestore.ps1 -ListAvailableBackups

# Restaurar backup específico
.\Start-BMRRestore.ps1 -S3Key "bmr-backups/BMR-Backup-Civer-One-20250104-153045.zip"
```

---

## ✅ Checklist Pre-Backup

- [ ] Verificar que las credenciales en `config\credentials.json` son correctas
- [ ] Verificar que hay al menos 50 GB libres en VPS origen
- [ ] Verificar conectividad con `Test-RemoteConnection.ps1`
- [ ] Object Storage tiene espacio disponible (1000 GB disponibles)

---

## 📊 Tiempos Estimados

| Operación | Tiempo Estimado | Depende de |
|-----------|----------------|------------|
| Crear Backup BMR | 30-60 min | Tamaño de datos en C: |
| Comprimir Backup | 10-20 min | Tamaño del backup |
| Subir a Object Storage | 20-40 min | Ancho de banda |
| Descargar desde Object Storage | 20-40 min | Ancho de banda |
| Restaurar | 30-60 min | Tamaño del backup |
| **TOTAL** | **~2-4 horas** | Variable |

---

## 💡 Tips para Backup Más Rápido

### 1. Usar Compresión Rápida
```powershell
.\Start-BMRBackup.ps1 -CompressLevel Fast
```

### 2. Eliminar Backup Local Después de Subir
```powershell
.\Start-BMRBackup.ps1 -DeleteLocalBackup
```

### 3. Excluir Archivos Temporales
Editar `config\backup-config.json` y agregar exclusiones.

---

## 🔍 Verificar Estado del Backup

### Ver Logs en Tiempo Real:
```powershell
Get-Content .\logs\backup-orchestration-*.log -Tail 50 -Wait
```

### Listar Backups en Object Storage:
```powershell
$env:AWS_ACCESS_KEY_ID = "G0LDHU6PIXWDEDJTAQ4B"
$env:AWS_SECRET_ACCESS_KEY = "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ"
aws s3 ls s3://backups-bmr-civer/bmr-backups/ --endpoint-url https://lax1.vultrobjects.com
```

---

## 🆘 Problemas Comunes

### "Error conectando a VPS"
```powershell
# En la VPS, ejecutar:
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### "AWS CLI no encontrado"
El script lo instalará automáticamente. Si falla, descarga manualmente de:
https://awscli.amazonaws.com/AWSCLIV2.msi

### "Espacio insuficiente"
```powershell
# Limpiar archivos temporales
Remove-Item C:\Windows\Temp\* -Recurse -Force
powercfg -h off  # Deshabilitar hibernación
```

---

## 📱 Comandos de Un Solo Línea

### Backup Completo con Todas las Opciones:
```powershell
.\Start-BMRBackup.ps1 -CompressLevel Maximum -DeleteLocalBackup -Verbose
```

### Restauración Automática:
```powershell
.\Start-BMRRestore.ps1 -S3Key "bmr-backups/BMR-Backup-XXX.zip" -AutoRestore
```

### Test Rápido de Todo:
```powershell
.\scripts\local\Test-RemoteConnection.ps1 -Target Origen
.\scripts\local\Test-RemoteConnection.ps1 -Target Destino
```

---

## 📁 Estructura de Archivos Generados

```
C:\Users\Public\BMR-Backup-VPS\
│
├── logs\
│   ├── backup-orchestration-20250104-153045.log
│   ├── restore-orchestration-20250104-160000.log
│   └── ... (logs históricos)
│
└── [En VPS]
    C:\BackupTemp\
    ├── BMR-Backup-Civer-One-20250104-153045\  (directorio)
    ├── BMR-Backup-Civer-One-20250104-153045.zip  (archivo comprimido)
    └── backup-report-20250104-153045.json  (metadata)
```

---

## 🔐 Seguridad

- ✅ Las credenciales están en `config\credentials.json` (ignorado por Git)
- ✅ Las conexiones usan WinRM cifrado
- ✅ Los backups pueden encriptarse (opción `-Encrypt`)
- ✅ Object Storage usa HTTPS

### Para Encriptar Backups:
```powershell
.\Start-BMRBackup.ps1 -Encrypt -EncryptionPassword "MiPasswordSuperSegura123!"
```

---

## 📈 Monitoreo del Progreso

### Desde tu PC:
```powershell
# Ver logs en tiempo real
Get-Content .\logs\backup-orchestration-*.log -Wait -Tail 20
```

### Desde la VPS (si te conectas por RDP):
```powershell
# Ver progreso de wbadmin
wbadmin get status
```

---

## 🎯 Próximos Pasos Después del Primer Backup

1. **Verificar que el backup está en Object Storage**
   ```powershell
   .\Start-BMRRestore.ps1 -ListAvailableBackups
   ```

2. **Probar restauración en VPS de prueba (opcional pero recomendado)**
   ```powershell
   .\Start-BMRRestore.ps1 -S3Key "bmr-backups/TU-BACKUP.zip"
   ```

3. **Programar backups automáticos**
   - Usar Task Scheduler de Windows
   - Configurar para ejecutar semanalmente

4. **Configurar notificaciones** (futuro)
   - Email al completar backup
   - Webhook a Telegram/Slack

---

## 📞 Ayuda Adicional

- Ver documentación completa: `README.md`
- Troubleshooting: `docs\troubleshooting.md`
- Test de conexión: `.\scripts\local\Test-RemoteConnection.ps1`

---

## ⚠️ Notas Importantes

1. **Primer Backup**: Siempre tarda más (datos completos)
2. **Ancho de Banda**: La transferencia a Object Storage consume ancho de banda
3. **Espacio**: Necesitas ~2x el espacio usado en C: durante el proceso
4. **Restauración BMR**: Requiere arrancar en WinRE para restauración completa

---

## 🎉 ¡Listo!

Tu sistema de backup BMR está configurado y listo para usar.

**Comando principal:**
```powershell
.\Start-BMRBackup.ps1
```

Siéntate, relájate, y deja que el sistema haga el trabajo. ☕
