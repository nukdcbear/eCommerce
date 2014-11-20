#![.ps1]powershell.exe -ExecutionPolicy Unrestricted -File
#############################################################################
# Copyright @ 2014 BMC Software, Inc and ReleaseTEAM Inc.                   #
# This script is supplied as a template for performing the defined actions  #
# via the BMC Release Package and Deployment software. This script is       #
# written to perform in most environments but may require changes to work   #
# correctly in your specific environment.                                   #
#############################################################################

# Custom Tiffany action to create Daily Repos directly from NAS OR from a manifest file
# V5.1.2

[CmdletBinding()]
Param (
  [Parameter(Position=0)]
  [string]$RepoType
)

[bool]$supressScreenOutput = $true

function Main 
{

    #Write-Host "Generic Pack"
    ##########################################
    # Declare Variables
    ##########################################

    # API Connection Information
    [string] $remoteHost = "tcowbvlqp01"
    [int] $port = 50000
    [string] $vlusertoken = "54233f32-d984-4b0a-ba3a-0f64ac100a39"
        
    # NAS Path info
    [string] $nasPathQA = $env:ECOM_QA_NAS_PATH
    [string] $nasPathProd = $env:ECOM_PROD_NAS_PATH
        
    # Manifest file, if one exists this overrides looking on NAS
    [string] $manifestFile = $env:ECOM_DAILY_MANIFEST_FILE
        
    # Last Code Drop Loaded
    [string] $lastLoadQA = $env:ECOM_LAST_QA_CODE_DROP
    [string] $lastLoadProd = $env:ECOM_LAST_PROD_CODE_DROP

    # Package names for tco and tco shared
    [string] $tcoPackageName = $env:TCOGLOBALSITE_PACKAGE
    [string] $tcosharedPackageName = $env:TCOSHARED_PACKAGE
    [string] $ecomWebSyncPackage = $env:ECOM_WEB_SYNC_PACKAGE
    [string] $ecomWebSiteBackupPackage = $env:ECOM_WEBSITE_BACKUP_PACKAGE
    [string] $ecomWebContentPushPackage = $env:ECOM_WEBCONTENT_PUSH_PACKAGE
    [string] $ecomWebSyncLBRepo = $env:ECOM_WEB_SYNC_LB_REPO
    [STRING] $ecomProdInitHoldPackage = $env:ECOM_PROD_INITIATE_HOLD_PACKAGE
    [string] $tcoPackageNameQA = $env:TCOGLOBALSITE_PACKAGE_QA
    [string] $tcosharedPackageNameQA = $env:TCOSHARED_PACKAGE_QA
    [string] $ecomWebSyncPackageQA = $env:ECOM_WEB_SYNC_PACKAGE_QA
    [string] $ecomWebSiteBackupPackageQA = $env:ECOM_WEBSITE_BACKUP_PACKAGE_QA
    [string] $ecomWebContentPushPackageQA = $env:ECOM_WEBCONTENT_PUSH_PACKAGE_QA

    # Working directory to build repo from
    [string] $repoWorkingDir = $env:ECOM_REPO_WORKING_DIR
    [string] $archiveDir = $env:ECOM_DROPS_ARCHIVE_DIR
    [string] $ecomDropsDir = $env:ECOM_DROPS_DIR
    [string] $rootDir = $env:VL_CHANNEL_ROOT

    # Package name process is running under
    [string] $masterPackage = $env:VL_PACKAGE
        
	# Property names on Packages
    [string] $bugPropertyName = "NUMBER"
    [string] $envPropertyName = "ENV"

	# Default role for repo
	# $repoRole=$env:REPO_ROLE
    $repoRole=0

	# Instance Arrays
	$tcoInstances=@()
	$tcosharedInstances=@()
	$buildIDs=@()

    $manifestprocessed = $false

    if ($RepoType.ToUpper() -eq "QA") {
        $envTypes = ("QA")
    }
    elseif ($RepoType.ToUpper() -eq "PROD") {
        $envTypes = ("PROD")
    }
    else {
        $envTypes = ("QA","PROD")
    }
    
	## Open the socket, and connect to RPD on the $remoteHost on the specified port 
	write-host "Connecting to $remoteHost on port $port" 

	trap { Write-Host "Could not connect to remote computer: $_"; exit 3} 
	$socket = new-object System.Net.Sockets.TcpClient($remoteHost, $port)

	write-host "Connected. `n" 

	$stream = $socket.GetStream() 
    	
	$writer = new-object System.IO.StreamWriter $stream

	## get any output from the socket
    GetOutput

    ## login and make sure it is successful
    $command = "login "+$vlusertoken
    $writer.WriteLine($command) 
    $writer.Flush() 
    
    ## get any output from the socket
    GetOutput
	
	# check for manifest file
	if (!(Test-Path $repoWorkingDir\$manifestFile)) {
		# If manifest file exists then we process the files in it
		# AND NOT FROM NAS

        Write-Host " "
    	Write-Host "**************************************"
    	Write-Host "**************************************"
    	Write-Host " Manifest file found"
    	Write-host " Reading contents of Manifest file"
    	Write-Host "**************************************"
    	Write-Host "**************************************"
    	Write-Host " "
    	$input = Get-Content $repoWorkingDir\$manifestFile
    
     	$input
 	
 	    Write-Host " "

        ProcessInput $input "NULL" 
        
        $manifestprocessed = $true
        
     	# Archive the manifestfile
     	# Get time stamp
        $timeStamp = Get-Date -f "yyyyMMdd_HHmmss"
        $archiveFile = $envType + "_" + $timeStamp + "_" + $manifestFile 
        Write-Host "Archiving the $rootDir$ecomDropsDir\$manifestFile to $archiveDir\$archiveFile."
        Move-Item $rootDir$ecomDropsDir\$manifestFile $archiveDir\$archiveFile -force

	}
	else {
	    foreach ($type in $envTypes) {
	        if ($type -eq "QA") {
	            $nasPath = $nasPathQA
	        }
	        if ($type -eq "PROD") {
	            $nasPath = $nasPathProd
	        }
	        
    	    # Let's process files from NAS
    	    Write-Host " Processing the $type code drop directory $naspath"
    	    $dirnames = Get-ChildItem $naspath -name | Where-Object {$_ -match "\d\d\d\d\d\d\d\d"}
    	    
    	    # Loop through each dated directory in search of daily-manifest.dat file for processing
    	    # One Repo for each directory will be created.
            foreach ($directory in $dirnames) {
                # Make sure the instance lists are reset for each directory processed
                $tcoInstances=@()
                $tcosharedInstances=@()
	            $buildIDs=@()

                # Check for existence of manifest file in the code drop dir
    	        $foundmanifest = $false
                if (Test-Path("$naspath\$directory\$manifestFile")) {
                    # Directory has a manifest file
                    # Process code drop
                    Write-Host " Manifest file found in $type directory $directory."
                    $input = Get-Content $naspath\$directory\$manifestFile
                    #$input
                    $foundmanifest = $true
                } 
                
                if ($foundmanifest) {
                    Write-Host "Files found to process repo"
                    foreach ($file in $input) {
                        Write-Host "$file"
                    }
            
                    Write-Host " "
                	Write-Host "**************************************"
                	Write-Host "Creating Instances"
                	Write-Host "**************************************"
                	Write-Host " "
                    Write-Host "With $input"
                	# Create Instances for each file listed
                	foreach ($line in $input) {
                	    Write-Host "$line, $filepath"
                		if (!$line.startsWith("#") -and $line.trim() -ne "")  {
                            if ($line.Contains("|")) {
                                # parse the source directory path and filename
                                $filepath,$fullfileName=$line.Split("|",2)
                            }
                            else {
                                $filepath=$naspath + "\" + $directory
                                $fullfileName=$line
                            }
                			Write-Host "Creating instance for file $fullfileName"
                			# parse filename and extension
                			$fileName,$extension=$fullfileName.split(".",2)
                			$deployType,$eType,$buildID=$fileName.split("_",4)
                			
                			# Want to use a full env name for envType for Repo name
                			# But need to keep original env designation from IBM as that is part of file name
                			# which is needed when we actually create an instance.
                			if ($eType.Contains("P")) {
                			    $envType = "PROD"
                			}
                			else {
                			    $envType = "QA"
                			}
                
                            # Retreiving files to work directory
                            if (Test-Path $filepath\$fullfileName) {
                                Write-Host "Found  $filepath\$fullfileName"
                                Copy-Item $filepath\$fullfileName -Destination $repoWorkingDir -PassThru
                            }
                            else {
                                Write-Host "Could not find file: " + $filepath\$fullfileName
                                exit 1
                            }
                
                            # Determine which type of zip content are we dealing with
                		    if (($deployType -eq "tco") -or ($deployType -eq "tcoshared")) {
                			    # Create the Instance
                			    if ($deployType -eq "tco") {
                				    $tcoInstances += $fileName
                			    }
                			    else {
                				    $tcosharedInstances += $fileName
                			    }
                			    $buildIDs += $buildID
                			    Write-Host "CreateInstance with - $deployType $eType $buildID $fileName"
                			    CreateInstance $deployType $eType $buildID $fileName
                			    
                			    # Cleanup on aisle 3, the zip file spill
                			    Remove-Item $repoWorkingDir\$fullfileName -Force
                		    }
                		    else {
                			    Write-Host "Deploy type is not tco or tco shared, exiting."
                			    exit 1
                		    }
                		}
                	}
                	
                    Start-Sleep -m 30000
                	Write-Host " "
                	Write-Host "**************************************"
                	Write-Host " Creating Repo"
                	Write-Host "**************************************"
                	Write-Host " "
                
                	# Create repo with dependencies
                	start-sleep -m 10000
                	CreateRepo $tcoInstances $tcosharedInstances
                
                	Write-Host "**************************************"
                	Write-Host "Repo $repoName Created"
                	Write-Host "**************************************"
                	Write-Host " "
                    
                    Remove-Item $naspath\$directory\$manifestFile -Force
                    
#                    if ($type -eq "QA") {
#                        Write-Host "package property add $masterPackage ECOM_LAST_QA_CODE_DROP $lastdirdatestr"
#                        RunAPICommand "package property add $masterPackage ECOM_LAST_QA_CODE_DROP $lastdirdatestr"
#                    }
#                    elseif ($type -eq "PROD") {
#                        Write-Host "package property add $masterPackage ECOM_LAST_PROD_CODE_DROP $lastdirdatestr"
#                        RunAPICommand "package property add $masterPackage ECOM_LAST_PROD_CODE_DROP $lastdirdatestr"
#                    }
                    $manifestprocessed = $true
                }
            }
        }
    }

    if (!$manifestprocessed) {
        Write-Host " "
        Write-Host "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" 
        Write-Host " No manifest file found in IBM code drop area. " 
        Write-Host "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" 
        Write-Host " " 
        exit 1
    }
	exit 0

}

