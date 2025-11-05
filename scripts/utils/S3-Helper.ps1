<#
.SYNOPSIS
    Funciones helper para trabajar con Vultr Object Storage (S3-compatible).

.DESCRIPTION
    Proporciona funciones para subir, descargar y gestionar archivos en
    Vultr Object Storage usando AWS CLI o s3cmd.

.NOTES
    Author: BMR Backup System
    Version: 1.0
#>

. (Join-Path $PSScriptRoot "Logger.ps1")

function Test-S3Tools {
    [CmdletBinding()]
    param()
    
    $awsInstalled = Get-Command aws -ErrorAction SilentlyContinue
    $s3cmdInstalled = Get-Command s3cmd -ErrorAction SilentlyContinue
    
    return @{
        AWS    = $null -ne $awsInstalled
        S3CMD  = $null -ne $s3cmdInstalled
        HasAny = ($null -ne $awsInstalled) -or ($null -ne $s3cmdInstalled)
    }
}

function Install-AWSCLI {
    [CmdletBinding()]
    param()
    
    Write-LogInfo "Instalando AWS CLI..."
    
    try {
        # Descargar instalador
        $installerUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
        $installerPath = Join-Path $env:TEMP "AWSCLIV2.msi"
        
        Write-LogInfo "Descargando AWS CLI desde $installerUrl..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        
        # Instalar
        Write-LogInfo "Instalando AWS CLI..."
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait -NoNewWindow
        
        # Limpiar
        Remove-Item $installerPath -Force
        
        Write-LogSuccess "AWS CLI instalado correctamente"
        return $true
    }
    catch {
        Write-LogError "Error instalando AWS CLI: $_"
        return $false
    }
}

function Initialize-S3Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$S3Config
    )
    
    $tools = Test-S3Tools
    
    if (-not $tools.HasAny) {
        Write-LogWarning "No se encontró AWS CLI ni s3cmd. Instalando AWS CLI..."
        if (-not (Install-AWSCLI)) {
            throw "No se pudo instalar AWS CLI"
        }
    }
    
    # Configurar AWS CLI
    if ($tools.AWS -or (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-LogInfo "Configurando AWS CLI para Vultr Object Storage..."
        
        $env:AWS_ACCESS_KEY_ID = $S3Config.accessKey
        $env:AWS_SECRET_ACCESS_KEY = $S3Config.secretKey
        $env:AWS_DEFAULT_REGION = $S3Config.region
        
        Write-LogSuccess "AWS CLI configurado"
    }
}

function Test-S3Bucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket
    )
    
    try {
        $result = & aws s3 ls "s3://$Bucket" --endpoint-url "https://$Endpoint" 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function New-S3Bucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket
    )
    
    Write-LogInfo "Creando bucket: $Bucket"
    
    try {
        & aws s3 mb "s3://$Bucket" --endpoint-url "https://$Endpoint"
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Bucket creado: $Bucket"
            return $true
        }
        else {
            Write-LogError "Error creando bucket"
            return $false
        }
    }
    catch {
        Write-LogError "Excepción creando bucket: $_"
        return $false
    }
}

function Send-FileToS3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket,
        
        [string]$S3Key,
        
        [switch]$ShowProgress
    )
    
    if (-not (Test-Path $FilePath)) {
        throw "Archivo no encontrado: $FilePath"
    }
    
    if (-not $S3Key) {
        $S3Key = Split-Path $FilePath -Leaf
    }
    
    $fileSize = (Get-Item $FilePath).Length / 1GB
    Write-LogInfo "Subiendo archivo a S3: $FilePath ($('{0:N2}' -f $fileSize) GB)"
    Write-LogInfo "Destino: s3://$Bucket/$S3Key"
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $args = @(
            "s3", "cp",
            "`"$FilePath`"",
            "s3://$Bucket/$S3Key",
            "--endpoint-url", "https://$Endpoint"
        )
        
        if ($ShowProgress) {
            $args += "--no-progress"  # Evitar spam en logs
        }
        
        $process = Start-Process -FilePath "aws" -ArgumentList $args -NoNewWindow -Wait -PassThru
        
        $stopwatch.Stop()
        
        if ($process.ExitCode -eq 0) {
            $elapsed = $stopwatch.Elapsed.TotalSeconds
            $speedMBps = ($fileSize * 1024) / $elapsed
            
            Write-LogSuccess "Archivo subido correctamente en $([math]::Round($elapsed, 2)) segundos"
            Write-LogInfo "Velocidad promedio: $('{0:N2}' -f $speedMBps) MB/s"
            return $true
        }
        else {
            Write-LogError "Error subiendo archivo. Código de salida: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Excepción subiendo archivo: $_"
        return $false
    }
}

function Get-FileFromS3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$S3Key,
        
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        
        [switch]$ShowProgress
    )
    
    Write-LogInfo "Descargando desde S3: s3://$Bucket/$S3Key"
    Write-LogInfo "Destino: $DestinationPath"
    
    # Crear directorio si no existe
    $destDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $args = @(
            "s3", "cp",
            "s3://$Bucket/$S3Key",
            "`"$DestinationPath`"",
            "--endpoint-url", "https://$Endpoint"
        )
        
        if ($ShowProgress) {
            $args += "--no-progress"
        }
        
        $process = Start-Process -FilePath "aws" -ArgumentList $args -NoNewWindow -Wait -PassThru
        
        $stopwatch.Stop()
        
        if ($process.ExitCode -eq 0) {
            $fileSize = (Get-Item $DestinationPath).Length / 1GB
            $elapsed = $stopwatch.Elapsed.TotalSeconds
            $speedMBps = ($fileSize * 1024) / $elapsed
            
            Write-LogSuccess "Archivo descargado correctamente en $([math]::Round($elapsed, 2)) segundos"
            Write-LogInfo "Velocidad promedio: $('{0:N2}' -f $speedMBps) MB/s"
            return $true
        }
        else {
            Write-LogError "Error descargando archivo. Código de salida: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Excepción descargando archivo: $_"
        return $false
    }
}

function Get-S3Objects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket,
        
        [string]$Prefix = ""
    )
    
    try {
        $args = @(
            "s3", "ls",
            "s3://$Bucket/$Prefix",
            "--endpoint-url", "https://$Endpoint"
        )
        
        $output = & aws @args 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            return $output
        }
        else {
            Write-LogWarning "No se pudieron listar objetos en S3"
            return @()
        }
    }
    catch {
        Write-LogError "Error listando objetos S3: $_"
        return @()
    }
}

function Remove-S3Object {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$S3Key,
        
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory = $true)]
        [string]$Bucket
    )
    
    Write-LogInfo "Eliminando objeto S3: s3://$Bucket/$S3Key"
    
    try {
        & aws s3 rm "s3://$Bucket/$S3Key" --endpoint-url "https://$Endpoint"
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Objeto eliminado"
            return $true
        }
        else {
            Write-LogError "Error eliminando objeto"
            return $false
        }
    }
    catch {
        Write-LogError "Excepción eliminando objeto: $_"
        return $false
    }
}

# Exportar funciones
Export-ModuleMember -Function @(
    'Test-S3Tools',
    'Install-AWSCLI',
    'Initialize-S3Config',
    'Test-S3Bucket',
    'New-S3Bucket',
    'Send-FileToS3',
    'Get-FileFromS3',
    'Get-S3Objects',
    'Remove-S3Object'
)
