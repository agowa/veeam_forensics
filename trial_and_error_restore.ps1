param(
  [parameter(Mandatory,HelpMessage="Affected ObjectId from Get-VBRRestorePoint")]
  $restorePointObjectId,
  
  [parameter(Mandatory,HelpMessage="Use this path to copy files from (Symlinked to current mount dir)")]
  $persistentMountPath = "C:\VeeamFLR\restore",
  
  [parameter(Mandatory,HelpMessage="Volume and path to any folder within the restorepoint to test if the backup is still mounted")]
  $testFolderPath = "Volume1\Windows"
)

# Note: While this script is running, use a tool like total commander. The sync tool in total commander will allow to continue a job upon an error occured.
# Just wait until the image is remounted until you continue.
# From what I've seen when restoring a file results in a driver hickup once, it will always cause one. Therefore you may want to use a tool that just attempts one single read of each file.
# I used Total Commander over a SSH connection from another computer to perform this copy operation, that's why it's not done within this script.

if ([bool](Get-PSSnapin -Registered -Name "VeeamPSSnapIn" -ErrorAction SilentlyContinue)) {
  Add-PSSnapin -Name "VeeamPSSnapIn"
} else {
  Set-Alias -Name "installutil" -Value (Join-Path -Path (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").InstallPath -ChildPath "InstallUtil.exe")
  installutil "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell.dll"
  Add-PSSnapin -Name "VeeamPSSnapIn"
}

$Global:restoreActive = $true # placeholder used to exit remount cycle.

# Select RestorePoint
$restorePoint = Get-VBRRestorePoint -ObjectId $restorePointObjectId
$testPath = "$persistentMountPath\$testFolderPath"

do {
  # try-finally is needed to unmount when the outer loop is interrupted.
  try {
    # Mount RestorePoint and start FLR Restore session
    Write-Host -ForegroundColor Green -BackgroundColor Black -Object "$(get-date -Format u): Mounting Image"
    $flerestore = Start-VBRWindowsFileRestore -RestorePoint $restorePoint
    Write-Host -ForegroundColor White -BackgroundColor Black -Object "$(get-date -Format u): Mounted Image"
    $null = New-Item -ItemType Junction -Path $persistentMountPath -Target "C:\VeeamFLR\$($flerestore.MountPoint)\"

    # Wait for driver to hick up
    do {
      Start-Sleep -Seconds 2
      Write-Host -ForegroundColor White -BackgroundColor Black -Object "$(get-date -Format u): Performing health check"
    } while(Test-Path -Path $testPath)
    Write-Host -ForegroundColor Red -BackgroundColor Black -Object "$(get-date -Format u): Encountered driver hick up"
  } finally {
    # Unmount Image
    Write-Host -ForegroundColor White -BackgroundColor Black -Object "$(get-date -Format u): Unmount Image"
    # ToDo: Sometimes the unmount gets stuck indefinitely after a driver hick up, in that case only terminating this script and restarting will help
    # The task within veeam will still be shown as running. The only way for it to "complete" is to restart the computer.
    # However for the restore to continue we can just start another job.
    # Therefore one may want to warp the following function call into a job and abondone it after a timeout of about 10 minutes.
    Stop-VBRWindowsFileRestore -FileRestore $flerestore
    Remove-Item -Force $persistentMountPath
  }
} while($restoreActive)
