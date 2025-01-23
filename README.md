# PRTG-Veeam-MS365-Tenant
 Monitors jobs and repositories of a given tenant or all tenants

 all Credits to BasvanH https://github.com/BasvanH

# Scripts and Compatibility
| script                                 | Veeam MS365 version | Description                        |
|:---------------------------------------|:--------------------|:-----------------------------------|
| PRTG-veeam-backup-MS365-tenants.ps1    | V8.x                | Full script for Veeam 8.x          |
| PRTG-veeam-backup-MS365-tenants_v7.ps1 | V7.x                | Full script for Veeam 7.x          |
| PRTG-veeam-backup-MS365-allTenants.ps1 | V8.x                | Returns all Jobs with last state   |

# Original Links
 https://github.com/BasvanH
 https://gist.github.com/BasvanH

# Install
## Full Skript
- ``Set-ExecutionPolicy -Scope CurrentUser`` in PS x64 AND x86
- If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
- On your probe, add script to 'Custom Sensors\EXEXML' folder
- In PRTG, on your probe add EXE/Script Advanced sensor
- Name the sensor eg: Veeam Backup for Office 365
- In the EXE/Script dropdown, select the script
- In parameters set: -username "%windowsdomain\%windowsuser" -password "%windowspassword" -apiUrl "https://\<url-to-vbo-api>:4443" -orgName "tenant.onmicrosoft.com" -ignoreSSL "false"
    - This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
- Set preferred timeout and interval
- I've set some default limits on the channels, change them to your preferred levels

## all Tenants
- ``Set-ExecutionPolicy -Scope CurrentUser`` in PS x64 AND x86
- If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
- On your probe, add script to 'Custom Sensors\EXEXML' folder
- In PRTG, on your probe add EXE/Script Advanced sensor
- Name the sensor eg: Veeam Backup for Office 365
- In the EXE/Script dropdown, select the script
- In parameters set: -username '%windowsdomain\%windowsuser' -password '%windowspassword' -apiUrl 'https://<url-to-vbo-api>:443' -ignoreSSL 'true' -debug $false
- This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
- Set preferred timeout and interval (do not use interval under 1h)

# Upgrade
## v7 to v8
 1. Replace the skript on your probe.
 2. Create new Sensor with the skript and copy the parameters from the old sensor to the new.
    - This is mandatory, as the skript for Veeam MS365 V8 does not include some values from the V7 script

# Parameters
| param         | example                           | type    | description
|:--------------|:----------------------------------|:--------|:-
| apiUrl        | https://\<url-to-vbo-api>:4443    | string  | The url to your Veeam MS365 API
| username      | %windowsdomain\%username          | string  | username to connect to the API
| password      | %windowspassword                  | string  | users passwort for API connection
| orgName       | tenant.onmicrosoft.com            | string  | orgname in Veeam for MS365
| ignoreSSL     | -ignoreSSL "true"                 | string  | skip SSL-Cert validation
| jobsOnly      | -jobsOnly $true                   | boolean | returns only the job info and skips repo info
| listOrgs      | -listOrgs $true                   | boolean | DEBUG PARAMETER - skript will only list all orgs on Server
| debug         | -debug $true                      | boolean | prints out debug info. use in PS!

You may need to wrap string parameters in quotes

# History
## 2024-10
 - Added parameter to return jobs only and ignore repo info.
 - fixed repo info

## 2024-09
 Script for V8. This one does not include the sensors
  - Job: *** | Success
  - Job: *** | Warning
  - Job: *** | Status  

These were counters for past backups.

