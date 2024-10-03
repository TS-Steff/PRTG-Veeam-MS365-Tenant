<#
    .SYNOPSIS
        PRTG Veeam Backup for Microsoft 365 Advanced Sensor.
  
    .DESCRIPTION
        Advanced Sensor will Report Job status, job nested status, repository statistics and proxy status.

        - If not already done, enable the the API in VBO https://helpcenter.veeam.com/docs/vbo365/rest/enable_restful_api.html?ver=20
        - On your probe, add script to 'Custom Sensors\EXEXML' folder
        - In PRTG, on your probe add EXE/Script Advanced sensor
        - Name the sensor eg: Veeam Backup for Office 365
        - In the EXE/Script dropdown, select the script
        - In parameters set: -username '%windowsdomain\%windowsuser' -password '%windowspassword' -apiUrl 'https://<url-to-vbo-api>:443' -orgName 'tenant.onmicrosoft.com' -ignoreDefRepo 'false' -ignoreSSL 'true' -debug $false
        - This way the Windows user defined on the probe is used for authenticating to VBO API, make sure the correct permissions are set in VBO for this user
        - Set preferred timeout and interval
        - I've set some default limits on the channels, change them to your preferred levels
	
    .PARAMETER apiUrl
        The url to your Veeam MS365 API https://<url-to-vbo-api>:443

    .PARAMETER username
        The username to connect with the API
        %windowsdomain\%windowsuser should work within PRTG

    .PARAMETER pasword
        The users password to connect with the API
        %windowspassword shoud work within PRTG
    
    .PARAMETER orgName
        the organisation Name to check 'tenant.onmicrosoft.com'

    .PARAMETER ignoreSSL
        does not validate SSL Certificate

    .PARAMETER jobsOnly
        returns only the job results


    .EXAMPLE
        -username '%windowsdomain\%windowsuser' -password '%windowspassword' -apiUrl 'https://<url-to-vbo-api>:443' -orgName 'tenant.onmicrosoft.com' -ignoreDefRepo 'false' -ignoreSSL 'true' -debug $false

    .NOTES
        Author: TS-Management GmbH, Stefan Müller, kontakt@ts-management.ch

        For issues, suggetions and forking please use Github.
   
    .LINK
        https://github.com/BasvanH
        https://gist.github.com/BasvanH
    

    .NOTES
    2023-03-16 - Line 157: replacing v7 with v6 - API does not support v7 jobSessions atm.
    2024-09-16 - Update to Veeam MS365 Backup 8.x

 #>

 param (
    [string]$apiUrl = $(throw "<prtg><error>1</error><text>-apiUrl is missing in parameters</text></prtg>"),
    [string]$username = $(throw "<prtg><error>1</error><text>-username is missing in parameters</text></prtg>"),
    [string]$password = $(throw "<prtg><error>1</error><text>-password is missing in parameters</text></prtg>"),
    [string]$orgName = $(throw "<prtg><error>1</error><text>-orgName is missing in parameters</text></prtg>"),
    #[string]$ignoreDefRepo = $(throw "<prtg><error>1</error><text>-ignoreDefRepo is missing in parameters</text></prtg>"),
    [string]$ignoreSSL = $(throw "<prtg><error>1</error><text>-ignoreSSL is missing in parameters</text></prtg>"),
    [boolean]$jobsOnly = $false,
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

$vboJobs = @()

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
}

Try {
    $authResult = ConvertFrom-Json($jsonResult.Content)
    $accessToken = $authResult.access_token
}catch{
    Write-Error "Error authentication result"
}

if($debug){write-host "jsonResult:" $authResult -ForegroundColor Green}

#endregion

