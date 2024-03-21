param (
    [string]$u="latest",
    [string]$a="latest",
    [string]$d="latest",
    [int16]$p=80,
    [switch]$h,
    [switch]$x
)

Install-Module -Scope CurrentUser -Confirm PSWriteColor
Clear-Host

$UX = $u
$APP = $a
$DB = $d
$PORT = $p
$HELP = $h
$skip_check = $x
$THREATRIX_NET = "threatrix-net"
$THREATRIX_DB = "threatrix-db"
$MIN_CPU = 8
$MIN_MEM = 30
$MIN_DISK = 250
$HOSTNAME = $env:COMPUTERNAME
$ARG0 = Split-Path -Leaf $MyInvocation.MyCommand.Path
$LOG_FILE = "install.log"


function banner {
  Write-Host "                                            " -BackgroundColor White
  Write-Host "    " $args "   "-ForegroundColor Blue -BackgroundColor White
  Write-Host "                                            " -BackgroundColor White
  Write-Host "           " $(Get-Date) "          " -ForegroundColor Blue -BackgroundColor White
  Write-Host "                                            " -BackgroundColor White
  Write-Host -ForegroundColor White
}
 
banner "Welcome to Threatrix Hybrid Install"

function usage {
  Write-Host "Usage: $ARG0 -h -u <ux tag> -a <app tag> -d <db tag>"
  Write-Host " -h : Help"
  Write-Host " -u <ux tag>: Version of the UX image you want to upgrade to. Default is latest"
  Write-Host " -a <app tag>: Version of the APP image you want to upgrade to. Default is latest"
  Write-Host " -d <db tag>: Version of the DB image you want to upgrade to. Default is latest"
  Write-Host " -p <port number>: Port number which threatrix applcation can use. Default is 80"
  Write-Host 
  exit 1
}

function check_disk {
    # Get the available disk space in bytes
    $available_space = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object -ExpandProperty FreeSpace)
 
    # Convert bytes to GB
    $available_space_gb = [math]::Round($available_space / 1GB, 2)
 
    # Check if available space is greater than or equal to 250GB
    $MIN_DISK = 250
    if ($available_space_gb -ge $MIN_DISK) {
        Write-Host "Met minimum disk space requirement of $MIN_DISK GB" -ForegroundColor Green
    } else {
        Write-Host 
        Write-Host "Only $available_space_gb is available on C:." -ForegroundColor Red
        Write-Host "Disk space is insufficient. Minimum disk space requirement is $MIN_DISK GB. Aborting install!" -ForegroundColor Red
        exit 1
    }
}

function check_ram {
    # Get the total memory in GB
    $total_mem = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB
 
    if ($total_mem -lt $MIN_MEM) {
        Write-Host 
        Write-Host "Only $total_mem_gb GB is available on /var/lib/docker." -ForegroundColor Red
        Write-Host "RAM is insufficient. Minimum RAM requirement is $MIN_MEM GB. Aborting install!" -ForegroundColor Red
        Write-Host
        exit 1
    } else {
        Write-Host "Met minimum RAM requirement of $MIN_MEM GB" -ForegroundColor Green
    }
}

function check_cpu {
    # Get the number of CPU cores
    $cpu_cores = $env:NUMBER_OF_PROCESSORS 
 
    if ($cpu_cores -le $MIN_CPU) {
        Write-Host "Met minimum CPU requirement of $MIN_CPU" -ForegroundColor Green
    } else {
        Write-Host 
        Write-Host "Only $cpu_cores are available."
        Write-Host "CPU is insufficient. Minimum CPU requirement is $MIN_CPU. Aborting install!"
        Write-Host
        exit 1
    }
}
 
function check_minimum_requirements {
    if (!$skip_check) {
        check_cpu
        check_ram
        check_disk
    }
}

