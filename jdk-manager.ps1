# Check if Chocolatey is installed, if not install it
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

$jdks = @{
    "17" = "corretto17jdk"
    "21" = "corretto21jdk"
}

function Is-JDKInstalled($pkgName) {
    return (choco list | Select-String $pkgName) -ne $null
}

function Install-JDK($pkgName) {
    if (-not (Is-JDKInstalled $pkgName)) {
        Write-Host "Installing $pkgName ..."
        choco install $pkgName -y
    } else {
        Write-Host "$pkgName is already installed."
    }
}

function Any-JDKInstalled() {
    foreach ($pkg in $jdks.Values) {
        if (Is-JDKInstalled $pkg) {
            return $true
        }
    }
    return $false
}

function Check-Updates() {
    Write-Host "`nChecking for updates on installed JDKs..."

    if (-not (Any-JDKInstalled)) {
        Write-Host "No JDKs are currently installed. Please install a JDK first." -ForegroundColor Yellow
        return
    }

    $updatesAvailable = $false
    $anyChecked = $false

    foreach ($pkg in $jdks.Values) {
        if (Is-JDKInstalled $pkg) {
            $anyChecked = $true
            Write-Host "Checking $pkg..." -NoNewline
            $outdatedOutput = choco outdated --id=$pkg | Out-String

            # Parse the output to check if updates are available
            if ($outdatedOutput -match "$pkg\s+\|") {
                # Extract version information using more robust regex patterns
                $versionPattern = [regex]"$pkg\s+\|\s+(\S+)\s+\|\s+(\S+)"
                $match = $versionPattern.Match($outdatedOutput)

                if ($match.Success) {
                    $updatesAvailable = $true
                    $currentVersion = $match.Groups[1].Value
                    $availableVersion = $match.Groups[2].Value

                    Write-Host " Update available!" -ForegroundColor Yellow
                    Write-Host "   Current version: $currentVersion"
                    Write-Host "   Available version: $availableVersion"
                } else {
                    # Fallback if regex doesn't match but package is in outdated list
                    Write-Host " Update available!" -ForegroundColor Yellow
                    Write-Host "   Run 'choco outdated --id=$pkg' for details"
                }
            } else {
                Write-Host " Up to date" -ForegroundColor Green
            }
        } else {
            Write-Host "Skipping $pkg (not installed)" -ForegroundColor Gray
        }
    }

    if ($anyChecked) {
        if (-not $updatesAvailable) {
            Write-Host "`nAll installed JDKs are up to date." -ForegroundColor Green
        } else {
            Write-Host "`nUpdates are available. Use option 2 from the menu to update." -ForegroundColor Yellow
        }
    }
}

function Update-JDK($pkgName) {
    if (Is-JDKInstalled $pkgName) {
        Write-Host "Updating $pkgName ..." -ForegroundColor Cyan

        # Get current version before update
        $outdatedOutput = choco outdated --id=$pkgName | Out-String
        $versionPattern = [regex]"$pkgName\s+\|\s+(\S+)\s+\|\s+(\S+)"
        $match = $versionPattern.Match($outdatedOutput)
        $currentVersion = if ($match.Success) { $match.Groups[1].Value } else { "unknown" }

        # Perform the update
        $result = choco upgrade $pkgName -y

        # Check if update was successful
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully updated $pkgName" -ForegroundColor Green

            # Try to get the new version
            $installedOutput = choco list --local-only --id=$pkgName | Out-String
            $newVersionPattern = [regex]"$pkgName\s+(\S+)"
            $newMatch = $newVersionPattern.Match($installedOutput)
            $newVersion = if ($newMatch.Success) { $newMatch.Groups[1].Value } else { "unknown" }

            if ($currentVersion -ne "unknown" -and $newVersion -ne "unknown") {
                Write-Host "Updated from version $currentVersion to $newVersion" -ForegroundColor Green
            }
        } else {
            Write-Host "Failed to update $pkgName. Please check the output above for errors." -ForegroundColor Red
        }
    } else {
        Write-Host "$pkgName is not installed." -ForegroundColor Yellow
        Write-Host "Use option 3 to install it first." -ForegroundColor Yellow
    }
}

