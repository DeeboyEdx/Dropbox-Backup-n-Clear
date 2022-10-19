# This collection of scripts makes a key presumption that...
# The media files being worked on are of 'YYYY-MM-DD HH.MM.SS.xyz' format
# This is the format Dropbox puts onto computers.
# 

[CmdletBinding()]
param (
    # this whole SourcePath parameter might be unnecessary if I'm just continuing with the batch file's assumption
    # that the files i'll be collating are in the same folder as the batch file
    [Parameter(Mandatory=$true)]
    [string] $SourcePath = "$HOME\Dropbox\Camera Uploads",
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [Alias ('DestinationPath')]
    [string[]] $BackupPath,
    [Alias ('Threshold')]
    [Alias ('WaitUntil')]
    [int64]    $StartThreshold = 0,
    [string]   $FinalPath,
    [Alias ('NoClose')]
    [switch]   $DoNotCloseUponCompletion,
    [switch]   $PerpetualRepeat
)

Begin {
    ############################################
    ### Initializing variables and functions ###
    ############################################
    $MEDIA_FILE_TYPES = @('.jpg', '.gif', '.png', '.mp4', '.jpeg')

    function Maybe-Exit ([switch] $Loop, [switch] $ConfirmRepeatIntent) {
        if ($Loop) {
            # call self recursively
            Write-Verbose 'Recursive call'
            if ($ConfirmRepeatIntent -and (Read-Host "Restart script?") -like 'n*') {
                # This is intended to end the entire execution / process
                exit
            }
            Write-Host "`nRestarting sync script" -BackgroundColor DarkGray -ForegroundColor White
            Start-Sleep 5
            Backup-and-Remove-Media-Files.ps1 -SourcePath $SourcePath -BackupPath $BackupPath -StartThreshold $StartThreshold -DoNotCloseUponCompletion:$DoNotCloseUponCompletion -PerpetualRepeat:$PerpetualRepeat
        }
        while ($DoNotCloseUponCompletion) {
            Read-Host | Out-Null
        }
        exit
    }

    function Get-Media-Files($path) {
        return Get-ChildItem -Path $path -File | Where-Object Extension -in $MEDIA_FILE_TYPES
    }

    function Test-Media-Files-Presence($path) {
        return [bool] (Get-Media-Files -path $path)
    }

    function Get-Collated-Media-Folders($path) {
        return Get-ChildItem -Directory -Path $path | Where-Object {$_.name -Match '^\d\d\d\d\-\d\d\-\d\d$'}
    }

    function Get-Collated-Year-Folders($path) {
        return Get-ChildItem -Directory -Path $path | Where-Object {$_.name -Match '^\d\d\d\d$'}
    }

    function Test-Collated-Media-Folders-Presence($path) {
        return [bool] (Get-Collated-Media-Folders -path $path) -or (Get-Collated-Year-Folders -path $path)
    }

    function Format-Collate-Media-Files-Successfully($path) {
        # verify collate batch file is present
        $batch_file_full_path = "$PSScriptRoot\collate v3.bat"
        if (-not (Test-Path $batch_file_full_path)){
            Write-Host "Collate batch file missing" -ForegroundColor Red
            return $false
        }

        # get batch's full path. Unnecessary as I'm now requiring it be in same path as this script.
        # $batch_file_full_path = Get-ChildItem -Path $batch_file_path | Select-Object -ExpandProperty FullName
        
        <# Turns out the batch works in the WORKING DIR, not the batch file's script root dir so all this copy business is unnecessary
        # copy collate batch to source path
        Copy-Item -Path $batch_file_path -Destination $path -ErrorAction SilentlyContinue

        # verify batch file was copied successfully
        # and keep track of file's location with $tempBatchPath 
        if (-not ([bool](Join-Path -Path $path -ChildPath $batch_file_path -Resolve -ErrorAction SilentlyContinue | Tee-Object -Variable tempBatchPath))){
            Write-Host "Collate batch file failed to copy to source path" -ForegroundColor Red
            return $false
        }
        #>

        # change working dir to source path
        # because batch file executes in working DIR, not batch's didr
        Push-Location $path

        # execute batch file
        $process = Start-Process $batch_file_full_path -Wait -PassThru

        # Buffering move to media folders from move to year folders
        Start-Sleep -Seconds 5

        try {
            # Create year folders
            Get-Collated-Media-Folders -path $path |
                Tee-Object -Variable media_folders |
                Sort-Object Name | 
                ForEach-Object {
                    $year = $_.Name.split('-')[0]
                    $year_path = Join-Path -Path $path -ChildPath $year
                    if (-not (Test-Path $year_path)) {
                        Write-Verbose "Making folder: $year_path"
                        mkdir $year_path -ErrorAction SilentlyContinue | Out-Null
                    }
                }

            # Move collated directories into year folders
            Get-Collated-Year-Folders -path $path |
                Sort-Object Name |
                ForEach-Object {
                    $year = $_.Name
                    $year_path = $_.FullName
                    
                    while ($pending_folders = Get-Collated-Media-Folders -path $path | Where-Object {$_.Name -like "$year*"}) {
                        # Buffering action
                        Start-Sleep -Seconds 5
                        Write-Verbose "Moving $($pending_folders.Count) $year* folder(s) to $year_path" -Verbose
                        $pending_folders | Move-Item -Destination $year_path -ErrorAction SilentlyContinue
                    }
                }
        }
        catch {
            Write-Host "Collating into year folders failed." -ForegroundColor Red
            return $false
        }

        # check batch ran successfully
        if ($process.ExitCode -ne 0) {
            Write-Host "Media files collating failed" -ForegroundColor Red
            return $false 
        }

        <# Don't need now that I've discovered batch file works in working dir.
        # remove copy from source path
        Remove-Item $tempBatchPath
        #>

        # Just in case, removing tmp file which sometimes gets missed.
        if (Test-Path tmp.txt -ErrorAction SilentlyContinue) {
            Remove-Item -Path tmp.txt -ErrorAction SilentlyContinue
        }

        # return to previous working dir
        Pop-Location

        Write-Host "Media files collated successfully" -ForegroundColor Green
        return $true
    }

    # ensure Free-File-Sync function exists
    if (-not (Test-Path Function:\Free-File-Sync -ErrorAction SilentlyContinue)) {
        # attempt to load function
        $ffs_name = "FreeFileSync-PS-Function.ps1"
        $ffs_script_path = Join-Path $PSScriptRoot $ffs_name
        try {
            . $ffs_script_path
        }
        catch {
            Write-Host "Free-File-Sync function missing!" -ForegroundColor Red
            Write-Host "Please ensure '$ffs_name' is in this script's same location..." 
            Write-Host "   $PSScriptRoot\" -ForegroundColor DarkGray
            Maybe-Exit
        }
    }

    function Sync-Files-Successfully ($source, $destination) {
        # checking pre-requisites
        if (-not $source -or -not $destination) {
            Write-Host "Please provide both a source and destination paths" -ForegroundColor Red
            return $false
        }
        if (-not (Test-Path $source)) {
            Write-Host "Source path is not reachable" -ForegroundColor Red
            return $false
        }
        if (-not (Test-Path $destination)) {
            Write-Host "Destination path '$destination' is not reachable" -ForegroundColor Red
            return $false
        }

        # performing the sync
        try {
            if (-not (Free-File-Sync -Source $source -Destination $destination -SyncType Update -ReturnBoolean)) {
                Write-Host "Syncing to '$destination' completed with error(s)!" -ForegroundColor Yellow
                return $false
            }
        }
        catch {
            Write-Host "Sync function failure!" -ForegroundColor Red
            return $false
        }

        # validating $destination contains all folders from $source
        $dest_med_folders = Get-Collated-Media-Folders -path $destination
        $unsynced_folders = Get-Collated-Media-Folders -path $source | Where-Object {$_.Name -notin $dest_med_folders.Name}
        if ($unsynced_folders) {
            Write-Host "Sync verification failed!" -ForegroundColor Yellow
            Write-Host "These folders were not found in destination '$destination'"
            foreach ($folder_name in $unsynced_folders.Name | Sort-Object) {
                Write-Host $folder_name
            }
            return $false
        }
        Write-Verbose "Verified all media folders from source are in destination"
        return $true
    }

    function Remove-Collated-Media-Folders($path) {
        try {
            Get-Collated-Media-Folders -path $path | Remove-Item -Recurse -Force -ErrorAction Stop
            Write-Host "Successfully removed collated media folder(s) from source" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to delete collated media folder(s)"
        }
    }

    function Remove-Collated-Year-Folders($path, $attempts = 3) {
        try {
            while ($pending_year_folders = Get-Collated-Year-Folders -path $path) {
                $pending_year_folders | Remove-Item -Recurse -Force -ErrorAction Stop
                Write-Host "Successfully removed collated year folder(s) from source" -ForegroundColor Green
            }
        }
        catch {
            if ($attempts -gt 0) {
                Write-Verbose "Re-attempting to remove $($pending_year_folders.Count) Year folder(s)" -Verbose
                Start-Sleep -Seconds 2
                Remove-Collated-Year-Folders -path $path -attempts ($attempts - 1)
            }
            else {
                Write-Host "Failed to delete collated year folder(s)" -ForegroundColor Red
                Write-Host "ERROR: $_"
            }
        }
    }

    function Wait-Until-Bytes ($path, $threshold) {
        Begin {
            if (-not $threshold) {
                return
            }
            function Format-Bytes {
                Param
                (
                    [Parameter(
                        ValueFromPipeline = $true
                    )]
                    [ValidateNotNullOrEmpty()]
                    [float]$number
                )
                Begin{
                    # Credit: https://theposhwolf.com/howtos/Format-Bytes/
                    # although I had to use Invoke-Expression cuz casting to [int64] was broken
                    $sizes = 'KB','MB','GB','TB','PB'
                }
                Process {
                    # New for loop
                    for($x = 0;$x -lt $sizes.count; $x++){
                        if ($number -lt (Invoke-Expression "1$($sizes[$x])")){
                            if ($x -eq 0){
                                return "$number B"
                            } else {
                                $num = $number / (Invoke-Expression "1$($sizes[$x-1])")
                                $num = "{0:N2}" -f $num
                                return "$num $($sizes[$x-1])"
                            }
                        }
                    }
                }
                End{}
            }
            $sum = 0
            $s_len = 3 # length of "0 B"
            $limit = Format-Bytes -number $threshold
            Write-Host "Waiting until source path reaches the threshold." -ForegroundColor Gray
            write-host "  $path" -ForegroundColor DarkGray
        }
        Process {
            if (-not $threshold) {
                return
            }
            while( $sum -lt $threshold) {
                $sum = Get-ChildItem -Path $path -Recurse | 
                    Measure-Object Length -Sum | 
                    Select-Object -ExpandProperty Sum
                $sentence = "$(Format-Bytes -number $sum) of $limit     "
                Write-Host ("`b"*$s_len) $sentence -NoNewline
                $s_len = $sentence.Length + 1
                Start-Sleep 5
            }
            Write-Host "  Reached.  Continuing..." -ForegroundColor DarkGreen
        }
        End {
        }
    }


    ########################
    ### Wait for trigger ###
    ########################

    # TODO : Make sure this is working right
    Wait-Until-Bytes -path $SourcePath -threshold $StartThreshold

    
    ###################################
    ### Preparing file by collating ###
    ###################################

    # check for presence of un-foldered / un-collated media files
    if ( (Test-Media-Files-Presence -path $SourcePath) -or (Get-Collated-Media-Folders -path $SourcePath) ) {
        # run the collate batch file
        if (-not (Format-Collate-Media-Files-Successfully -path $SourcePath)) {
            Write-Host "Exiting" -ForegroundColor Red
            Maybe-Exit -Loop:$PerpetualRepeat
        }
    }

    # check for presence of media folders
    if (-not (Test-Collated-Media-Folders-Presence -path $SourcePath)) {
        Write-Host "No media folders found in source path.  Nothing to do here.  Bye" -ForegroundColor Gray
        Maybe-Exit -Loop:$PerpetualRepeat
    }

    if ($PerpetualRepeat -and $FinalPath) {
        Write-Warning "Note that FinalPath will not be synced to when -PerpetualRepeat argument is used."
    }

    Write-Host
}