function wait_for_confirmation {
    $prompt=$true
    while ($prompt) {
        $yn = Read-Host "Do you want to continue? y or n ) "
        switch -wildcard ($yn) {
            "y" {
                Write-Host 
                Write-Host "Proceeding with install..." -ForegroundColor Green
                Write-Host 
                $prompt=$false
            }
            "n" {
                Write-Host
                Write-Host "Aborting install!" -ForegroundColor Red
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

# Check if minimumhybrid requirements are met.
check_minimum_requirements
Write-Host
Write-Host "Installing the following components in your Hybrid Envirnment:"
Write-Host
Write-Color "  Threat Center:", " $UX" -Color Blue, Yellow
Write-Color "  APP          :", " $APP" -Color Blue, Yellow
Write-Color "  DB           :", " $DB" -Color Blue, Yellow
Write-Color "  Rabbit MQ    :", " rabbitmq:3" -Color Blue, Yellow
Write-Host

wait_for_confirmation

Write-Host "Downloading Container images...."
docker pull -q threatrix/hybrid-db:$DB > ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Unable to download threatrix/hybrid-db:$DB container image. Aborting install!" -ForegroundColor Red
    Write-Host 
    exit 1
}
Write-Host "Sucessfully downloaded threatrix/hybrid-db:$DB container image!" -ForegroundColor Green
docker pull -q threatrix/hybrid-app:$APP 2>&1 >> ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Unable to download threatrix/hybrid-app:$APP container image. Aborting install!"
    Write-Host 
    exit 1
}
Write-Host "Sucessfully downloaded threatrix/hybrid-app:$APP container image!" -ForegroundColor Green
docker pull -q threatrix/threat-center:$UX 2>&1 >> ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Unable to download threatrix/threat-center:$UX container image. Aborting install!" -ForegroundColor Red
    Write-Host 
    exit 1
}
Write-Host "Sucessfully downloaded threatrix/threat-center:$UX container image!" -ForegroundColor Green
docker pull -q rabbitmq:3 2>&1 >> ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Unable to download  rabbitmq:3 container image. Aborting install!" -ForegroundColor Red
    Write-Host 
    exit 1
}
Write-Host "Sucessfully downloaded rabbitmq:3 container image!" -ForegroundColor Green

# check if threat-network exists. If not, create it and restart all containers to use it.
docker network ls | Select-String $THREATRIX_NET *> $null
 
if ($LASTEXITCODE -eq 0) {
    Write-Host "Threatrix Network exists!" -ForegroundColor Green
} else {
    Write-Host "Threatrix Network does not exist!"
    Write-Host "Creating Threatrix Network.." -ForegroundColor Green
    Write-Output "Creating Threatrix Network.." >> ${LOG_FILE}
    docker network create $THREATRIX_NET >> ${LOG_FILE}
}

Write-Host "Starting containers...." -ForegroundColor Green
Write-Output "Starting containers...." >> ${LOG_FILE}


# check if DB container is already running
docker ps -a | findstr $THREATRIX_DB *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Warning: Threatrix DB Container already exists!" -ForegroundColor Yellow
    Write-Host "Stopping ${THREATRIX_DB} container and cleaning up." -ForegroundColor Yellow
    docker rm -f $THREATRIX_DB *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to stop Threatrix database. Please correct the problem and reinstall...." -ForegroundColor Red
        exit
    }

}
# check if threat-network exists. If not, create it and restart all containers to use it.
docker volumes ls $THREATRIX_DB *> $null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Warning: Threatrix DB Volume exists." -ForegroundColor Yellow
    Write-Host "Warning: Proceeding with install witll re-initilize the DB." -ForegroundColor Yellow
    wait_for_confirmation
    docker volume rm $THREATRIX_DB *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed clenup old $THREATRIX_DB. Please correct the problem and reinstall...." -ForegroundColor Red
        exit
    }
}
Write-Host "Creating Threatrix DB Volume." -ForegroundColor Green
Write-Output "Creating Threatrix DB Volume." >> ${LOG_FILE}
docker volume create $THREATRIX_DB >> ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed  to create $THREATRIX_DB. Please correct the problem and reinstall...." -ForegroundColor Red
    exit
}

# Deploy and Run Threatrix Database with newly create volume
docker run -d --network ${THREATRIX_NET} --restart always --name ${THREATRIX_DB} --volume ${THREATRIX_DB}:/var/lib/scylla --hostname threatrix-db -d threatrix/hybrid-db:$DB --smp 2 --memory 4G --developer-mode 1 >> ${LOG_FILE}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start Threatrix database. Please correct the problem and reinstall...." -ForegroundColor Red
    exit
}

