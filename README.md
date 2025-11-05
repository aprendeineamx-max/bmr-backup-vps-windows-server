# Sistema de Backup BMR/Full Server para VPS Windows Server 2025

## 🎯 Descripción
Sistema completo para realizar backups BMR (Bare Metal Recovery) de tu VPS Windows Server 2025 y restaurarlo en otra VPS, usando Vultr Object Storage como almacenamiento intermedio.

## 🏗️ Arquitectura de la Solución

```
┌─────────────────────┐
│   VPS ORIGEN        │
│   Civer-One         │
│   216.238.80.222    │
│   (México)          │
└──────────┬──────────┘
           │
           │ 1. Backup BMR
           │    (wbadmin)
           ▼
┌─────────────────────┐
│  Object Storage     │
│  Vultr LAX1         │
│  (Los Angeles)      │
│  1000 GB capacity   │
└──────────┬──────────┘
           │
           │ 2. Download
           │    Backup
           ▼
┌─────────────────────┐
│   VPS DESTINO       │
│   RESPALDO-1        │
│   216.238.84.243    │
│   (México)          │
└─────────────────────┘
```

## ⚙️ Características

- ✅ Backup completo BMR (no solo System State)
- ✅ Ejecución remota desde tu PC
- ✅ Almacenamiento en Object Storage (económico y escalable)
- ✅ Compresión automática
- ✅ Encriptación opcional
- ✅ Logs detallados
- ✅ Verificación de integridad
- ✅ Restauración automatizada

## 📋 Requisitos Previos

### En VPS Origen (Civer-One)
- Windows Server 2025 Standard
- PowerShell 5.1+
- Windows Server Backup feature instalada
- Conexión RDP/WinRM habilitada

### En VPS Destino (RESPALDO-1)
- Windows Server 2025 Standard
- Espacio suficiente para restauración
- Windows Recovery Environment habilitado

### En tu PC
- Windows con PowerShell
- s3cmd o AWS CLI (para Object Storage)
- Acceso remoto a las VPS

## 🚀 Instalación Rápida

### 1. Configurar Credenciales

Edita el archivo `config\credentials.json` con tus datos:

```json
{
  "vpsOrigen": {
    "ip": "216.238.80.222",
    "username": "Administrator",
    "password": "g#7UH-jM{otz9bd@"
  },
  "vpsDestino": {
    "ip": "216.238.84.243",
    "username": "Administrador",
    "password": "b[2)3]6{Agp_+C+"
  },
  "objectStorage": {
    "endpoint": "lax1.vultrobjects.com",
    "accessKey": "G0LDHU6PIXWDEDJTAQ4B",
    "secretKey": "AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ",
    "bucket": "backups-bmr-civer"
  }
}
```

### 2. Ejecutar desde tu PC

```powershell
# Backup completo
.\Start-BMRBackup.ps1

# Restaurar en VPS destino
.\Start-BMRRestore.ps1
```

## 📁 Estructura del Proyecto

```
BMR-Backup-VPS/
│
├── README.md                          # Este archivo
├── config/
│   ├── credentials.json              # Credenciales (NO subir a Git)
│   ├── credentials.example.json      # Plantilla de credenciales
│   └── backup-config.json            # Configuración de backup
│
├── scripts/
│   ├── remote/                       # Scripts para ejecutar en VPS
│   │   ├── Install-Prerequisites.ps1 # Instalar requisitos
│   │   ├── Create-BMRBackup.ps1     # Crear backup BMR
│   │   ├── Upload-ToObjectStorage.ps1 # Subir a Object Storage
│   │   ├── Download-FromObjectStorage.ps1 # Descargar backup
│   │   └── Restore-BMRBackup.ps1    # Restaurar backup
│   │
│   ├── local/                        # Scripts para tu PC
│   │   ├── Test-RemoteConnection.ps1 # Probar conexión
│   │   └── Monitor-BackupProgress.ps1 # Monitorear progreso
│   │
│   └── utils/                        # Utilidades
│       ├── Logger.ps1               # Sistema de logs
│       └── S3-Helper.ps1            # Funciones para S3
│
├── Start-BMRBackup.ps1              # Script maestro de backup
├── Start-BMRRestore.ps1             # Script maestro de restauración
│
├── logs/                            # Logs de operaciones
└── docs/                            # Documentación adicional
    ├── troubleshooting.md
    └── manual-recovery.md
```

## 🔧 Uso Detallado

### Paso 1: Preparar el Entorno