function getAllOrgLinks($orgName){
    if($debug){
        write-host "START - getAllOrgLinks" -ForegroundColor Cyan
        write-host "OrgName:" $orgName -ForegroundColor Cyan
    }

    $url = '/v8/Organizations?limit=100' # default limit is set to 30

    $headers = @{
        "accept"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }

    if($debug){ write-host $apiUrl$url -ForegroundColor Cyan }   
    
    try{
        $jsonResultOrg = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }
  
    if($debug){ Write-Host ConvertFrom-Json($jsonResultOrg.Content) -ForegroundColor Cyan }
    
    # Convert JSON to a Powershell object
    $orgsObj = $jsonResultOrg | ConvertFrom-Json
    
    # Access the "restults"
    $orgsResults = $orgsObj.results

    # extract all organization names
    $allOrgNames = $orgsResults.name

    # write all orgas down
    if($debug){ write-host $allOrgNames -ForegroundColor Cyan }

    if($orgName -in $allOrgNames){
        if($debug){write-host "!!! FOUND $orgName in orglist" -ForegroundColor Red}

        # Get org data
        $org = $orgsResults | Where-Object { $_.name -eq $orgName}

        if($debug){ 
            write-host $org -ForegroundColor Cyan
            Write-host "OrgID: " $org.id -ForegroundColor Cyan
        }

        # ToDo: Check if all of this elemets are needed
        #create link list
        $orgInfos = [PSCustomObject]@{
            orgID       = $org.id                             # needed
            lSelf       = $org._links.self.href   
            lJobs       = $org._links.jobs.href
            lUsedRepos  = $org._links.usedRepositories.href   # used
        }

        if($debug){write-host "orgLinks:" $orgInfos -ForegroundColor Cyan}
    }else{
        write-host "NO Match in orgList for $orgName" -ForegroundColor Red
        if($debug){ write-host "END - getAllOrgLinks" -ForegroundColor Cyan }
        Exit 1
    }

    if($debug){ write-host "END - getAllOrgLinks" -ForegroundColor Cyan } 

    return $orgInfos    
}

function getOrgJobsDetails($orgID){
    if($debug){
        write-host "START - getOrgJobsDetails" -ForegroundColor Yellow
        write-host "orgID: " $orgID -ForegroundColor Yellow
    }
    
    $url = "/v8/Jobs?organizationId=$orgID"

    if($debug){write-host "API URL: " $apiUrl$url -ForegroundColor Yellow}

    $headers = @{
        "Content-Type"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }

    try{
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }

    #$jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

    if($debug){Write-Host ConvertFrom-Json($jsonResult.Content) -ForegroundColor Yellow}

    Try {
        $jobs = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in result getOrgJobsLinks"
        Exit 1
    }  

    # Convert JSON to PS obj
    $jobs = $jsonResult | ConvertFrom-Json
    
    # access results
    $jobs = $jobs.results
    
    if($debug){write-host "JOBS:" $jobs -ForegroundColor yellow}
    foreach($job in $jobs){   
        #$v6SessionsLink = $job._links.jobsessions.href -replace '/v8/', '/v6/'
        #$v6SessionsLink = $v6SessionsLink.ToString()
        getOrgJobSessionDetails $job.id $job._links.jobsessions.href
        #getOrgJobSessionDetails $v6SessionsLink $job.id
        #getOrgJobSessionDetails $v6SessionsLink $job.id
        if($debug){
            write-host "************************************************************"    -ForegroundColor Yellow
            write-host "name:       " $job.name                                          -ForegroundColor Yellow
            write-host "id:         " $job.id                                            -ForegroundColor Yellow
            write-host "lastRun:    " $job.lastRun                                       -ForegroundColor Yellow
            write-host "lastStatus: " $job.lastStatus                                    -ForegroundColor Yellow
            write-host "************************************************************"    -ForegroundColor Yellow
        }
    }
    if($debug){ write-host "END - getOrgJobsDetails" -ForegroundColor yellow }
}