function ProcessInput {
    Param( [string[]]$input, [string]$filepath="NULL" )
    
    Write-Host " "
	Write-Host "**************************************"
	Write-Host "Creating Instances"
	Write-Host "**************************************"
	Write-Host " "
    Write-Host "With $input"
	# Create Instances for each file listed
	foreach ($line in $input) {
	    Write-Host "$line, $filepath"
		if (!$line.startsWith("#"))  {
            if ($line.Contains("|")) {
                # parse the source directory path and filename
                $filepath,$fullfileName=$line.Split("|",2)
            }
            else {
                $filepath=$naspath + "\" + $directory
                $fullfileName=$line
            }
			Write-Host "Creating instance for file $fullfileName"
			# parse filename and extension
			$fileName,$extension=$fullfileName.split(".",2)
			$deployType,$eType,$buildID=$fileName.split("_",4)
			
			# Want to use a full env name for envType for Repo name
			# But need to keep original env designation from IBM as that is part of file name
			# which is needed when we actually create an instance.
			if ($eType.Contains("P")) {
			    $envType = "PROD"
			}
			else {
			    $envType = "QA"
			}

            # Retreiving files to work directory
            if (Test-Path $filepath\$fullfileName) {
                Write-Host "Found  $filepath\$fullfileName"
                Copy-Item $filepath\$fullfileName -Destination $repoWorkingDir -PassThru
            }
            else {
                Write-Host "Could not find file: " + $filepath\$fullfileName
                exit 1
            }

            # Determine which type of zip content are we dealing with
		    if (($deployType -eq "tco") -or ($deployType -eq "tcoshared")) {
			    # Create the Instance
			    if ($deployType -eq "tco") {
				    $tcoInstances += $fileName
			    }
			    else {
				    $tcosharedInstances += $fileName
			    }
			    $buildIDs += $buildID
			    Write-Host "CreateInstance with - $deployType $eType $buildID $fileName"
			    CreateInstance $deployType $eType $buildID $fileName
			    
			    # Cleanup on aisle 3, the zip file spill
			    Remove-Item $repoWorkingDir\$fullfileName -Force
		    }
		    else {
			    Write-Host "Deploy type is not tco or tco shared, exiting."
			    exit 1
		    }
		}
	}
	
    Start-Sleep -m 30000
	Write-Host " "
	Write-Host "**************************************"
	Write-Host " Creating Repo"
	Write-Host "**************************************"
	Write-Host " "

	# Create repo with dependencies
	start-sleep -m 10000
	CreateRepo $tcoInstances $tcosharedInstances

	Write-Host "**************************************"
	Write-Host "Repo $repoName Created"
	Write-Host "**************************************"
	Write-Host " "
	
}

