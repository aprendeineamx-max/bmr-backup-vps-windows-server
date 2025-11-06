# ============================================================
# VERIFICAR ESTADO DE AMBOS PROCESOS
# Ejecutar desde Civer-One para monitorear progreso
# ============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VERIFICANDO ESTADO DE PROCESOS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Configuración
$respaldo1IP = "216.238.84.243"
$civerTwoIP = "216.238.88.126"
$respaldo1Pass = "VL0jh-eDuT7+ftUz"
$civerTwoPass = "6K#fVnH-arJG-(wT"

# ============================================================
# PROCESO 1: Verificar PSRemoting en RESPALDO-1
# ============================================================
Write-Host "[1/2] Verificando RESPALDO-1 (PSRemoting)..." -ForegroundColor Yellow

$pass1 = ConvertTo-SecureString $respaldo1Pass -AsPlainText -Force
$cred1 = New-Object PSCredential("Administrator", $pass1)

try {
    $session1 = New-PSSession -ComputerName $respaldo1IP -Credential $cred1 -ErrorAction Stop
    
    Write-Host "  [OK] PSRemoting funcionando en RESPALDO-1" -ForegroundColor Green
    
    # Verificar espacio y archivos
    $info1 = Invoke-Command -Session $session1 -ScriptBlock {
        $disk = Get-PSDrive C
        $backupFiles = Get-ChildItem "C:\BackupTemp\" -Filter "*.7z.*" -ErrorAction SilentlyContinue
        
        return @{
            FreeGB = [math]::Round($disk.Free/1GB, 2)
            UsedGB = [math]::Round($disk.Used/1GB, 2)
            BackupFiles = $backupFiles.Count
            BackupSizeGB = if($backupFiles) { [math]::Round(($backupFiles | Measure-Object Length -Sum).Sum/1GB, 2) } else { 0 }
        }
    }
    
    Write-Host "  Disco C: $($info1.FreeGB) GB libres, $($info1.UsedGB) GB usados" -ForegroundColor White
    
    if ($info1.BackupFiles -gt 0) {
        Write-Host "  [OK] Archivos de backup encontrados: $($info1.BackupFiles) ($($info1.BackupSizeGB) GB)" -ForegroundColor Green
        
        # Verificar si ya se extrajo
        $extracted = Invoke-Command -Session $session1 -ScriptBlock {
            Test-Path "C:\BackupTemp\CIVER-TWO-BMR-COMPLETO-*\Users"
        }
        
        if ($extracted) {
            Write-Host "  [OK] Backup ya extraído - Proceso completado" -ForegroundColor Green
        } else {
            Write-Host "  [INFO] Archivos transferidos, pendiente extracción" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INFO] Sin archivos de backup - Pendiente transferencia" -ForegroundColor Yellow
        Write-Host "  Ejecuta: Restaurar-RESPALDO1-Simple.ps1" -ForegroundColor Cyan
    }
    
    Remove-PSSession $session1
    
} catch {
    Write-Host "  [ERROR] No se puede conectar a RESPALDO-1" -ForegroundColor Red
    Write-Host "  Causa: PSRemoting no habilitado" -ForegroundColor Yellow
    Write-Host "  Solución: Conecta por RDP y ejecuta:" -ForegroundColor Cyan
    Write-Host "    Enable-PSRemoting -Force" -ForegroundColor White
    Write-Host "    Restart-Service WinRM -Force" -ForegroundColor White
}

# ============================================================
# PROCESO 2: Verificar Macrium en Civer-Two
# ============================================================
Write-Host "`n[2/2] Verificando Civer-Two (Macrium)..." -ForegroundColor Yellow

$pass2 = ConvertTo-SecureString $civerTwoPass -AsPlainText -Force
$cred2 = New-Object PSCredential("Administrator", $pass2)

