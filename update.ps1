param (
    [string]$u="latest",
    [string]$a="latest",
    [int16]$p=80,
    [switch]$h,
    [switch]$s
)

Install-Module -Scope CurrentUser -Confirm PSWriteColor
Clear-Host

$UX = $u
$APP = $a
$PORT = $p
$HELP = $h
$HTTPS = $s
$THREATRIX_NET = "threatrix-net"
$OLD_UX_VERSION = ""
$OLD_APP_VERSION = ""
$UX_VERSION = ""
$APP_VERSION = ""
$HOSTNAME = $env:COMPUTERNAME
$ARG0 = Split-Path -Leaf $MyInvocation.MyCommand.Path
$LOG_FILE = "update.log"

function banner {
    Write-Host "                                            " -BackgroundColor White
    Write-Host "    " $args  "    "-ForegroundColor Blue -BackgroundColor White
    Write-Host "                                            " -BackgroundColor White
    Write-Host "         " $(Get-Date -UFormat "%a %D %r") "         " -ForegroundColor Blue -BackgroundColor White
    Write-Host "                                            " -BackgroundColor White
    Write-Host -ForegroundColor White
}

function usage {
    Write-Host "Usage: $ARG0 -h -u <ux tag> -a <app tag> -p <port number> -s"
    Write-Host " -h : Help"
    Write-Host " -u <ux tag>: Version of the UX image you want to upgrade to. Default is latest"
    Write-Host " -a <app tag>: Version of the APP image you want to upgrade to. Default is latest"
    Write-Host " -p <port number>: Port number which threatrix applcation can use. Default is 80"
    Write-Host " -s Enable HTTPS."
    exit 0
}

function connect_containers
{
    # Get a list of all Docker networks
    $NETWORKS = docker network ls --format '{{.Name}}'

    # Get a list of all running Docker containers
    $CONTAINERS = docker ps --format '{{.Names}}'
 
    # Define an array of Threatrix containers
    $TRX_CONTAINERS = @("threatrix-hybrid-app", "threatrix-threat-center", "threatrix-db", "rabbitmq")

    # Print a message indicating that the containers are being disconnected
    Write-Host "Disconnecting containers $TRX_CONTAINERS ...."

    # Disconnect the Threatrix containers from all networks
    foreach ($net in $NETWORKS) {
        foreach ($cont in $CONTAINERS) {
            if ($TRX_CONTAINERS -contains $cont) {
                docker network disconnect $net $cont *> $null
            }
        }
    }

    # Print a message indicating that the containers are being connected to the Threatrix network
    Write-Host "Connecting containers to $THREATRIX_NET ...."

    # Connect the Threatrix database container to the Threatrix network
    docker network connect $THREATRIX_NET threatrix-db >> update.log
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to connect Threatrix database to $THREATRIX_NET. Please correct the problem and upgrade...." -ForegroundColor Red
        Write-Host 
        exit
    } 

    docker network connect $THREATRIX_NET rabbitmq >> update.log
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$($env:RED)Failed to connect Threatrix database to $($env:WHITE)$THREATRIX_NET. $($env:RED)Please correct the problem and upgrade...." -ForegroundColor Red
        Write-Host 
        exit
    } 
    docker restart threatrix-db rabbitmq >> update.log
	docker network prune -f
}

function wait_for_confirmation {
    $prompt=$true
    while ($prompt) {
        $yn = Read-Host "Do you want to continue? (y or n ) "
        switch -wildcard ($yn) {
            "y" {
                Write-Host 
                Write-Host "Proceeding with update..." -ForegroundColor Green
                Write-Host 
                $prompt=$false
            }
            "n" {
                Write-Host
                Write-Host "Aborting update!" -ForegroundColor Red
                Write-Host
                exit
            }
            default {
                Write-Host "Please answer yes or no."
            }
        }
    }
}

# help option
if ($HELP) {
    usage
}

# Get Latest UX version
$string = docker exec -it threatrix-threat-center cat /var/www/html/assets/version.json | Select-String -Pattern 'version'
if ($string -match '"(\d+\.\d+\.\d+\.\d+)"')
{
    $OLD_UX_VERSION = $matches[1]
}
else {
    $OLD_UX_VERSION = "unknown"
}