function Get-JDKFolder($version) {
    $basePath = "C:\Program Files\Amazon Corretto"
    $temurinPath = "C:\Program Files\Eclipse Adoptium"
    if ($version -eq "17") {
        if (Test-Path $basePath) {
            $folders = Get-ChildItem -Path $basePath -Directory |
                Where-Object { $_.Name -match "^jdk$version" } |
                Sort-Object Name -Descending
            if ($folders.Count -gt 0) {
                return $folders[0].FullName
            }
        }
    } elseif ($version -eq "21") {
        if (Test-Path $temurinPath) {
            $folders = Get-ChildItem -Path $temurinPath -Directory |
                Where-Object { $_.Name -match "^jdk-$version" } |
                Sort-Object Name -Descending
            if ($folders.Count -gt 0) {
                return $folders[0].FullName
            }
        }
    }
    return $null
}

function Switch-JDK($version) {
    $javaHome = Get-JDKFolder $version
    if (-not $javaHome) {
        Write-Error "JAVA_HOME for version $version not found. Please install it first."
        return
    }
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, [EnvironmentVariableTarget]::Machine)

    $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $pathParts = $path -split ';' | Where-Object { $_ -notmatch "Amazon Corretto" -and $_ -notmatch "Eclipse Adoptium" }
    $newPathParts = @("$javaHome\bin") + $pathParts
    $newPath = ($newPathParts -join ';')
    [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::Machine)

    Write-Host "Switched JAVA_HOME to $javaHome"
    Write-Host "Please open a new terminal window for the changes to take effect."
}

function Show-Menu {
    Clear-Host
    Write-Host "=== JDK Management with Chocolatey ===" -ForegroundColor Cyan
    Write-Host "Installed versions:"
    foreach ($ver in $jdks.Keys) {
        $pkg = $jdks[$ver]
        if (Is-JDKInstalled $pkg) {
            Write-Host " - Java $ver ($pkg)" -ForegroundColor Green
        } else {
            Write-Host " - Java $ver (not installed)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "Select an option:"
    Write-Host "1. Check for JDK updates"
    Write-Host "2. Update JDK"
    Write-Host "3. Install JDK"
    Write-Host "4. Switch JAVA_HOME version"
    Write-Host "0. Exit"
}

# --- START ---

# Install JDKs if not installed
do {
    Show-Menu
    $choice = Read-Host "Enter your choice"
    switch ($choice) {
        "1" {
            Check-Updates
            Read-Host "Press Enter to continue..."
        }
        "2" {
            Write-Host "Select the version to update:"
            foreach ($ver in $jdks.Keys) {
                Write-Host "$ver. Java $ver"
            }
            $verChoice = Read-Host "Version"
            if ($jdks.ContainsKey($verChoice)) {
                Update-JDK $jdks[$verChoice]
            } else {
                Write-Host "Invalid version." -ForegroundColor Red
            }
            Read-Host "Press Enter to continue..."
        }
        "3" {
            Write-Host "Select the version to install:"
            foreach ($ver in $jdks.Keys) {
                $pkg = $jdks[$ver]
                if (-not (Is-JDKInstalled $pkg)) {
                    Write-Host "$ver. Java $ver"
                }
            }
            $verChoice = Read-Host "Version"
            if ($jdks.ContainsKey($verChoice)) {
                $pkg = $jdks[$verChoice]
                if (-not (Is-JDKInstalled $pkg)) {
                    Install-JDK $pkg
                } else {
                    Write-Host "Java $verChoice is already installed." -ForegroundColor Yellow
                }
            } else {
                Write-Host "Invalid version." -ForegroundColor Red
            }
            Read-Host "Press Enter to continue..."
        }
        "4" {
            Write-Host "Select the version to switch JAVA_HOME:"
            foreach ($ver in $jdks.Keys) {
                $pkg = $jdks[$ver]
                if (Is-JDKInstalled $pkg) {
                    Write-Host "$ver. Java $ver"
                }
            }
            $verChoice = Read-Host "Version"
            if ($jdks.ContainsKey($verChoice)) {
                if (Is-JDKInstalled $jdks[$verChoice]) {
                    Switch-JDK $verChoice
                } else {
                    Write-Host "Java $verChoice is not installed. Please install it first." -ForegroundColor Yellow
                }
            } else {
                Write-Host "Invalid version." -ForegroundColor Red
            }
            Read-Host "Press Enter to continue..."
        }
        "0" {
            Write-Host "Exiting program." -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
            Read-Host "Press Enter to continue..."
        }
    }
} while ($true)
