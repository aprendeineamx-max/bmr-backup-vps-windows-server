<#
.SYNOPSIS
    Sistema de logging unificado para el sistema de backup BMR.

.DESCRIPTION
    Proporciona funciones para logging con diferentes niveles de severidad,
    rotación de logs, y formato consistente.

.NOTES
    Author: BMR Backup System
    Version: 1.0
#>

$Script:LogPath = Join-Path $PSScriptRoot "..\..\logs"
$Script:LogFile = $null

function Initialize-Logger {
    [CmdletBinding()]
    param(
        [string]$LogName = "backup",
        [string]$LogDirectory = $Script:LogPath
    )
    
    # Crear directorio de logs si no existe
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Crear nombre de archivo con fecha
    $timestamp = Get-Date -Format "yyyy-MM-dd"
    $Script:LogFile = Join-Path $LogDirectory "$LogName-$timestamp.log"
    
    # Escribir header
    $header = @"
================================================================================
Log iniciado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Sistema: $env:COMPUTERNAME
Usuario: $env:USERNAME
================================================================================
"@
    Add-Content -Path $Script:LogFile -Value $header
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsole
    )
    
    # Inicializar logger si no está inicializado
    if (-not $Script:LogFile) {
        Initialize-Logger
    }
    
    # Formato del mensaje
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Escribir a archivo
    try {
        Add-Content -Path $Script:LogFile -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "No se pudo escribir al log: $_"
    }
    
    # Escribir a consola con colores
    if (-not $NoConsole) {
        $color = switch ($Level) {
            'INFO'    { 'White' }
            'WARNING' { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Gray' }
            default   { 'White' }
        }
        
        Write-Host $logMessage -ForegroundColor $color
    }
}

function Write-LogInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Log -Message $Message -Level 'INFO'
}

function Write-LogWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Log -Message $Message -Level 'WARNING'
}

function Write-LogError {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Log -Message $Message -Level 'ERROR'
}

function Write-LogSuccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Log -Message $Message -Level 'SUCCESS'
}

function Write-LogDebug {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    if ($DebugPreference -ne 'SilentlyContinue') {
        Write-Log -Message $Message -Level 'DEBUG'
    }
}

function Get-LogContent {
    [CmdletBinding()]
    param(
        [int]$Tail = 50,
        [switch]$All
    )
    
    if (-not $Script:LogFile -or -not (Test-Path $Script:LogFile)) {
        Write-Warning "No hay archivo de log disponible"
        return
    }
    
    if ($All) {
        Get-Content $Script:LogFile
    }
    else {
        Get-Content $Script:LogFile -Tail $Tail
    }
}

function Clear-OldLogs {
    [CmdletBinding()]
    param(
        [int]$DaysToKeep = 30,
        [string]$LogDirectory = $Script:LogPath
    )
    
    if (-not (Test-Path $LogDirectory)) {
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
    
    Get-ChildItem -Path $LogDirectory -Filter "*.log" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Write-LogInfo "Eliminando log antiguo: $($_.Name)"
            Remove-Item $_.FullName -Force
        }
}

# Exportar funciones
Export-ModuleMember -Function @(
    'Initialize-Logger',
    'Write-Log',
    'Write-LogInfo',
    'Write-LogWarning',
    'Write-LogError',
    'Write-LogSuccess',
    'Write-LogDebug',
    'Get-LogContent',
    'Clear-OldLogs'
)