function getOrgJobSessionDetails(){
    Param(
        [Parameter(Mandatory = $true)] [string] $id,
        [Parameter(Mandatory = $false)] $link
        
    )
        
    if($debug){
        write-host "START - getOrgJobSessionDetails" -ForegroundColor Green
        write-host "*** Job Detials" $link -ForegroundColor Green
        write-host "jobID:" $id -ForegroundColor Green
    }
    

    $url = "/v8/JobSessions?JobId=$id&limit=2&offset=0"
    
    $headers = @{
        "Content-Type"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }

    write-host $apiUrl$url  -ForegroundColor Green

    try{
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }    

    # convert JSON to PS object
    $objResults = $jsonResult | ConvertFrom-Json

    $jobResults = $objResults.results
    #$jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    
    if($debug){Write-Host $jobResults -ForegroundColor Green}
    
    <#
    Try {
        $sessions = (ConvertFrom-Json($jsonResult.Content)).results
    } Catch {
        Write-Error "Error in result getOrgJobSessionDetails"
        Exit 1
    }  
    #>
     
    # Skip session currently active or user aborted, get last known run status
    if ($jobResults[0].status.ToLower() -in @('running', 'queued', 'stopped')) {
        $session = $jobResults[1]
    } else {
        $session = $jobResults[0]
    } 

 
    <#
    # Log Items
    write-host $session.id -BackgroundColor Yellow -ForegroundColor Black
    $url = '/v8/JobSessions/' + $session.id + '/LogItems?limit=1000000'
    write-host $url -BackgroundColor Yellow -ForegroundColor Black
    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }
    
    try{
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    } 

    # convert JSON to PS Obj
    $jobLogObj = $jsonResult | ConvertFrom-Json

    # Access results
    $jobLogResults = $jobLogObj.results

    write-host $jobLogResults -ForegroundColor Red    
    
    if($debug){
        write-host "JOB:" $job -ForegroundColor Blue
    }


       
    write-host $jobLogResults -ForegroundColor Red

    Try {
        $logItems = (ConvertFrom-Json($jsonResult.Content)).results
    } Catch {
        Write-Error "Error in logitems result"
    
    } 

    write-host $logItems -ForegroundColor Green
    
        # Log items to object
        ForEach ($logItem in $logItems) {
            $sCnt = 0;$wCnt = 0;$fCnt = 0
            Switch -wildcard ($logItem.title.ToLower()) {
                   '*success*' {$sCnt++}
                   '*warning*' {$wCnt++}
                   '*failed*' {$fCnt++}
            }
        }
    #>
        Switch -wildcard ($session.status.ToLower()) {
                   '*success*' {$jobStatus = 0}
                   '*warning*' {$jobStatus = 1}
                   '*failed*' {$jobStatus = 2}
                   default {$jobStatus = 3}
        }

        # Thank you Veeam for fixing this!
        $transferred = $session.statistics.transferredDataBytes

        $myObj = "" | Select Jobname, Status, Start, End, Transferred, LastRun
			        $myObj.Jobname = $job.name
                    $myObj.Status = $jobStatus
                    $myObj.Start = Get-Date($session.creationTime)
                    $myObj.End = Get-Date($session.endTime)
                    $myObj.Transferred = $transferred
                    #$myObj.Success = $sCnt 
                    #$myObj.Warning = $wCnt
                    #$myObj.Failed = $fCnt
                    $myObj.LastRun = $job.lastRun

        $vboJobs += $myObj

        if($debug){
            write-host $vboJobs -ForegroundColor Green
            write-host "END - getOrgJobSessionDetails" -ForegroundColor Green
        }

        return $vboJobs
}

function getOrgRepoLinks($link){
    if($debug){write-host "START - getOrgRepoLinks" -ForegroundColor Cyan}
    
    $url = $link

    $headers = @{
        "Content-Type"= "application/json";
        "Authorization" = "Bearer $accessToken";
    }
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    #Write-Host ConvertFrom-Json($jsonResult.Content) -ForegroundColor Cyan

    Try {
        $repos = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in result getOrgRepoLinks"
        Exit 1
    }    

    $orgRepoLinks = @()
    $repos = $jsonResult | ConvertFrom-Json
    foreach ($repoLink in $repos.results._links.backupRepository.href){
        $orgRepoLinks += $repoLink
    }

    if($debug){
        write-host $orgRepoLinks
        write-host "END - getOrgRepoLinks" -ForegroundColor Cyan
    }
    return $orgRepoLinks
}

function getOrgRepoDetails($orgRepoLink){
    if($debug){write-host "START - getOrgRepoDetails" -ForegroundColor Cyan}
    #write-host "*** ORG REPO LINK" $orgRepoLink -ForegroundColor Green
    $url = $orgRepoLink

    $headers = @{ 
        "Content-Type"= "application/json"; 
        "Authorization" = "Bearer $accessToken"; 
    }

    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

    if($debug){Write-Host ConvertFrom-Json($jsonResult.Content) -ForegroundColor Cyan}

    Try {
        $repos = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in result getOrgRepoDetails"
        Exit 1
    }        

    $orgRepoDetails = $jsonResult | ConvertFrom-Json
    
    if($orgRepoDetails.name -ne 'Default Backup Repository'){
        $myObj = "" | Select Name, Capacity, Free
        $myObj.Name = $orgRepoDetails.name
        $myObj.Capacity = $orgRepoDetails.capacityBytes
        $myObj.Free = $orgRepoDetails.freeSpaceBytes
    }

    $repo += $myObj
    
    if($debug){write-host "END - getOrgRepoDetails" -ForegroundColor Cyan}
    return $repo
}