function CreateRepo($tcoList,$tcosharedList) {
	# Interface with API to create Repo

	# Generate Repo Name, Create repo

	$repoName = "ECom_Daily_" + $envType
	foreach ($bid in $buildIDs) {
		$repoName = $repoName + "_" + $bid
	}

	$repoName = $repoName + "_[" + $(get-date -f "yyyy-MM-dd_HH:mm:ss") + "]"

	Write-Host "Repo Name is $repoName"

	Write-Host "repo add $repoRole $repoName"
	RunAPICommand "repo add $repoRole $repoName"
	
	Write-Host "Adding instances to repo $repoName"

	# Add instances to Repo
	$WebSiteBackupPackage = if ($envType -eq "QA") { $ecomWebSiteBackupPackageQA } else { $ecomWebSiteBackupPackage }
	$PackageName = if ($envType -eq "QA") { $tcoPackageNameQA } else { $tcoPackageName }
	$sharedPackageName = if ($envType -eq "QA") { $tcosharedPackageNameQA } else { $tcosharedPackageName }
	$WebContentPushPackage = if ($envType -eq "QA") { $ecomWebContentPushPackageQA } else { $ecomWebContentPushPackage }
	$WebSyncPackage = if ($envType -eq "QA") { $ecomWebSyncPackageQA } else { $ecomWebSyncPackage }
    $RepoNameFormat= if ($envType -eq "QA") { "eComQARepoDeploy_%Y%m%d.[#]" } else { "eComProdRepoDeploy_%Y%m%d.[#]" }
	
    if ($envType -ne "QA" ) {
    	# Add Prod Init Hold package to Repo
    	Write-Host "Adding instance of $ecomProdInitHoldPackage to $repoName"
    	Write-host "repo artifact add instance $repoName ${ecomProdInitHoldPackage}:Master.1"
    	RunAPICommand "repo artifact add instance $repoName ${ecomProdInitHoldPackage}:Master.1"
    	start-sleep -m 1000
    	$lastPackInst = $ecomProdInitHoldPackage + ":Master.1" 
    }

	# Add WebSite Backup package to Repo
	Write-Host "Adding instance of $WebSiteBackupPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${WebSiteBackupPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${WebSiteBackupPackage}:Master.1"
	start-sleep -m 1000
    if ($envType -ne "QA" ) {
    	write-host "repo artifact depend add $repoName ${WebSiteBackupPackage}:Master.1 $lastPackInst"
    	RunAPICommand "repo artifact depend add $repoName ${WebSiteBackupPackage}:Master.1 $lastPackInst"
    }
	$lastPackInst = $WebSiteBackupPackage + ":Master.1" 
	
	$last = $nul
	$setDepend = $true
	foreach ($inst in $tcoList)  {
		write-host "Adding instance $inst to $repoName"
		write-host "-----------------------------------"

		# add instance to repo
		write-host "repo artifact add instance $repoName ${PackageName}:${inst}"
		RunAPICommand "repo artifact add instance $repoName ${PackageName}:${inst}"
		start-sleep -m 1000
		if ($setDepend) {
			write-host "repo artifact depend add $repoName ${PackageName}:${inst} $lastPackInst"
			#RunAPICommand "repo artifact depend add $repoName ${PackageName}:${inst} ${tcoPackageName}:${last}"
			RunAPICommand "repo artifact depend add $repoName ${PackageName}:${inst} $lastPackInst"
		}
		$last = $inst
		$setDepend = $true
		# Keep the last package instance added to repo
		$lastPackInst = $PackageName + ":" + $last
	}

	$last = $nul
	$setDepend = $true
	foreach ($inst in $tcosharedList)  {
		write-host "Adding instance $inst to $repoName"
		write-host "-----------------------------------"

		# add instance to repo
		write-host "repo artifact add instance $repoName ${sharedPackageName}:${inst}"
		RunAPICommand "repo artifact add instance $repoName ${sharedPackageName}:${inst}"
		start-sleep -m 1000
		if ($setDepend) {
			write-host "repo artifact depend add $repoName ${sharedPackageName}:${inst} $lastPackInst"
			#RunAPICommand "repo artifact depend add $repoName ${sharedPackageName}:${inst} ${tcosharedPackageName}:${last}"
			RunAPICommand "repo artifact depend add $repoName ${sharedPackageName}:${inst} $lastPackInst"
		}
		$last = $inst
		$setDepend = $true
		# Keep the last package instance added to repo
		$lastPackInst = $sharedPackageName + ":" + $last
	}

	# Add Web Content Update package to Repo
	write-host "Adding instance of $WebContentPushPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${WebContentPushPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${WebContentPushPackage}:Master.1"
	start-sleep -m 1000
	write-host "repo artifact depend add $repoName ${WebContentPushPackage}:Master.1 $lastPackInst"
	RunAPICommand "repo artifact depend add $repoName ${WebContentPushPackage}:Master.1 $lastPackInst"
	$lastPackInst = $WebContentPushPackage + ":Master.1"
	
	# Add Web Sync package to the Repo
	write-host "Adding instance of $WebSyncPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${WebSyncPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${WebSyncPackage}:Master.1"
	start-sleep -m 1000
	write-host "repo artifact depend add $repoName ${WebSyncPackage}:Master.1 $lastPackInst"
	RunAPICommand "repo artifact depend add $repoName ${WebSyncPackage}:Master.1 $lastPackInst"

    if ($envType -ne "QA" ) {
        # Only for nonQA repos
    	# Add Web Sync Repo for Prod to the Daily Repo
    	write-host "Adding instance of $ecomWebSyncLBRepo to $repoName"
    	Write-host "repo artifact add instance $repoName ${ecomWebSyncLBRepo}:Master.1"
    	RunAPICommand "repo artifact add instance $repoName ${ecomWebSyncLBRepo}:Master.1"
    	start-sleep -m 1000
    	write-host "repo artifact depend add $repoName ${ecomWebSyncLBRepo}:Master.1 $lastPackInst"
    	RunAPICommand "repo artifact depend add $repoName ${ecomWebSyncLBRepo}:Master.1 $lastPackInst"
    }

    Write-host "repo nameformat $repoName ${RepoNameFormat}"
    RunAPICommand "repo nameformat $repoName ${RepoNameFormat}"
    start-sleep -m 1000

}

