#############################################################################
# Copyright @ 2014 BMC Software, Inc and ReleaseTEAM Inc.                   #
# This script is supplied as a template for performing the defined actions  #
# via the BMC Release Package and Deployment software. This script is       #
# written to perform in most environments but may require changes to work   #
# correctly in your specific environment.                                   #
#############################################################################

# Custom Tiffany action to create Daily Repos from a manifest file
# V3.0.8

function Main 
{

	#Write-Host "Generic Pack"
	##########################################
	# Declare Variables
	##########################################

	# Manifest file name
	$manifestFile = $env:VL_CONTENT_PATH

	# API Connection Information
    [string] $remoteHost = "localhost"
    [int] $port = 50000
    [string] $vlusertoken = "53f21ba1-6978-4159-a720-0690ac147e8b"
        
	# Package names for tco and tco shared
    [string] $tcoPackageName = $env:TCO_PACKAGE_NAME
    [string] $tcosharedPackageName = $env:TCOSHARED_PACKAGE_NAME
    [string] $tcoWebSyncPackage = $env:TCO_WEB_SYNC_PACKAGE
    [string] $tcoWebSiteBackupPackage = $env:TCO_WEBSITE_BACKUP_PACKAGE
    [string] $tcoWebContentPushPackage = $env:TCO_WEBCONTENT_PUSH_PACKAGE
    [string] $tcoWebConfigPushPackage = $env:TCO_WEBCONFIG_PUSH_PACKAGE

    # Working directory to build repo from
    [string] $repoWorkingDir = $env:ECOM_REPO_WORKING_DIR
    [string] $archiveDir = $env:ECOM_DROPS_ARCHIVE_DIR
    [string] $ecomDropsDir = $env:ECOM_DROPS_DIR
    [string] $rootDir = $env:$VL_CHANNEL_ROOT

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


	## Open the socket, and connect to RPD on the $remoteHost on the specified port 
	write-host "Connecting to $remoteHost on port $port" 

	trap { Write-Error "Could not connect to remote computer: $_"; exit 3} 
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
		Write-Error "No manifest file available."
		exit 1
	}

	Write-Host "**************************************"
	Write-Host "Reading contents of Manifest file"
	Write-Host "**************************************"
	$input = Get-Content $repoWorkingDir\$manifestFile

 	$input
 	
	Write-Host " "
	Write-Host "**************************************"
	Write-Host "Creating Instances"
	Write-Host "**************************************"

	# Create Instances for each file listed
	foreach ($line in $input) {
		if (!$line.startsWith("#"))  {
            if ($line.Contains("|")) {
                # parse the source directory path and filename
                $filepath,$fullfileName=$line.Split("|",2)
            }
            else {
                $filepath="."
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
                Copy-Item $filepath\$fullfileName -Destination $repoWorkingDir
            }
            else {
                Write-Error "Could not find file: " + $filepath\$fullfileName
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
			    CreateInstance $deployType $eType $buildID $fileName
		    }
		    else {
			    write-error "Deploy type is not tco or tco shared, exiting."
			    exit 1
		    }
		}
	}

 	# Archive the manifestfile
 	# Get time stamp
    $timeStamp = Get-Date -f "yyyyMMdd_HHmmss"
    $archiveFile = $envType + "_" + $timeStamp + "_" + $manifestFile 
    Write-Host "Archiving the $rootDir$ecomDropsDir\$manifestFile to $archiveDir\$archiveFile."
    Move-Item $rootDir$repoWorkingDir\$manifestFile $archiveDir\$archiveFile -force

    Start-Sleep -m 30000
	Write-Host " "
	Write-Host "**************************************"
	Write-Host "Creating Repo"
	Write-Host "**************************************"

	# Create repo with dependencies
	start-sleep -m 10000
	CreateRepo $tcoInstances $tcosharedInstances

	write-host "Repo $repoName Created"

	exit 0

}