# PROCESS :
# memo: There are 2 ways this runs through an array of destinations.
#       1) foreach @(array)
#       2) piping an array will run the PROCESS block for each element (not BEGIN or END blocks), instead of giving it the array
Process {
    foreach ($SyncDestPath in $BackupPath) {
        # if there's any confusion in relative paths or whatnot, un-comment this line to resolve a full path for each destination
        # $SyncDestPath = Resolve-Path $SyncDestPath | Select-Object -ExpandProperty Path

        # run sync to backup destination
        if (-not (Sync-Files-Successfully -source $SourcePath -destination $SyncDestPath)) {
            Write-Host 'Sync to backup destination did not complete successfully' -ForegroundColor Red
            #Read-Host | Out-Null # not waiting for user to hit Enter anymore
            Write-Host "Opening FreeFileSync for manual resolution" -ForegroundColor DarkGray
            # consider figuring out how to (if possible) have it open with src & dest pre-filled in
            Free-File-Sync -Source $SourcePath -Destination $BackupPath -SyncType Update -JustOpenApp
            Write-Verbose "`$PerpetualRepeat: $PerpetualRepeat"
            Maybe-Exit -ConfirmRepeatIntent -Loop:$PerpetualRepeat
            # this needs to be 'exit' instead of 'return' so the entire script stops and the END block doesn't run
        }
    }
}

# FINAL :
# run final sync (consisdering removing this since $BackupPath now accepts multiple paths)
# remove collated media folders from source path
End {
    # run sync to final destination
    if ($FinalPath -and -not (Sync-Files-Successfully -source $SourcePath -destination $FinalPath)) {
        Write-Host 'Sync to final destination did not complete successfully' -ForegroundColor Red
        Read-Host | Out-Null
        Write-Host "Opening FreeFileSync for manual resolution" -ForegroundColor DarkGray
        Free-File-Sync -Source $SourcePath -Destination $FinalPath -SyncType Update -JustOpenApp
        Maybe-Exit -ConfirmRepeatIntent -Loop:$PerpetualRepeat
    }

    # delete all the folders formatted like so.  YYYY
    Remove-Collated-Year-Folders -path $SourcePath

    Write-Host
    Write-Host "Completed backups and cleared out source path '$SourcePath'" -ForegroundColor Black -BackgroundColor Green

    Maybe-Exit -Loop:$PerpetualRepeat
}

# tell Eg when this is done
# he may find this useful for managing his Mom's Dropbox pics
