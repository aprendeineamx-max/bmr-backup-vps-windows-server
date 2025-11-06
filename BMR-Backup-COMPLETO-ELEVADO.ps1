# Backup COMPLETO con permisos elevados - Users + ProgramData
# Ejecutar desde Civer-One, respalda Civer-Two COMPLETO

param(
    [string]$TargetIP = "216.238.88.126",
    [string]$Username = "Administrator", 
    [string]$Password = "6K#fVnH-arJG-(wT"
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BACKUP COMPLETO CON PERMISOS ELEVADOS" -ForegroundColor Green  
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Conectando a $TargetIP..." -ForegroundColor Cyan
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential($Username, $secPass)
$session = New-PSSession -ComputerName $TargetIP -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Write-Host "[OK] Sesion establecida`n" -ForegroundColor Green

# Script remoto con SYSTEM privileges
$remoteScript = {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "CIVER-TWO-FULL-$timestamp"
    $backupDir = "C:\BackupTemp\$backupName"
    $logFile = "C:\BackupTemp\$backupName-log.txt"
    
    function Log { param($msg) "$([DateTime]::Now.ToString('HH:mm:ss')) $msg" | Tee-Object -FilePath $logFile -Append | Write-Host }
    
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    
    Log "===== BACKUP COMPLETO CON PERMISOS ELEVADOS ====="
    Log "Servidor: $env:COMPUTERNAME"
    
    # Habilitar privilegios SYSTEM temporalmente
    Log "`n[PASO 1/4] Habilitando privilegios de backup..."
    
    try {
        # Usar PsExec para ejecutar como SYSTEM (alternativa)
        # O habilitar SeBackupPrivilege directamente
        
        $signature = @"
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, 
            ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
        
        [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);
        
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }
        
        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }
        
        public const uint SE_PRIVILEGE_ENABLED = 0x00000002;
        public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        public const uint TOKEN_QUERY = 0x0008;
"@
        
        try {
            Add-Type -MemberDefinition $signature -Name 'PrivilegeManager' -Namespace 'Win32' -ErrorAction SilentlyContinue
            
            $process = [System.Diagnostics.Process]::GetCurrentProcess()
            $token = [IntPtr]::Zero
            [Win32.PrivilegeManager]::OpenProcessToken($process.Handle, 0x0028, [ref]$token) | Out-Null
            
            $luid = New-Object Win32.PrivilegeManager+LUID
            [Win32.PrivilegeManager]::LookupPrivilegeValue($null, "SeBackupPrivilege", [ref]$luid) | Out-Null
            
            $tokenPrivileges = New-Object Win32.PrivilegeManager+TOKEN_PRIVILEGES
            $tokenPrivileges.PrivilegeCount = 1
            $tokenPrivileges.Luid = $luid
            $tokenPrivileges.Attributes = 0x00000002
            
            [Win32.PrivilegeManager]::AdjustTokenPrivileges($token, $false, [ref]$tokenPrivileges, 0, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            
            Log "  [OK] SeBackupPrivilege habilitado"
        } catch {
            Log "  [!] No se pudo habilitar SeBackupPrivilege: $_"
        }
        
        # Carpetas a respaldar CON permisos completos
        $foldersToBackup = @(
            @{Source="C:\Users"; Dest="Users"; Priority="High"},
            @{Source="C:\ProgramData"; Dest="ProgramData"; Priority="High"},
            @{Source="C:\Program Files\Common Files"; Dest="ProgramFilesCommon"; Priority="Medium"},
            @{Source="C:\Windows\System32\config"; Dest="WindowsConfig"; Priority="Critical"}
        )
        
        Log "`n[PASO 2/4] Copiando archivos con privilegios elevados..."
        $totalCopied = 0
        
        foreach($folder in $foldersToBackup){
            $source = $folder.Source
            $dest = Join-Path $backupDir $folder.Dest
            
            if(!(Test-Path $source)){
                Log "  SKIP: $source no existe"
                continue
            }
            
            Log "  Copiando: $source (Prioridad: $($folder.Priority))"
            
            try {
                # Usar robocopy con flags de backup (/B)
                # /B = Backup mode (usa SeBackupPrivilege)
                # /ZB = Usa restart mode si /B falla
                # /COPYALL = Copia TODO (permisos, auditoría, etc)
                
                $robocopyArgs = @(
                    "`"$source`"",
                    "`"$dest`"",
                    "/E",           # Subdirectorios incluyendo vacíos
                    "/B",           # Modo backup (SeBackupPrivilege)
                    "/ZB",          # Restart mode si /B falla
                    "/COPYALL",     # Copia permisos, owner, auditoría
                    "/R:2",         # 2 reintentos
                    "/W:1",         # 1 segundo entre reintentos
                    "/MT:2",        # 2 threads
                    "/XJ",          # Excluir junction points
                    "/XD",          # Excluir directorios
                    "`"*\AppData\Local\Temp`"",
                    "`"*\Downloads`"",
                    "`"*\Temporary Internet Files`"",
                    "`"*\Cache`"",
                    "/NFL",         # No file list
                    "/NDL",         # No directory list
                    "/NJH",         # No job header
                    "/NJS"          # No job summary
                )
                
                $robocopyCmd = "robocopy " + ($robocopyArgs -join ' ')
                $robocopyLog = Join-Path $backupDir "robocopy_$($folder.Dest).log"
                
                # Ejecutar robocopy
                $result = Invoke-Expression "$robocopyCmd /LOG:`"$robocopyLog`"" 2>&1
                
                # Robocopy exit codes: 0-7 son éxito, 8+ son errores
                $exitCode = $LASTEXITCODE
                
                if($exitCode -le 7){
                    if(Test-Path $dest){
                        $size = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                        $sizeMB = [math]::Round($size/1MB, 2)
                        Log "    [OK] Copiado: $sizeMB MB (codigo: $exitCode)"
                        $totalCopied += $sizeMB
                    } else {
                        Log "    [!] Directorio vacio o sin archivos"
                    }
                } else {
                    Log "    [ERROR] Robocopy fallo (codigo: $exitCode)"
                    Log "    Ver log: $robocopyLog"
                }
                
            } catch {
                Log "    [ERROR] Excepcion: $_"
            }
        }
        
        Log "`nTotal copiado: $totalCopied MB ($([math]::Round($totalCopied/1024,2)) GB)"
        
        # Comprimir
        Log "`n[PASO 3/4] Comprimiendo backup..."
        $7zip = "C:\Program Files\7-Zip\7z.exe"
        
        if(!(Test-Path $7zip)){
            Log "  Instalando 7-Zip..."
            try {
                $7zipUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
                $installer = "$env:TEMP\7zip.msi"
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $7zipUrl -OutFile $installer -UseBasicParsing -TimeoutSec 120
                Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /norestart"
                Log "  [OK] 7-Zip instalado"
            } catch {
                Log "  [ERROR] No se pudo instalar 7-Zip: $_"
                return @{Success=$false; Error="7-Zip install failed"; TotalCopiedMB=$totalCopied}
            }
        }
        
        $zipFile = "C:\BackupTemp\$backupName.7z"
        Log "  Comprimiendo: $zipFile"
        Log "  (Dividido en partes de 500MB para facilitar transferencia)"
        
        $sourcePattern = $backupDir + "\*"
        & $7zip a -t7z -mx=5 -mmt=on -v500m $zipFile $sourcePattern 2>&1 | Out-Null
        
        if($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1){
            Log "  [ERROR] Compresion fallo (codigo: $LASTEXITCODE)"
            return @{Success=$false; Error="Compression failed"; TotalCopiedMB=$totalCopied}
        }
        
        $pattern = "$backupName.7z.*"
        $parts = Get-ChildItem "C:\BackupTemp" -Filter $pattern -ErrorAction SilentlyContinue
        
        if(!$parts){
            Log "  [ERROR] No se crearon archivos comprimidos"
            return @{Success=$false; Error="No compressed files"; TotalCopiedMB=$totalCopied}
        }
        
        $totalSize = ($parts | Measure-Object Length -Sum).Sum
        $totalGB = [math]::Round($totalSize/1GB, 2)
        Log "  [OK] Backup comprimido: $($parts.Count) partes, $totalGB GB total"
        
        # Listar archivos
        Log "`n[PASO 4/4] Archivos creados:"
        foreach($part in $parts){
            $partSizeMB = [math]::Round($part.Length/1MB, 2)
            Log "  - $($part.Name): $partSizeMB MB"
        }
        
        Log "`n===== BACKUP COMPLETADO ====="
        Log "Datos copiados: $totalCopied MB"
        Log "Comprimido a: $totalGB GB"
        Log "Partes: $($parts.Count)"
        Log "Ubicacion: C:\BackupTemp\"
        Log "Log: $logFile"
        
        return @{
            Success = $true
            BackupName = $backupName
            PartsCreated = $parts.Count
            TotalSizeGB = $totalGB
            TotalCopiedMB = $totalCopied
            LogFile = $logFile
            Parts = $parts | ForEach-Object { @{Name=$_.Name; SizeMB=[math]::Round($_.Length/1MB,2)} }
        }
        
    } catch {
        Log "[ERROR] Excepcion general: $_"
        return @{Success=$false; Error=$_.Exception.Message}
    }
}

Write-Host "Ejecutando backup COMPLETO (tiempo estimado: 60-120 min)...`n" -ForegroundColor Yellow

try {
    $result = Invoke-Command -Session $session -ScriptBlock $remoteScript
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "RESULTADO FINAL" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    if($result.Success){
        Write-Host "[OK] Backup COMPLETO exitoso!" -ForegroundColor Green
        Write-Host "`nEstadisticas:" -ForegroundColor Cyan
        Write-Host "  Datos copiados: $($result.TotalCopiedMB) MB ($([math]::Round($result.TotalCopiedMB/1024,2)) GB)" -ForegroundColor White
        Write-Host "  Comprimido a: $($result.TotalSizeGB) GB" -ForegroundColor White
        Write-Host "  Partes: $($result.PartsCreated)" -ForegroundColor White
        
        Write-Host "`nArchivos creados:" -ForegroundColor Cyan
        foreach($part in $result.Parts){
            Write-Host "  - $($part.Name): $($part.SizeMB) MB" -ForegroundColor White
        }
        
        Write-Host "`nUbicaciones:" -ForegroundColor Cyan
        Write-Host "  Local en Civer-Two: C:\BackupTemp\$($result.BackupName)*" -ForegroundColor White
        Write-Host "  Log: $($result.LogFile)" -ForegroundColor White
        
        Write-Host "`nPROXIMO PASO:" -ForegroundColor Yellow
        Write-Host "  Copiar archivos desde Civer-Two a Civer-One..." -ForegroundColor White
        
        # Copiar archivos a Civer-One
        Write-Host "`n[COPIANDO A CIVER-ONE]..." -ForegroundColor Cyan
        $copied = 0
        $failed = 0
        
        foreach($part in $result.Parts){
            $remotePath = "C:\BackupTemp\$($part.Name)"
            $localPath = "C:\BackupTemp\$($part.Name)"
            
            try {
                Write-Host "  Copiando: $($part.Name) ($($part.SizeMB) MB)" -ForegroundColor Gray
                Copy-Item -Path $remotePath -Destination $localPath -FromSession $session -Force -ErrorAction Stop
                
                if(Test-Path $localPath){
                    Write-Host "    [OK] Copiado" -ForegroundColor Green
                    $copied++
                } else {
                    Write-Host "    [ERROR] No verificado" -ForegroundColor Red
                    $failed++
                }
            } catch {
                Write-Host "    [ERROR] $_" -ForegroundColor Red
                $failed++
            }
        }
        
        Write-Host "`n[RESUMEN COPIA]" -ForegroundColor Cyan
        Write-Host "  Copiados: $copied de $($result.PartsCreated)" -ForegroundColor White
        Write-Host "  Fallidos: $failed" -ForegroundColor $(if($failed -gt 0){'Yellow'}else{'Green'})
        Write-Host "  Ubicacion en Civer-One: C:\BackupTemp\" -ForegroundColor Cyan
        
    } else {
        Write-Host "[ERROR] Backup fallo" -ForegroundColor Red
        Write-Host "  Error: $($result.Error)" -ForegroundColor Yellow
        if($result.TotalCopiedMB){
            Write-Host "  Datos copiados antes del error: $($result.TotalCopiedMB) MB" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "[ERROR] Excepcion: $_" -ForegroundColor Red
} finally {
    Remove-PSSession $session
    Write-Host "`nSesion cerrada." -ForegroundColor Gray
}
