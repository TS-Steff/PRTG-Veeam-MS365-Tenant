<#
    .SYNOPSIS
        PRTG Veeam Backup for Microsoft 365 Advanced Sensor.
  
    .DESCRIPTION
        Advanced Sensor will Report last Job status for all jobs.

        - If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
        - On your probe, add script to 'Custom Sensors\EXEXML' folder
        - In PRTG, on your probe add EXE/Script Advanced sensor
        - Name the sensor eg: Veeam Backup for Office 365
        - In the EXE/Script dropdown, select the script
        - In parameters set: -username '%windowsdomain\%windowsuser' -password '%windowspassword' -apiUrl 'https://<url-to-vbo-api>:443' -ignoreSSL 'true' -debug $false
        - This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
        - Set preferred timeout and interval (do not use interval under 1h)
	
    .PARAMETER apiUrl
        The url to your Veeam MS365 API https://<url-to-vbo-api>:443

    .PARAMETER username
        The username to connect with the API
        %windowsdomain\%windowsuser should work within PRTG

    .PARAMETER pasword
        The users password to connect with the API
        %windowspassword shoud work within PRTG

    .PARAMETER ignoreSSL
        does not validate SSL Certificate

    .PARAMETER debug
        use for debug if you run the skript directly from powershell

    .EXAMPLE
        -username '%windowsdomain\%windowsuser' -password '%windowspassword' -apiUrl 'https://<url-to-vbo-api>:443' -ignoreSSL 'true'

    .NOTES
        Author: TS-Management GmbH, Stefan Müller, kontakt@ts-management.ch
        For issues, suggetions and forking please use Github.
   
    .LINK
        https://github.com/BasvanH
        https://gist.github.com/BasvanH
    

    .NOTES
    2025-01-23 - first version

 #>

 param (
    [string]$apiUrl = $(throw "<prtg><error>1</error><text>-apiUrl is missing in parameters</text></prtg>"),
    [string]$username = $(throw "<prtg><error>1</error><text>-username is missing in parameters</text></prtg>"),
    [string]$password = $(throw "<prtg><error>1</error><text>-password is missing in parameters</text></prtg>"),
    [string]$ignoreSSL = $(throw "<prtg><error>1</error><text>-ignoreSSL is missing in parameters</text></prtg>"),
    [boolean]$debug = $false
)

if($debug){
    write-host "*******************" -ForegroundColor Red
    write-host "!!! DEBUG MODE !!! " -ForegroundColor Red
    write-host "*******************" -ForegroundColor Red
}

if($ignoreSSL -eq 'true'){
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;

    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

#region: Authenticate
$url = '/v8/token'
$body = @{
    "username" = $username;
    "password" = $password;
    "grant_type" = "password";
    "disable_antiforgery_token"="true";
}
$headers = @{
    "Content-Type"= "application/x-www-form-urlencoded"
}

try {
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Body $body -Headers $headers -Method Post -UseBasicParsing
} Catch {
    Write-Error "Error invoking web request at Start"
    Write-Host $_.exception.innerexception.errorcode -BackgroundColor Red
    Write-Host $_.exception.innerexception.Message -BackgroundColor Red
    Write-Host $_.exception.innerexception.Data -BackgroundColor Red
    Write-Host $_.exception.innerexception.HResult -BackgroundColor Red
}

Try {
    $authResult = ConvertFrom-Json($jsonResult.Content)
    $accessToken = $authResult.access_token
}catch{
    Write-Error "Error authentication result"
}

if($debug){write-host "jsonResult:" $authResult -ForegroundColor Green}
#endregion

function getOrgNameByID($orgID){
    #$url = "/v8/Jobs?organizationId=$orgID"
    #$url = '/v8/Organizations/?limit=100' # default limit is set to 30

    $url = "/v8/Organizations/$orgID/?limit=100" # default limit is set to 30

    $headers = @{
        "accept"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }

    try{
        $jsonResultOrg = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }
    
    # Convert JSON to a Powershell object
    $orgsObj = $jsonResultOrg | ConvertFrom-Json

    return $orgsObj.name
}

function getAllJobs(){
    if($debug){write-host "START - getAllJobs" -ForegroundColor Cyan}

    $url = '/v8/Jobs?limit=100' # default limit is set to 30

    $headers = @{
        "accept"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }

    try{
        $jsonResultOrg = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }
    
    # Convert JSON to a Powershell object
    $orgsObj = $jsonResultOrg | ConvertFrom-Json
    
    # Access the "restults"
    $jobsResults = $orgsObj.results
    
    foreach($job in $jobsResults){

        # Change Job State to int for lookup
        Switch -wildcard ($job.lastStatus.ToLower()) {
            '*success*' {$jobStatus = 0}
            '*warning*' {$jobStatus = 1}
            '*failed*' {$jobStatus = 2}
            default {$jobStatus = 3}
        }        

        if($debug){
            write-host $job.organizationId -ForegroundColor Blue
            getOrgNameByID($job.organizationId)
            write-host $job.name
            write-host $job.lastStatus
            write-host $jobStatus
            write-host $job.lastBackup
            write-host "----"   
        }

        # create table
        $jobObject = [PSCustomObject]@{
            "orgName"  = getOrgNameByID($job.organizationId)
            "state" = $jobStatus
        }
        $jobsTable.add($jobObject)

    }

    if($debug){ write-host "END - getAllJobs" -ForegroundColor Cyan } 
}

$jobsTable = [System.Collections.Generic.List[object]]::new()

getAllJobs

if($debug){ $jobsTable | Format-Table * -Autosize }


#region: jobs to PRTG results
$prtgResult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>
  <text></text>
"@

foreach($job in $jobsTable){
    $orgName = $job.orgName
    $jobResult = $job.state


$prtgresult += @"
  <result>
    <channel>$orgName</channel>
    <unit>Custom</unit>
    <value>$jobResult</value>
    <showChart>1</showChart>
    <showTable>1</showTable>
    <ValueLookup>ts.veeam.ms365.jobstatus</ValueLookup>
  </result>

"@
}

$prtgresult += @"
</prtg>
"@

$prtgResult
#endregion