```powershell
# Instalar requisitos en VPS origen
.\scripts\remote\Install-Prerequisites.ps1 -Target Origen

# Instalar requisitos en VPS destino
.\scripts\remote\Install-Prerequisites.ps1 -Target Destino
```

### Paso 2: Crear Backup

```powershell
# Ejecutar backup completo (se ejecuta remotamente en VPS origen)
.\Start-BMRBackup.ps1 -Verbose

# Con encriptación
.\Start-BMRBackup.ps1 -Encrypt -EncryptionPassword "TuPasswordSegura"

# Con compresión máxima
.\Start-BMRBackup.ps1 -CompressionLevel Maximum
```

### Paso 3: Restaurar en VPS Destino

```powershell
# Restaurar backup más reciente
.\Start-BMRRestore.ps1

# Restaurar backup específico
.\Start-BMRRestore.ps1 -BackupDate "2025-11-04"

# Restauración en modo de prueba (sin aplicar)
.\Start-BMRRestore.ps1 -WhatIf
```

## 📊 Monitoreo y Logs

```powershell
# Ver progreso en tiempo real
.\scripts\local\Monitor-BackupProgress.ps1

# Ver logs
Get-Content .\logs\backup-$(Get-Date -Format 'yyyy-MM-dd').log -Tail 50 -Wait
```

## 🔐 Seguridad

- Las credenciales se almacenan en `credentials.json` (agregado a .gitignore)
- Conexiones remotas usan WinRM sobre HTTPS (recomendado)
- Los backups pueden encriptarse con AES-256
- Las contraseñas se manejan como SecureString en PowerShell

## ⚠️ Consideraciones Importantes

### Espacio en Disco
- El backup ocupará aproximadamente el tamaño usado del disco C: (comprimido)
- Se recomienda tener al menos 50 GB libres en VPS origen para el backup temporal
- El Object Storage debe tener espacio suficiente (cuenta con 1000 GB)

### Tiempo de Ejecución
- Backup: 30-60 minutos (depende del tamaño de datos)
- Upload a Object Storage: 20-40 minutos (depende de ancho de banda)
- Download desde Object Storage: 20-40 minutos
- Restauración: 30-60 minutos

### Costos de Object Storage
- Storage: $0.050/GB (sobre 1000 GB)
- Transfer: $0.010/GB (sobre 1000 GB)

## 🐛 Troubleshooting

### Error: "Windows Server Backup no está instalado"
```powershell
Install-WindowsFeature -Name Windows-Server-Backup
```

### Error: "No se puede conectar a la VPS"
```powershell
# Verificar WinRM
Test-WSMan -ComputerName 216.238.80.222 -Credential (Get-Credential)

# Habilitar WinRM en VPS (ejecutar en la VPS)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### Error: "Backup muy grande para Object Storage"
```powershell
# Usar compresión máxima
.\Start-BMRBackup.ps1 -CompressionLevel Maximum

# O usar Hub-de-Backups como almacenamiento temporal
.\Start-BMRBackup.ps1 -UseHubStorage
```

## 🔄 Alternativas de Almacenamiento

### Opción 1: Object Storage (Recomendada) ✅
- ✅ Más económica a largo plazo
- ✅ Alta disponibilidad
- ✅ No requiere mantener VPS adicional
- ❌ Puede ser más lenta la transferencia

### Opción 2: Hub-de-Backups VPS
- ✅ Transferencia más rápida (red interna Vultr)
- ✅ Útil para múltiples backups
- ❌ Costo mensual fijo
- ❌ Requiere mantenimiento

### Opción 3: Servidor-de-Recuperacion-2
- ✅ Disco E: con 1000 GB
- ✅ Ya disponible
- ❌ En diferente ubicación (Atlanta vs México)
- ❌ Mayor latencia

## 📚 Documentación Adicional

- [Manual de Recuperación Manual](docs/manual-recovery.md)
- [Guía de Troubleshooting](docs/troubleshooting.md)
- [Mejores Prácticas](docs/best-practices.md)

## 🤝 Soporte

Para problemas o preguntas:
1. Revisa los logs en `logs/`
2. Consulta [troubleshooting.md](docs/troubleshooting.md)
3. Verifica la configuración en `config/`

## 📝 Notas

- Este sistema está optimizado para Windows Server 2025
- Se recomienda realizar backups semanales
- Prueba la restauración al menos una vez al mes
- Mantén las credenciales seguras y actualizadas

## 🔄 Roadmap

- [ ] Soporte para backups incrementales
- [ ] Interfaz web para monitoreo
- [ ] Notificaciones por email/Telegram
- [ ] Backup automático programado
- [ ] Replicación multi-región
