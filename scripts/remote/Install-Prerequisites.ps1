<#
.SYNOPSIS
    Instala los prerequisitos necesarios en la VPS para el sistema de backup BMR.

.DESCRIPTION
    Instala Windows Server Backup, habilita WinRM, configura firewall,
    y prepara el sistema para realizar backups BMR.

.PARAMETER Target
    Especifica si es para VPS Origen o Destino.

.EXAMPLE
    .\Install-Prerequisites.ps1 -Target Origen

.NOTES
    Debe ejecutarse con privilegios de administrador.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Origen', 'Destino', 'Hub')]
    [string]$Target
)

# Importar logger
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "..\utils\Logger.ps1")

Initialize-Logger -LogName "install-prerequisites"

Write-LogInfo "========================================"
Write-LogInfo "Instalando prerequisitos para: $Target"
Write-LogInfo "========================================"

# Verificar privilegios de administrador
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-LogError "Este script debe ejecutarse como Administrador"
    exit 1
}

# 1. Instalar Windows Server Backup
Write-LogInfo "Verificando Windows Server Backup..."
$wsbFeature = Get-WindowsFeature -Name Windows-Server-Backup

if ($wsbFeature.Installed) {
    Write-LogSuccess "Windows Server Backup ya está instalado"
}
else {
    Write-LogInfo "Instalando Windows Server Backup..."
    try {
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeAllSubFeature
        Write-LogSuccess "Windows Server Backup instalado correctamente"
    }
    catch {
        Write-LogError "Error instalando Windows Server Backup: $_"
        exit 1
    }
}

# 2. Habilitar WinRM para gestión remota
Write-LogInfo "Configurando WinRM..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    
    # Configurar TrustedHosts (para conexiones remotas)
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    
    # Aumentar límites de memoria
    Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 2048
    Set-Item WSMan:\localhost\Plugin\Microsoft.PowerShell\Quotas\MaxMemoryPerShellMB -Value 2048
    
    # Reiniciar servicio WinRM
    Restart-Service WinRM -Force
    
    Write-LogSuccess "WinRM configurado correctamente"
}
catch {
    Write-LogError "Error configurando WinRM: $_"
}

# 3. Configurar Firewall
Write-LogInfo "Configurando reglas de firewall..."
try {
    # Permitir WinRM
    Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
    
    # Permitir File and Printer Sharing (para SMB si se usa)
    Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
    
    Write-LogSuccess "Firewall configurado"
}
catch {
    Write-LogError "Error configurando firewall: $_"
}

# 4. Crear directorios necesarios
Write-LogInfo "Creando estructura de directorios..."
$directories = @(
    "C:\BackupTemp",
    "C:\BMR-Backup-System",
    "C:\BMR-Backup-System\Logs"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-LogInfo "Directorio creado: $dir"
    }
}

# 5. Configurar políticas de ejecución
Write-LogInfo "Configurando políticas de PowerShell..."
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    Write-LogSuccess "Políticas de ejecución configuradas"
}
catch {
    Write-LogWarning "No se pudo configurar política de ejecución: $_"
}

# 6. Instalar AWS CLI si no está presente (para Object Storage)
Write-LogInfo "Verificando AWS CLI..."
$awsCli = Get-Command aws -ErrorAction SilentlyContinue

if (-not $awsCli) {
    Write-LogInfo "AWS CLI no encontrado. Instalando..."
    
    try {
        $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
        $installerPath = Join-Path $env:TEMP "AWSCLIV2.msi"
        
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait -NoNewWindow
        Remove-Item $installerPath -Force
        
        Write-LogSuccess "AWS CLI instalado"
    }
    catch {
        Write-LogWarning "No se pudo instalar AWS CLI automáticamente: $_"
        Write-LogWarning "Puede instalarlo manualmente desde: https://aws.amazon.com/cli/"
    }
}
else {
    Write-LogSuccess "AWS CLI ya está instalado"
}

