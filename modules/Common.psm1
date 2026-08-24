# Common.psm1 - Powkiddy A20 搞机工具箱 公共模块

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== 日志函数 =====
function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    Write-Host "  $Msg" -ForegroundColor $Color
}
function Write-OK   { param([string]$Msg) Write-Log "[OK] $Msg" "Green" }
function Write-Info { param([string]$Msg) Write-Log "[..] $Msg" "Cyan" }
function Write-Warn { param([string]$Msg) Write-Log "[!!] $Msg" "Yellow" }
function Write-Err  { param([string]$Msg) Write-Log "[XX] $Msg" "Red" }
function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host "    $Title" -ForegroundColor Cyan
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ===== CRC32 (zlib 兼容) =====
$script:CrcTable = $null

function Initialize-CrcTable {
    if ($null -ne $script:CrcTable) { return }
    $script:CrcTable = New-Object uint32[] 256
    for ($i = 0; $i -lt 256; $i++) {
        [uint32]$c = $i
        for ($j = 0; $j -lt 8; $j++) {
            if (($c -band 1) -ne 0) {
                $c = 0xEDB88320 -bxor ($c -shr 1)
            }
            else {
                $c = $c -shr 1
            }
        }
        $script:CrcTable[$i] = $c
    }
}

function Get-CRC32 {
    param([byte[]]$Data)
    Initialize-CrcTable
    [uint32]$crc = 0xFFFFFFFF
    foreach ($byte in $Data) {
        $index = ($crc -bxor $byte) -band 0xFF
        $crc = $script:CrcTable[$index] -bxor ($crc -shr 8)
    }
    return ($crc -bxor 0xFFFFFFFF)
}

# ===== ADB 操作 =====
$script:AdbPath = $null

function Find-Adb {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $base = Split-Path $scriptDir

    $c1 = Join-Path $base "platform-tools\adb.exe"
    $c2 = Join-Path $scriptDir "platform-tools\adb.exe"

    if (Test-Path $c1) {
        $script:AdbPath = $c1
        Write-Info "ADB: $c1"
        return $true
    }
    if (Test-Path $c2) {
        $script:AdbPath = $c2
        Write-Info "ADB: $c2"
        return $true
    }

    $found = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($found) {
        $script:AdbPath = $found.Source
        Write-Info ("ADB: " + $found.Source)
        return $true
    }

    Write-Err "找不到 adb.exe"
    return $false
}

function Invoke-Adb {
    param([string[]]$Arguments)
    if (-not $script:AdbPath) { return $null }

    $tmpDir = $env:TEMP
    $outFile = Join-Path $tmpDir "_adb_out.tmp"
    $errFile = Join-Path $tmpDir "_adb_err.tmp"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $script:AdbPath
    $pinfo.Arguments = $Arguments -join " "
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    $result = @{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
    return $result
}

function Invoke-AdbShell {
    param([string]$Command)
    $result = Invoke-Adb @("shell", $Command)
    return $result
}

function Test-DeviceConnection {
    $result = Invoke-Adb @("devices")
    if ($result.StdOut -match "device\s") {
        Write-OK "设备已连接"
        return $true
    }
    Write-Err "未检测到设备，请确认 USB 已连接且 ADB 调试已开启"
    return $false
}

function Enable-RootAdb {
    Write-Info "获取 ADB root 权限..."
    Invoke-Adb @("root") | Out-Null
    Start-Sleep -Seconds 3

    $id = Invoke-AdbShell "id"
    if ($id.StdOut -match "uid=0") {
        Write-OK "Root 权限获取成功"
        return $true
    }

    $suId = Invoke-AdbShell "su -c id"
    if ($suId.StdOut -match "uid=0") {
        Write-OK "通过 su 获取 root 成功"
        return $true
    }

    Write-Err "无法获取 root 权限"
    return $false
}

# ===== 设备操作辅助 =====
function Get-DeviceCmdline {
    $r = Invoke-AdbShell "cat /proc/cmdline"
    if ($r.ExitCode -ne 0) {
        $r = Invoke-AdbShell "su -c 'cat /proc/cmdline'"
    }
    return $r.StdOut.Trim()
}

function Get-MagiskVersion {
    $r = Invoke-AdbShell "su -c 'magisk -v'"
    if ($r.ExitCode -ne 0) {
        $r = Invoke-AdbShell "magisk -v"
    }
    if ($r.StdOut -match "MAGISK") {
        return $r.StdOut.Trim()
    }
    return $null
}

# ===== 字节操作辅助 =====
function Find-BytePattern {
    param([byte[]]$Haystack, [byte[]]$Needle, [int]$Start = 0)
    for ($i = $Start; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $match = $false
                break
            }
        }
        if ($match) { return $i }
    }
    return -1
}

Export-ModuleMember -Function *