function CreateRepo($tcoList,$tcosharedList) {
	# Interface with API to create Instance

	# Generate Repo Name, Create repo

	$repoName = "ECom_Daily_" + $envType
	foreach ($bid in $buildIDs) {
		$repoName = $repoName + "_" + $bid
	}

	$repoName = $repoName + "_[" + $(get-date -f "yyyy-MM-dd_HH:mm:ss") + "]"

	write-host "Repo Name is $repoName"

	write-host "repo add $repoRole $repoName"
	RunAPICommand "repo add $repoRole $repoName"
	
	write-host "Adding instances to repo $repoName"

	# Add instances to Repo
	
	# Add WebSite Backup package to Repo
	write-host "Adding instance of $tcoWebSiteBackupPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${tcoWebSiteBackupPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${tcoWebSiteBackupPackage}:Master.1"
	start-sleep -m 1000
	$lastPackInst = $tcoWebSiteBackupPackage + ":Master.1" 
	
	$last = $nul
	$setDepend = $true
	foreach ($inst in $tcoList)  {
		write-host "Adding instance $inst to $repoName"
		write-host "-----------------------------------"

		# add instance to repo
		write-host "repo artifact add instance $repoName ${tcoPackageName}:${inst}"
		RunAPICommand "repo artifact add instance $repoName ${tcoPackageName}:${inst}"
		start-sleep -m 1000
		if ($setDepend) {
			write-host "repo artifact depend add $repoName ${tcoPackageName}:${inst} $lastPackInst"
			#RunAPICommand "repo artifact depend add $repoName ${tcoPackageName}:${inst} ${tcoPackageName}:${last}"
			RunAPICommand "repo artifact depend add $repoName ${tcoPackageName}:${inst} $lastPackInst"
		}
		$last = $inst
		$setDepend = $true
		# Keep the last package instance added to repo
		$lastPackInst = $tcoPackageName + ":" + $last
	}

	$last = $nul
	$setDepend = $true
	foreach ($inst in $tcosharedList)  {
		write-host "Adding instance $inst to $repoName"
		write-host "-----------------------------------"

		# add instance to repo
		write-host "repo artifact add instance $repoName ${tcosharedPackageName}:${inst}"
		RunAPICommand "repo artifact add instance $repoName ${tcosharedPackageName}:${inst}"
		start-sleep -m 1000
		if ($setDepend) {
			write-host "repo artifact depend add $repoName ${tcosharedPackageName}:${inst} $lastPackInst"
			#RunAPICommand "repo artifact depend add $repoName ${tcosharedPackageName}:${inst} ${tcosharedPackageName}:${last}"
			RunAPICommand "repo artifact depend add $repoName ${tcosharedPackageName}:${inst} $lastPackInst"
		}
		$last = $inst
		$setDepend = $true
		# Keep the last package instance added to repo
		$lastPackInst = $tcosharedPackageName + ":" + $last
	}

	# Add Web Content Update package to Repo
	write-host "Adding instance of $tcoWebContentPushPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${tcoWebContentPushPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${tcoWebContentPushPackage}:Master.1"
	start-sleep -m 1000
	write-host "repo artifact depend add $repoName ${tcoWebContentPushPackage}:Master.1 $lastPackInst"
	RunAPICommand "repo artifact depend add $repoName ${tcoWebContentPushPackage}:Master.1 $lastPackInst"
	$lastPackInst = $tcoWebContentPushPackage + ":Master.1"
	
    # Add Web.config Update package to Repo
    write-host "Adding instance of $tcoWebConfigPushPackage to $repoName"
    Write-host "repo artifact add instance $repoName ${tcoWebConfigPushPackage}:Master.1"
    RunAPICommand "repo artifact add instance $repoName ${tcoWebConfigPushPackage}:Master.1"
    start-sleep -m 1000
	write-host "repo artifact depend add $repoName ${tcoWebConfigPushPackage}:Master.1 $lastPackInst"
    RunAPICommand "repo artifact depend add $repoName ${tcoWebConfigPushPackage}:Master.1 $lastPackInst"
    $lastPackInst = $tcoWebConfigPushPackage + ":Master.1"
    
	# Add Web Sync package to Repo
	write-host "Adding instance of $tcoWebSyncPackage to $repoName"
	Write-host "repo artifact add instance $repoName ${tcoWebSyncPackage}:Master.1"
	RunAPICommand "repo artifact add instance $repoName ${tcoWebSyncPackage}:Master.1"
	start-sleep -m 1000
	write-host "repo artifact depend add $repoName ${tcoWebSyncPackage}:Master.1 $lastPackInst"
	RunAPICommand "repo artifact depend add $repoName ${tcoWebSyncPackage}:Master.1 $lastPackInst"

 # Create instance from repo
 #write-host "Creating Instance from repo $repoName"
 #write-host "--------------------------------------"
 #write-host "instance create repo $repoName"
 #RunAPICommand "instance create repo $repoName"

}

function CreateInstance($dtype,$etype,$bid,$instName) {
	# Interface with API to create Repo

	$package=$nul

	if ($dtype -eq "tco")  {
		$package = $tcoPackageName
	}
	elseif ($dtype -eq "tcoshared")  {
		$package = $tcosharedPackageName
	}
	
	write-host "Instance name is $instName"
	
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
			Write-Error "Error creating instance ${package}:${instName}"
			exit 1
		}
		if ($checkReady.Contains("Object not found"))  {
			Write-Error "Object not found creating instance ${package}:${instName}"
			exit 1
		}
	}
	write-host "Instance ${package}:${instName} created successfully"	


	# return instanceName
	return $instName
}

function RunAPICommand($apiCommand)  {
	## write the command
	$writer.WriteLine($apiCommand) 
	$writer.Flush() 
                
	## wait some time 
	start-sleep -m 100
                
	## get any output from the socket
	#$SCRIPT:output += GetOutput
	GetOutput
}


## Read output from a remote host 
function GetOutput 
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

    if($outputBuffer)  
    {  
        foreach($line in $outputBuffer.Split("`n")) 
            { 
                write-host $line 
            } 
    }    
    $outputBuffer
}

. Main