# 7. Verificar espacio en disco
Write-LogInfo "Verificando espacio en disco..."
$drive = Get-PSDrive -Name C
$freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
$usedSpaceGB = [math]::Round($drive.Used / 1GB, 2)

Write-LogInfo "Disco C: - Usado: $usedSpaceGB GB, Libre: $freeSpaceGB GB"

if ($freeSpaceGB -lt 50) {
    Write-LogWarning "Espacio libre bajo en disco C: (${freeSpaceGB} GB)"
    Write-LogWarning "Se recomienda al menos 50 GB libres para backups temporales"
}

# 8. Deshabilitar hibernación y pagefile para ahorrar espacio (opcional)
if ($Target -eq 'Origen') {
    Write-LogInfo "Optimizando espacio en disco..."
    
    try {
        # Deshabilitar hibernación
        powercfg -h off
        Write-LogInfo "Hibernación deshabilitada (liberando espacio)"
    }
    catch {
        Write-LogWarning "No se pudo deshabilitar hibernación: $_"
    }
}

# 9. Configurar servicios necesarios
Write-LogInfo "Configurando servicios..."
$services = @(
    @{ Name = "wbengine"; DisplayName = "Windows Backup" },
    @{ Name = "vss"; DisplayName = "Volume Shadow Copy" },
    @{ Name = "WinRM"; DisplayName = "Windows Remote Management" }
)

foreach ($svc in $services) {
    try {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.StartType -ne 'Automatic') {
                Set-Service -Name $svc.Name -StartupType Automatic
                Write-LogInfo "$($svc.DisplayName): Configurado para inicio automático"
            }
            if ($service.Status -ne 'Running') {
                Start-Service -Name $svc.Name
                Write-LogInfo "$($svc.DisplayName): Iniciado"
            }
        }
    }
    catch {
        Write-LogWarning "Error configurando servicio $($svc.Name): $_"
    }
}

# 10. Verificar versión de PowerShell
Write-LogInfo "Verificando versión de PowerShell..."
$psVersion = $PSVersionTable.PSVersion
Write-LogInfo "PowerShell versión: $($psVersion.Major).$($psVersion.Minor)"

if ($psVersion.Major -lt 5) {
    Write-LogWarning "Se recomienda PowerShell 5.1 o superior"
}

# 11. Test de conectividad (solo para verificación)
Write-LogInfo "Probando conectividad a Object Storage..."
try {
    $testConnection = Test-NetConnection -ComputerName "lax1.vultrobjects.com" -Port 443 -WarningAction SilentlyContinue
    if ($testConnection.TcpTestSucceeded) {
        Write-LogSuccess "Conectividad a Object Storage: OK"
    }
    else {
        Write-LogWarning "No se pudo conectar a Object Storage"
    }
}
catch {
    Write-LogWarning "Error probando conectividad: $_"
}

Write-LogInfo ""
Write-LogSuccess "========================================"
Write-LogSuccess "Instalación completada para: $Target"
Write-LogSuccess "========================================"
Write-LogInfo ""
Write-LogInfo "Información del sistema:"
Write-LogInfo "  - OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-LogInfo "  - Hostname: $env:COMPUTERNAME"
Write-LogInfo "  - Espacio libre C:: $freeSpaceGB GB"
Write-LogInfo "  - Windows Server Backup: Instalado"
Write-LogInfo "  - WinRM: Habilitado"
Write-LogInfo ""

# Crear archivo de verificación
$verificationFile = "C:\BMR-Backup-System\prerequisites-installed.txt"
@"
Prerequisites instalados: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Target: $Target
Hostname: $env:COMPUTERNAME
OS: $((Get-CimInstance Win32_OperatingSystem).Caption)
PowerShell: $($psVersion.Major).$($psVersion.Minor)
"@ | Out-File -FilePath $verificationFile -Force

Write-LogInfo "Archivo de verificación creado: $verificationFile"
