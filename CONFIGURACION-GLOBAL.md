# 🔧 CONFIGURACIÓN GLOBAL DEL SISTEMA DE BACKUP BMR

## 📍 Ubicación del Archivo de Configuración

**Archivo principal:** `config/credentials.json`

Este archivo contiene **TODAS** las variables de configuración del sistema.

---

## 🖥️ VPS ORIGEN (Servidor a respaldar)

**Actual:** Civer-Two
- **IP:** 216.238.88.126
- **Usuario:** Administrator
- **Password:** 6K#fVnH-arJG-(wT
- **Ubicación:** Mexico City
- **Recursos:** 2 vCPUs, 16GB RAM, 200GB NVMe

Para cambiar la VPS origen, edita en `config/credentials.json`:
```json
"vpsOrigen": {
  "name": "Nombre-de-tu-VPS",
  "ip": "TU.IP.AQUI",
  "username": "Administrator",
  "password": "TU_PASSWORD",
  "location": "Ciudad"
}
```

---

## 🎯 VPS DESTINO (Servidor donde restaurar)

**Actual:** RESPALDO-1
- **IP:** 216.238.84.243
- **Usuario:** Administrador
- **Password:** b[2)3]6{Agp_+C+
- **Ubicación:** Mexico City
- **Recursos:** 2 vCPUs, 8GB RAM, 160GB NVMe

Para cambiar la VPS destino, edita:
```json
"vpsDestino": {
  "name": "Nombre-VPS-Destino",
  "ip": "TU.IP.DESTINO",
  "username": "Administrador",
  "password": "PASSWORD_DESTINO",
  "location": "Ciudad"
}
```

---

## ☁️ OBJECT STORAGE (Almacenamiento intermedio)

**Proveedor:** Vultr Object Storage (S3-compatible)
- **Endpoint:** lax1.vultrobjects.com
- **Región:** lax1 (Los Angeles)
- **Bucket:** backups-bmr-civer
- **Access Key:** G0LDHU6PIXWDEDJTAQ4B
- **Secret Key:** AUxkwxrBSe3SK1k6MdknXnvloCB9EQiuU7HLw1eZ
- **Estado:** ✅ Habilitado

Para cambiar Object Storage, edita:
```json
"objectStorage": {
  "provider": "vultr",
  "endpoint": "lax1.vultrobjects.com",
  "region": "lax1",
  "accessKey": "TU_ACCESS_KEY",
  "secretKey": "TU_SECRET_KEY",
  "bucket": "nombre-de-tu-bucket",
  "location": "Los Angeles",
  "enabled": true
}
```

---

## 🔄 SERVIDORES OPCIONALES

### Hub de Backups (Deshabilitado)
- **IP:** 216.238.84.79
- **Block Storage:** E: (1000GB)
- **Estado:** ❌ Deshabilitado

### Servidor de Recuperación 2 (Deshabilitado)
- **IP:** 45.32.215.154
- **Block Storage:** E:
- **Ubicación:** Atlanta
- **Estado:** ❌ Deshabilitado (falta password)

Para habilitar, cambia `"enabled": false` a `"enabled": true` en el archivo `config/credentials.json`

---

## 🚀 CÓMO USAR ESTE ARCHIVO

### Opción 1: Editar credentials.json directamente
```powershell
notepad "C:\Users\Public\BMR-Backup-VPS\config\credentials.json"
```

### Opción 2: Editar desde VS Code
1. Abre: `C:\Users\Public\BMR-Backup-VPS\config\credentials.json`
2. Modifica los valores que necesites
3. Guarda el archivo (Ctrl+S)

### Opción 3: Ver configuración actual
```powershell
cd "C:\Users\Public\BMR-Backup-VPS"
Get-Content ".\config\credentials.json" | ConvertFrom-Json | Format-List
```

---

## ⚠️ IMPORTANTE

1. **NO subas `credentials.json` a GitHub** (ya está protegido por `.gitignore`)
2. **Haz backup de este archivo** antes de editarlo
3. **Verifica la sintaxis JSON** después de editar (usa VS Code para validación automática)
4. **Los scripts leen automáticamente** este archivo, no necesitas cambiar código

---

## 📝 EJEMPLO DE CAMBIO RÁPIDO

Para cambiar de VPS origen de Civer-Two a Civer-One:

```powershell
$config = Get-Content ".\config\credentials.json" -Raw | ConvertFrom-Json
$config.vpsOrigen.name = "Civer-One"
$config.vpsOrigen.ip = "216.238.80.222"
$config.vpsOrigen.password = "g#7UH-jM{otz9bd@"
$config | ConvertTo-Json -Depth 10 | Set-Content ".\config\credentials.json"
```

---

## 🎯 FLUJO ACTUAL DEL SISTEMA

```
VPS ORIGEN (Civer-Two)
   📦 216.238.88.126
        ⬇️ Backup BMR
        
OBJECT STORAGE (Vultr)
   ☁️ lax1.vultrobjects.com
   📦 bucket: backups-bmr-civer
        ⬇️ Download
        
VPS DESTINO (RESPALDO-1)
   🎯 216.238.84.243
        ⬇️ Restore BMR
```

---

**Última actualización:** 2025-11-04
**Versión del sistema:** 1.0
**Repository:** https://github.com/aprendeineamx-max/bmr-backup-vps-windows-server
