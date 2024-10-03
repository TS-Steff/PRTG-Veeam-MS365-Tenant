# PRTG-Veeam-MS365-Tenant
 Monitors jobs and repositories of a given tenant

 all Credits to BasvanH https://github.com/BasvanH

# Compatibility
| script                                 | Veeam MS365 version |
|:---------------------------------------|:--------------------|
| PRTG-veeam-backup-MS365-tenants.ps1    | V8.x                |
| PRTG-veeam-backup-MS365-tenants_v7.ps1 | V7.x                |

# Original Links
 https://github.com/BasvanH

 https://gist.github.com/BasvanH

# Install and usage
- If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
- On your probe, add script to 'Custom Sensors\EXEXML' folder
- In PRTG, on your probe add EXE/Script Advanced sensor
- Name the sensor eg: Veeam Backup for Office 365
- In the EXE/Script dropdown, select the script
- In parameters set: -username "%windowsdomain\%windowsuser" -password "%windowspassword" -apiUrl "https://<url-to-vbo-api>:443" -orgName "tenant.onmicrosoft.com" -ignoreSSL "false"
    - This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
- Set preferred timeout and interval
- I've set some default limits on the channels, change them to your preferred levels

# Parameters
| param         | example                           | type    | description
|:--------------|:----------------------------------|:--------|:-
| apiUrl        | https://<url-to-vbo-api>:443      | string  | The url to your Veeam MS365 API
| username      | %windowsdomain\%username          | string  | username to connect to the API
| password      | %windowspassword                  | string  | users passwort for API connection
| orgName       | tenant.onmicrosoft.com            | string  | orgname in Veeam for MS365
| ignoreSSL     | -ignoreSSL "true"                 | string  | skip SSL-Cert validation
| jobsOnly      | -jobsOnly $true                   | boolean | returns only the job info and skips repo info
| debug         | -debug $true                      | boolean | prints out debug info. use in PS!

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

