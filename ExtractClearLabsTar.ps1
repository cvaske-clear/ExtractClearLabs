param(
    [Parameter(Mandatory=$false)][string]$tarball
)

Add-Type -AssemblyName System.Windows.Forms

# $tarball = "C:\Users\charles_vaske\Downloads\BHJL13.2023-08-28.01.all_and_intermediates.tar"

if (!($tarball)) {
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
    }
    $null = $FileBrowser.ShowDialog()

    $tarball = $FileBrowser.FileName
}

Write-Debug "Extracting: $($tarball)"

$outdir = Split-Path -parent $tarball

Set-Location $outdir

# $LabName = Read-Host -Prompt 'Input your lab name'

tar xf $tarball
if ($LASTEXITCODE) {
    Write-Host "The selected file could not be extracted: $($tarball)"
    exit
}

if (!(Test-Path -Path "fastqs")) {
    Write-Host "This file does not appear to be a Clear Labs archive, as it does not contain a subdirectory 'fastqs'"
    exit
}

$fns = Get-ChildItem -Path "fastqs" -Name "*.fastq.gz" -File

# Starting name looks like:  11SalA01-BHKL22.2023-08-08.02-A01_S1_R1_001-FS10002469-060623.fastq.gz
# Goal file name looks like: 11SalA01-LabID-FS10002469230808BHKL2202-A01_S1_L001_R1_001.fastq.gz
#
# Method: 
#   Step 1: split on _, resulting in 4+ parts. The last three parts are system generated:
#               * _SXXX_ sample number in demultiplexing
#               * _RX_ read number
#               * _001-FSXXXXX.fastq.gz part, flowecell ID, extension
#           user input before that could include an underscore. Split out and storethe flowcell ID, 
#           then replace the last parte with 001.fastq.gz as a standard ending.
#   Step 2: Rejoin eveyrthing except the last 3 parts, and split based on -. The last four parts are
#               * Instrument
#               * year
#               * Month
#               * Day 
#               * run number
#               * Well ID
#           The parts before that are the sample name, and could have underscores or other 
#           nonalphanumeric characters. We need to convert these earlier parts into a sample
#           name with only alphanumeric plus dashes.
#   Step 3: Construct the RunId section
#   Step 4: paste parts into SampleName-Runid-WellId_SXXX_L001_RX_001.fastq.gz
# For this to work, there the part number assumptions must all be correct. If any assumptions fail,
# return the original file name.
function Rename-Soter-Fastq {
    param ($origname)

    ## Step 1: construct ending, save and remove Flowcell ID
    $fnparts = [regex]::split($origname, "_")
    if ($fnparts.length -lt 4) {
        Write-Debug "Not enough underscores to match pattern: $($origname)"
        return $origname
    }
    if ($fnparts[-1] -match '^001-([A-Z0-9-]+)\.fastq\.gz$') {
        $flowcellid = $Matches.1
    } else {
        Write-Debug "Flowcell/FASTQ suffix does not match: $($origname)"
        return $origname
    }
    
    $new_ending = "$($fnparts[-3])_L001_$($fnparts[-2]).fastq.gz"

    ## Step 2: 
    $sample_runid = $fnparts[0..($fnparts.length - 4)] -join "_"
    $sample_runid_parts = $sample_runid -split "[.-]"
    if ($sample_runid_parts.length -lt 7) {
        Write-Debug "Sample/RunID section of file name does not have enough parts: $($sample_runid_parts.length)"
        Write-Debug "    parts: $($sample_runid_parts)"
        Write-Debug "    original filename: $($origname)"
        return $origname
    }
    $well = $sample_runid_parts[-1]
    $runnum = $sample_runid_parts[-2]
    $day = $sample_runid_parts[-3]
    $month = $sample_runid_parts[-4]
    $year = $sample_runid_parts[-5]
    $instrument = $sample_runid_parts[-6]

    $newrunid = "$($flowcellid)$($year)$($month)$($day)$($instrument)$($runnum)-$($well)"
    $newsample = $sample_runid_parts[0..($sample_runid_parts.length - 7)] -join "-" -replace "[^a-zA-Z0-9]", "-"

    $newname = "$($newsample)-$($newrunid)_$($new_ending)"

    return $newname
}

$renames = 0
foreach ($fn in $fns) {
    $newfn = Rename-Soter-Fastq($fn)
    Write-Debug "1st Name: $($fn)"
    Write-Debug "New Name: $($newfn)"
    if ($fn -ne $newfn) {
        Rename-Item "fastqs/$($fn)" $newfn
        $renames = $renames + 1
    }
}

Write-Host "Extraction complete. ${renames} file(s) renamed in subdirectory 'fastqs'"

Invoke-Item "fastqs"