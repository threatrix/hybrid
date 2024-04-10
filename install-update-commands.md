## Linux
### Install
```
curl -s https://raw.githubusercontent.com/threatrix/hybrid/master/install --output install && chmod 0777 install && sudo ./install
```
DEPRECATED:
```
source <(curl -s https://raw.githubusercontent.com/threatrix/hybrid/master/install)
```

### Update
```
curl -s https://raw.githubusercontent.com/threatrix/hybrid/master/update --output update && chmod 0777 update && sudo ./update
```
DEPRECATED:
```
source <(curl -s https://raw.githubusercontent.com/threatrix/hybrid/master/update)
```

## Windows
### Install
```
Invoke-WebRequest -Uri https://github.com/threatrix/hybrid/blob/master/install.ps1  -OutFile .\install.ps1; .\install.ps1
```

### Update
```
Invoke-WebRequest -Uri https://github.com/threatrix/hybrid/blob/master/update.ps1  -OutFile .\update.ps1; .\update.ps1
```