function CreateInstance($dtype,$etype,$bid,$instName) {
	# Interface with API to create Instance

	$package=$nul
	
	if ($dtype -eq "tco")  {
	    $package = if ($envType -eq "QA") { $tcoPackageNameQA } else { $tcoPackageName }
		#$package = $tcoPackageName
	}
	elseif ($dtype -eq "tcoshared")  {
	    $package = if ($envType -eq "QA") { $tcosharedPackageNameQA } else { $tcosharedPackageName }
		#$package = $tcosharedPackageName
	}
	
	Write-Host "Instance name is $instName for Package $package"
	
	Write-Host " "
	Write-Host "****************************"
	Write-Host " Checking instance status"
	Write-Host " "
	$package_inst = $package + ":" + $instName
	Write-Host "instance status $package_inst"
	$inststatus = RunApiCommand "instance status $package_inst" $supressScreenOutput
	if ($inststatus.Contains("Ready")) {
	    Write-Host " "
	    Write-Host " Previous load of instance found, renaming and recreating"
	    #Write-Host "instance delete 10086"
	    #RunApiCommand "instance delete 10086" $supressScreenOutput
	    $newname = $instName + "_" + $(get-date -f "yyyyMMdd_HH:mm")
	    Write-Host "instance rename $package_inst $newname"
	    RunApiCommand "instance rename $package_inst $newname" $supressScreenOutput
	}
	else {
	    Write-Host " Previous load of instance does not exist."
	}
	Write-Host "****************************"
	Write-Host " "
	
	# Update properties
	write-host "package property add $package ENV $etype"
	RunAPICommand "package property add $package ENV $etype"
	write-host "package property add $package NUMBER $bid"
	RunAPICommand "package property add $package NUMBER $bid"
	write-host "package property add $package ECOM_REPO_WORKING_DIR $repoWorkingDir"
	RunAPICommand "package property add $package ECOM_REPO_WORKING_DIR $repoWorkingDir"

	# Create Instance
	write-host "instance create package $package $instName"
	RunApiCommand "instance create package $package $instName"

	#Wait for instance to be created
	$ready=$false
	while (!$ready) {
		Start-Sleep -m 1000
		$checkReady = RunApiCommand "instance status ${package}:${instName}"
		if ($checkReady.Contains("Ready"))  {
			$ready = $true
		}
		if ($checkReady.Contains("Error"))  {
			Write-Host "Error creating instance ${package}:${instName}"
			exit 1
		}
		if ($checkReady.Contains("Object not found"))  {
			Write-Host "Object not found creating instance ${package}:${instName}"
			exit 1
		}
	}
	Write-host "Instance ${package}:${instName} created successfully"	


	# return instanceName
	return $instName
}