# check if rabbit-mq container is already running
docker ps -a | findstr "rabbitmq" *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Warning: Rabbit MQ Container is already running!" -ForegroundColor Yellow
    Write-Host "Stopping Rabbit MQ container and cleaning up." -ForegroundColor Yellow
    docker rm -f rabbitmq *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to cleanup Rabbit MQ. Please correct the problem and reinstall...." -ForegroundColor Red
        exit
    }
} 
# Install and Run RabbitMQ
docker run -d --network ${THREATRIX_NET} --restart always --hostname hybrid-mq --name rabbitmq -e RABBITMQ_DEFAULT_USER=threatrix -e RABBITMQ_DEFAULT_PASS=DwkEc?#NxSJS_E6M%qcB rabbitmq:3 >> ${LOG_FILE}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start RabbitMQ. Please correct the problem and reinstall...." -ForegroundColor Red
    exit
}

# wait for database to init
Write-Host "Waiting for database to initialize...."
Start-Sleep -Seconds 30
# Setup schema
Write-Host "Creating schemas...."
docker exec -it threatrix-db cqlsh -f /opt/threatrix/threatrix-schema.cql >> ${LOG_FILE}
docker exec -it threatrix-db cqlsh -f /opt/threatrix/corp-keyspace-schema.cql >> ${LOG_FILE}

# Import licenses
Write-Host "Importing Licenses...."
docker exec -it threatrix-db cqlsh -e "COPY threatrix.license FROM '/opt/threatrix/license.cql' WITH HEADER=TRUE AND MINBATCHSIZE=1 AND MAXBATCHSIZE=1 AND PAGESIZE=10;" >> ${LOG_FILE}

Write-Host "Starting Threatrix Components...."
# check if threatrix-hybrid-app container is already running
docker ps -a | findstr "threatrix-hybrid-app"  *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Warning: threatrix-hybrid-app Container already exists!" -ForegroundColor Yellow
    Write-Host "Stopping  threatrix-hybrid-app container and cleaning up." -ForegroundColor Yellow
    docker rm -f threatrix-hybrid-app *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to stop Threatrix Backend Component. Please correct the problem and reinstall...." -ForegroundColor Red
        exit
    }

}
docker run -d --restart always --network=${THREATRIX_NET} --name threatrix-hybrid-app -e THREATRIX_DB_SVC=threatrix-db -e THREATRIX_MQ_SVC=hybrid-mq --hostname hybrid-app -d threatrix/hybrid-app:${APP} >> ${LOG_FILE}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start threatrix-hybrid-app. Please correct the problem and reinstall...." -ForegroundColor Red
    exit
}
Write-Host "Started Threatrix Backend Component Successfully!"  -ForegroundColor Green

# check if threatrix-web container is already running
docker ps -a | findstr "threatrix-threat-center"  *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Warning: threatrix-threat-center Container already exists!" -ForegroundColor Yellow
    Write-Host "Stopping  threatrix-threat-center container and cleaning up." -ForegroundColor Yellow
    docker rm -f threatrix-threat-center *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to stop Threatrix Frontent Component. Please correct the problem and reinstall...." -ForegroundColor Red
        exit
    }
}

docker run -d --network=${THREATRIX_NET} --hostname=threatrix-web -p ${PORT}:80 --restart always --name threatrix-threat-center -e BACKEND=threatrix-hybrid-app -e BACKEND_PORT=8080 threatrix/threat-center:${UX}  >> ${LOG_FILE}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start threatrix-web. Please correct the problem and reinstall...." -ForegroundColor Red
    exit 1
}
Write-Host "Started Threatrix Frontend Component Successfully!"  -ForegroundColor Green
# Get UX version from threat center container
$string = docker exec -it threatrix-threat-center cat /var/www/html/assets/version.json | Select-String -Pattern 'version'
if ($string -match '"(\d+\.\d+\.\d+\.\d+)"')
{
    $UX_VERSION = $matches[1]
}
else {
    $UX_VERSION = $UX
}


# Get APP version from hybrid app container
$APP_VERSION = docker exec -it threatrix-hybrid-app cat /opt/threatrix/version

if ($LASTEXITCODE -ne 0) {
    $APP_VERSION = $APP
}


Write-Host "Installed the following versions of Threatrix components in your Hybrid Environment:"
Write-Host 
Write-Color "  Threat Center:", " $UX_VERSION" -Color Blue, Yellow
Write-Color "  APP          :", " $APP_VERSION" -Color Blue, Yellow
Write-Host ""
Write-Color "Use the following URL to access Threat Center:", " http://${HOSTNAME}:${PORT}/" -Color Blue, Green
Write-Host ""
banner "Threatrix installation complete    "