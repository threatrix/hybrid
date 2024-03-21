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


Write-Host "The following versions of Threatrix components are installed in your Hybrid Environment:"
Write-Host 
Write-Color "  Threat Center:", " $UX_VERSION" -Color Blue, Yellow
Write-Color "  APP          :", " $APP_VERSION" -Color Blue, Yellow