# Get latest app version
$OLD_APP_VERSION = docker exec -it threatrix-hybrid-app cat /opt/threatrix/version
if ($LASTEXITCODE -ne 0) {
    $OLD_APP_VERSION = "unknown"
}

banner "Welcome to Threatrix Hybrid Update"
Write-Host
Write-Host "Updating your Hybrid Environment with the following components:"
Write-Host
Write-Color "  Threat Center:", " $UX" -Color Blue, Yellow
Write-Color "  APP          :", " $APP" -Color Blue, Yellow
Write-Host

wait_for_confirmation

# Check if Threatrix network exists. If not, create it and restart all containers to use it.
Remove-Item -Path update.log -ErrorAction SilentlyContinue
$val = (docker network ls | Select-String -Pattern $THREATRIX_NET -SimpleMatch)

if ($null -ne $val) {
    Write-Host "Threatrix Network exists!" -ForegroundColor Green
} else {
    Write-Host "Threatrix Network does not exist!" -ForegroundColor Green
    Write-Host "Creating Threatrix Network.."
    docker network create $THREATRIX_NET >> update.log
    Write-Host "Restarting containers to use $THREATRIX_NET"
    connect_containers
}

Write-Host "Updating Threatrix App and Threat Center...."
docker container rm -f threatrix-threat-center threatrix-hybrid-app *> $null
docker pull -q threatrix/hybrid-app:$APP >> update.log
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to download Threatrix Application threatrix/hybrid-app:$APP. Please correct the problem and update...." -ForegroundColor Red
    exit
}
docker pull -q threatrix/threat-center:$UX >> update.log
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to download Threatrix UI threatrix/threat-center:$UX. Please correct the problem and update...." -ForegroundColor Red
    exit
}

Write-Host "Restarting Threatrix App and Threat Center containers...."
docker run -d --restart always --network $THREATRIX_NET --name threatrix-hybrid-app -e THREATRIX_DB_SVC=threatrix-db -e THREATRIX_MQ_SVC=hybrid-mq --hostname hybrid-app -d threatrix/hybrid-app:$APP >> update.log

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start Threatrix Application. Please correct the problem and update...." -ForegroundColor Red
    exit
}
Write-Host "Restarted Threatrix App Successfully!" -ForegroundColor Green

if ($HTTPS) {
    docker run -d --network ${THREATRIX_NET} --hostname threatrix-web -p ${PORT}:443 --restart always --name threatrix-threat-center -e BACKEND=threatrix-hybrid-app -e BACKEND_PORT=8080 threatrix/threat-center:${UX} >> update.log
} else {
    docker run -d --network ${THREATRIX_NET} --hostname threatrix-web -p ${PORT}:80 --restart always --name threatrix-threat-center -e BACKEND=threatrix-hybrid-app -e BACKEND_PORT=8080 threatrix/threat-center:${UX} >> update.log
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start Threatrix Threat Center. Please correct the problem and update...." -ForegroundColor Red
    exit
}
Write-Host "Restarted Threatrix Threat Center Successfully!" -ForegroundColor Green
# Wait for containers to come up
Start-Sleep -Seconds 10

# Get Latest UX version
$string = docker exec -it threatrix-threat-center cat /var/www/html/assets/version.json | Select-String -Pattern 'version'
if ($string -match '"(\d+\.\d+\.\d+\.\d+)"')
{
    $UX_VERSION = $matches[1]
}
else {
    $UX_VERSION = "unknown"
}

# Get latest app version
$APP_VERSION = docker exec -it threatrix-hybrid-app cat /opt/threatrix/version
if ($LASTEXITCODE -ne 0) {
    $APP_VERSION = "unknown"
}

Write-Host "Upgraded the following Threatrix components in your Hybrid Environment:"
Write-Host
Write-Color "Threat Center: from ", "$OLD_UX_VERSION ", "to ", "$UX_VERSION" -Color Blue, Yellow, Blue, Yellow
Write-Color "Threatix Applicaion: from ", "$OLD_APP_VERSION ", "to ", "$APP_VERSION" -Color Blue, Yellow, Blue, Yellow
Write-Host
Write-Color "Use the following URL to access Threat Center:", " http://${HOSTNAME}:${PORT}/" -Color Blue, Green
Write-Host
banner "Threatrix Hybrid Update complete! "