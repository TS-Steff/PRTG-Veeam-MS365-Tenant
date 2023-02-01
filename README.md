# PRTG-Veeam-MS365-Tenant
 Monitors jobs and repositories of a given tenant

 all Credits to BasvanH https://github.com/BasvanH


# Original Links
 https://github.com/BasvanH

 https://gist.github.com/BasvanH

# Install and usage
- If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
- On your probe, add script to 'Custom Sensors\EXEXML' folder
- In PRTG, on your probe add EXE/Script Advanced sensor
- Name the sensor eg: Veeam Backup for Office 365
- In the EXE/Script dropdown, select the script
- In parameters set: -username "%windowsdomain\%windowsuser" -password "%windowspassword" -apiUrl "https://<url-to-vbo-api>:443" -orgName "tenant.onmicrosoft.com" -ignoreDefRepo "false" -ignoreSSL "false"
    - This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
- Set preferred timeout and interval
- I've set some default limits on the channels, change them to your preferred levels