try {
    $session2 = New-PSSession -ComputerName $civerTwoIP -Credential $cred2 -ErrorAction Stop
    
    Write-Host "  [OK] Conectado a Civer-Two" -ForegroundColor Green
    
    # Verificar Macrium
    $info2 = Invoke-Command -Session $session2 -ScriptBlock {
        $result = @{
            MacriumInstalled = $false
            MacriumPath = $null
            InstallerPath = $null
            ImageFiles = 0
            ImageSizeGB = 0
            ISOExists = $false
            ISOSizeGB = 0
        }
        
        # Verificar instalación
        $paths = @(
            "C:\Program Files\Macrium\Reflect\Reflect.exe",
            "C:\Program Files (x86)\Macrium\Reflect\Reflect.exe"
        )
        
        foreach ($path in $paths) {
            if (Test-Path $path) {
                $result.MacriumInstalled = $true
                $result.MacriumPath = $path
                break
            }
        }
        
        # Verificar instalador
        if (Test-Path "C:\Users\Administrator\Desktop\MacriumReflect.exe") {
            $result.InstallerPath = "C:\Users\Administrator\Desktop\MacriumReflect.exe"
        }
        
        # Verificar imágenes creadas
        $imageFiles = Get-ChildItem "C:\BackupTemp\" -Filter "*.mrimg" -Recurse -ErrorAction SilentlyContinue
        if ($imageFiles) {
            $result.ImageFiles = $imageFiles.Count
            $result.ImageSizeGB = [math]::Round(($imageFiles | Measure-Object Length -Sum).Sum/1GB, 2)
        }
        
        # Verificar ISO de rescate
        $isoFile = Get-ChildItem "C:\BackupTemp\" -Filter "Macrium-Rescue-Media.iso" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($isoFile) {
            $result.ISOExists = $true
            $result.ISOSizeGB = [math]::Round($isoFile.Length/1GB, 2)
        }
        
        return $result
    }
    
    if ($info2.MacriumInstalled) {
        Write-Host "  [OK] Macrium Reflect instalado" -ForegroundColor Green
        Write-Host "  Ruta: $($info2.MacriumPath)" -ForegroundColor White
        
        if ($info2.ImageFiles -gt 0) {
            Write-Host "  [OK] Imagen de disco creada: $($info2.ImageFiles) archivo(s) ($($info2.ImageSizeGB) GB)" -ForegroundColor Green
        } else {
            Write-Host "  [INFO] Pendiente crear imagen de disco" -ForegroundColor Yellow
            Write-Host "  Ejecuta: Crear-ISO-Booteable-Macrium.ps1" -ForegroundColor Cyan
            Write-Host "  O usa la interfaz gráfica de Macrium Reflect" -ForegroundColor Cyan
        }
        
        if ($info2.ISOExists) {
            Write-Host "  [OK] ISO de rescate creado ($($info2.ISOSizeGB) GB)" -ForegroundColor Green
        } else {
            Write-Host "  [INFO] Pendiente crear ISO de rescate booteable" -ForegroundColor Yellow
            Write-Host "  En Macrium: Other Tasks → Create Rescue Media" -ForegroundColor Cyan
        }
        
    } else {
        Write-Host "  [INFO] Macrium Reflect NO instalado" -ForegroundColor Yellow
        
        if ($info2.InstallerPath) {
            Write-Host "  Instalador disponible en: $($info2.InstallerPath)" -ForegroundColor White
            Write-Host "  Conecta por RDP y ejecuta el instalador" -ForegroundColor Cyan
        } else {
            Write-Host "  [WARNING] Instalador no encontrado" -ForegroundColor Yellow
            Write-Host "  Descarga desde: https://www.macrium.com/reflectfree" -ForegroundColor Cyan
        }
    }
    
    Remove-PSSession $session2
    
} catch {
    Write-Host "  [ERROR] No se puede conectar a Civer-Two: $_" -ForegroundColor Red
}

# ============================================================
# RESUMEN
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMEN" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Archivos de backup originales (Civer-One):" -ForegroundColor White
$originalBackup = Get-ChildItem "C:\BackupTemp\CIVER-TWO-BMR-COMPLETO-*.7z.*" -ErrorAction SilentlyContinue
if ($originalBackup) {
    $totalGB = [math]::Round(($originalBackup | Measure-Object Length -Sum).Sum/1GB, 2)
    Write-Host "  [OK] $($originalBackup.Count) archivos ($totalGB GB)" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] No encontrados" -ForegroundColor Red
}

Write-Host "`nPróximas acciones:" -ForegroundColor Cyan
Write-Host "  1. Si RESPALDO-1 no tiene PSRemoting: Habilitar primero" -ForegroundColor Gray
Write-Host "  2. Si Macrium no está instalado: Instalar en Civer-Two" -ForegroundColor Gray
Write-Host "  3. Ejecutar restauración: Restaurar-RESPALDO1-Simple.ps1" -ForegroundColor Gray
Write-Host "  4. Crear imagen booteable: Crear-ISO-Booteable-Macrium.ps1" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Cyan

Write-Host "Presiona Enter para cerrar..." -ForegroundColor Gray
Read-Host