$orgInfos = getAllOrgLinks($orgName)

$orgJobsDetails = getOrgJobsDetails($orgInfos.orgID)

if($debug){
    write-host "*** JOBS ***" -ForegroundColor Green -NoNewline
    $orgJobsDetails | ft
}

# TODO
if(-not $jobsOnly){
    $orgRepoLinks = getOrgRepoLinks($orgInfos.lUsedRepos)
    $orgRepoDetails = @()
    foreach($orgRepoLink in $orgRepoLinks){
        $orgRepoDetails += getOrgRepoDetails($orgRepoLink)
    }
    if($debug){
        write-host "*** REPOS ****" -ForegroundColor Green -NoNewline
        $orgRepoDetails | ft
    }
}

#region: Jobs to PRTG results
Write-Host "<prtg>"
ForEach ($job in $orgJobsDetails){
    $channel = "Job: " + $job.Jobname + " | Status"
    $value = $job.Status
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>One</unit>"
                "<showChart>0</showChart>"
                "<showTable>1</showTable>"
                "<LimitMaxWarning>1</LimitMaxWarning>"
                "<LimitMaxError>2</LimitMaxError>"
                "<LimitMode>1</LimitMode>"
                "</result>"

    $channel = "Job: " + $job.Jobname + " | Runtime"
    $value = [math]::Round(($job.end - $job.start).TotalSeconds)
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>TimeSeconds</unit>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"    

    $channel = "Job: " + $job.Jobname + " | Transferred"
    $value = [long]$job.Transferred
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>BytesDisk</unit>"
                "<VolumeSize>Byte</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "<LimitMinWarning>20971520</LimitMinWarning>"
                "<LimitMinError>10485760</LimitMinError>"
                "<LimitMode>1</LimitMode>"
                "</result>"            
}
#endregion

#region: Repositories to PRTG results
if(-not $jobsOnly){
    ForEach ($repository in $orgRepoDetails) {
        #$reponame = $repository.name
        #write-host "Repo name: '$reponame'" -ForegroundColor red

        if($repository.name){
            $channel = "Repository: " + $repository.Name + " | Capacity"
            $value = $repository.Capacity
            Write-Host "<result>"
                        "<channel>$channel</channel>"
                        "<value>$value</value>"
                        "<unit>BytesDisk</unit>"
                        "<VolumeSize>GigaByte</VolumeSize>"
                        "<showChart>1</showChart>"
                        "<showTable>1</showTable>"
                        "</result>"    

            $channel = "Repository: " + $repository.Name + " | Free"
            $value = $repository.Free
            Write-Host "<result>"
                        "<channel>$channel</channel>"
                        "<value>$value</value>"
                        "<unit>BytesDisk</unit>"
                        "<VolumeSize>GigaByte</VolumeSize>"
                        "<showChart>1</showChart>"
                        "<showTable>1</showTable>"
                        "<LimitMinWarning>1073741824</LimitMinWarning>"
                        "<LimitMinError>536870912</LimitMinError>"
                        "<LimitMode>1</LimitMode>"
                        "</result>"

            $channel = "Repository: " + $repository.Name + " | Used"
            $value = $repository.Capacity - $repository.Free
            Write-Host "<result>"
                        "<channel>$channel</channel>"
                        "<value>$value</value>"
                        "<unit>BytesDisk</unit>"
                        "<VolumeSize>GigaByte</VolumeSize>"
                        "<showChart>1</showChart>"
                        "<showTable>1</showTable>"
                        "</result>"   

            $channel = "Repository: " + $repository.Name + " | Used Percent"
            $value = 100 / $repository.Capacity * ($repository.Capacity - $repository.Free)
            Write-Host "<result>"
                        "<channel>$channel</channel>"
                        "<value>$value</value>"
                        "<unit>Percent</unit>"
                        "<float>1</float>"
                        "<decimalMode>All</decimalMode>"
                        "<LimitMaxWarning>80</LimitMaxWarning>"
                        "<LimitMaxError>90</LimitMaxError>"
                        "<LimitMode>1</LimitMode>"
                        "<showChart>1</showChart>"
                        "<showTable>1</showTable>"
                        "</result>"                            
        }
    }
}
#endregion
Write-Host "<text>LastRun:" $job.LastRun"</text>"
Write-Host "</prtg>"