function RunAPICommand($apiCommand, $surpressOutput)  {
	## write the command
	$writer.WriteLine($apiCommand) 
	$writer.Flush() 
                
	## wait some time 
	start-sleep -m 100
                
	## get any output from the socket
	#$SCRIPT:output += GetOutput
	GetOutput $surpressOutput
}


## Read output from a remote host 
function GetOutput($donotPrint) 
{ 
    ## Create a buffer to receive the response 
    $buffer = new-object System.Byte[] 1024 
    $encoding = new-object System.Text.AsciiEncoding

    $outputBuffer = "" 
    $foundMore = $false

    ## Read all the data available from the stream, writing it to the 
    ## output buffer when done. 
    do 
    { 
        ## Allow data to buffer for a bit 
        start-sleep -m 100

        ## Read what data is available 
        $foundmore = $false 
        $stream.ReadTimeout = 2000

        do 
        { 
            try 
            { 
                $read = $stream.Read($buffer, 0, 1024)
                start-sleep -m 1000
                if($read -gt 0) 
                { 
                    $foundmore = $true 
                    $outputBuffer += ($encoding.GetString($buffer, 0, $read)) 
                } 
            } catch { $foundMore = $false; $read = 0 } 
        } while($read -gt 0) 
    } while($foundmore)

    if (!$donotPrint) {
        if($outputBuffer)  
        {  
            foreach($line in $outputBuffer.Split("`n")) 
                { 
                    write-host $line 
                } 
        } 
    }   

    $outputBuffer
}

. Main