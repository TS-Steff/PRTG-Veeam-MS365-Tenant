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
	
    .NOTES
    For issues, suggetions and forking please use Github.
   
    .LINK
    https://github.com/BasvanH
    https://gist.github.com/BasvanH
    
    .TODO
    - Create Lookup OVL

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
if($debug){write-host "jsonResult:" $authResult -ForegroundColor Cyan}
if($debug){write-host "acces Token:" $accessToken -ForegroundColor Cyan}
#endregion

function getAllOrgLinks($orgName){
    if($debug){write-host "START - getAllOrgLinks" -ForegroundColor Cyan}
    $url = '/v8/Organizations?limit=100' # default limit is set to 30
    if($debug){write-host "OrgName:" $orgName -ForegroundColor green}
    
    $headers = @{
        "accept"= "application/json";
        "Authorization" = "Bearer $accessToken";
        
    }

    if($debug){
        write-host $apiUrl$url -ForegroundColor green
    }   
    #$jsonResult = Invoke-RestMethod -Uri $apiUrl$url -Method Get -Headers $headers -UseBasicParsing -ErrorVariable RespErr;
    
    try{
        $jsonResultOrg = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    }catch{
        $StatusCode = $_.Exception.Response.StatusCode

        write-host "status: " $StatusCode
        write-host "status: " $([int]$StatusCode)
    }
    
    if($debug){ write-host $RespErr }
    if($debug){ Write-Host ConvertFrom-Json($jsonResultOrg.Content) -ForegroundColor Yellow }
    
    Try {
        $orgas = ConvertFrom-Json($jsonResultOrg.Content)
    } Catch {
        Write-Error "Error in result getAllOrgLinks"
        Exit 1
    }
  
    $orgas = $jsonResultOrg | ConvertFrom-Json
    
    if($debug){
        foreach($orga in $orgas.results){
            write-host $orga.name -ForegroundColor Green
        }
    }

    if($orgName -in $orgas.results.name){
        if($debug){write-host "FOUND $orgName in orglist" -ForegroundColor Red}

        #get matching node
        $org = $orgas | Where-Object {$_.results.name -eq $orgName}
        
        write-host $orgas.results -ForegroundColor Blue

        #create link list
        $orgLinks = [PSCustomObject]@{
            self      = $org._links.self.href
            jobs      = $org._links.jobs.href
            usedRepos = $org._links.usedRepositories.href
        }

        if($debug){write-host "orgLinks:" $orgLinks -ForegroundColor Cyan}

    }else{
        write-host "NO Match in orgList for $orgName" -ForegroundColor Red
        if($debug){ write-host "END - getAllOrgLinks" -ForegroundColor Cyan }
        Exit 1
    }

    if($debug){ write-host "END - getAllOrgLinks" -ForegroundColor Cyan } 

    return $orgLinks    
}

function getOrgJobsDetails($link){
    if($debug){write-host "START - getOrgJobsDetails" -ForegroundColor Cyan}
    if($debug){write-host "*** Jobs link" $link -ForegroundColor Green}
    $url = $link

    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    if($debug){Write-Host ConvertFrom-Json($jsonResult.Content) -ForegroundColor Cyan}

    Try {
        $jobs = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in result getOrgJobsLinks"
        Exit 1
    }  
    
    $orgJobLinks = @()
    $jobs = $jsonResult | ConvertFrom-Json
    if($debug){write-host "JOBS:" $jobs -ForegroundColor yellow}
    foreach($job in $jobs){   
        $v6SessionsLink = $job._links.jobsessions.href -replace '/v7/', '/v6/'
        $v6SessionsLink = $v6SessionsLink.ToString()
        getOrgJobSessionDetails $v6SessionsLink $job.id
        #write-host "********************"
        #write-host "name: "       $job.name
        #write-host "id:"          $job.id
        #write-host "link: "       $job._links.jobsessions.href
        #write-host "lastRun: "    $job.lastRun
        #write-host "lastStatus: " $job.lastStatus
    }
    if($debug){ write-host "END - getOrgJobsDetails" -ForegroundColor Cyan }

    
}

function getOrgJobSessionDetails(){
    Param(
        [Parameter(Mandatory = $true)] $link,
        [Parameter(Mandatory = $false)] [string] $id
    )
    if($debug){write-host "START - getOrgJobSessionDetails" -ForegroundColor Cyan}
    if($debug){
        write-host "*** Job Detials" $link
        write-host "jobID:" $id
    }
    
    
    $url = $link
    
    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }

    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    
    if($debug){Write-Host ConvertFrom-Json($jsonResult.Content) -ForegroundColor yellow}

    Try {
        $sessions = (ConvertFrom-Json($jsonResult.Content)).results
    } Catch {
        Write-Error "Error in result getOrgJobSessionDetails"
        Exit 1
    }  

    # Skip session currently active or user aborted, get last known run status
    if ($sessions[0].status.ToLower() -in @('running', 'queued', 'stopped')) {
        $session = $sessions[1]
    } else {
        $session = $sessions[0]
    } 

    # Log Items
    $url = '/v6/JobSessions/' + $session.id + '/LogItems?limit=1000000'
    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing
    if($debug){
        write-host "JOB:" $job -ForegroundColor Blue
    }

    Try {
        $logItems = (ConvertFrom-Json($jsonResult.Content)).results
    } Catch {
        Write-Error "Error in logitems result"
    Exit 1
    }    
        # Log items to object
        ForEach ($logItem in $logItems) {
            $sCnt = 0;$wCnt = 0;$fCnt = 0
            Switch -wildcard ($logItem.title.ToLower()) {
                   '*success*' {$sCnt++}
                   '*warning*' {$wCnt++}
                   '*failed*' {$fCnt++}
            }
        }

        Switch -wildcard ($session.status.ToLower()) {
                   '*success*' {$jobStatus = 0}
                   '*warning*' {$jobStatus = 1}
                   '*failed*' {$jobStatus = 2}
                   default {$jobStatus = 3}
        }

        # Thank you Veeam for fixing this!
        $transferred = $session.statistics.transferredDataBytes

        $myObj = "" | Select Jobname, Status, Start, End, Transferred, Success, Warning, Failed, LastRun
			        $myObj.Jobname = $job.name
                    $myObj.Status = $jobStatus
                    $myObj.Start = Get-Date($session.creationTime)
                    $myObj.End = Get-Date($session.endTime)
                    $myObj.Transferred = $transferred
                    $myObj.Success = $sCnt
                    $myObj.Warning = $wCnt
                    $myObj.Failed = $fCnt
                    $myObj.LastRun = $job.lastRun

        $vboJobs += $myObj

        if($debug){write-host $vboJobs -ForegroundColor green}
        if($debug){write-host "END - getOrgJobSessionDetails" -ForegroundColor Cyan}
        return $vboJobs
}

function getOrgRepoLinks($link){
    if($debug){write-host "START - getOrgRepoLinks" -ForegroundColor Cyan}
    $url = $link

    $headers = @{
        "Content-Type"= "multipart/form-data";
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

    if($debug){write-host "END - getOrgRepoLinks" -ForegroundColor Cyan}
    return $orgRepoLinks
}

function getOrgRepoDetails($orgRepoLink){
    if($debug){write-host "START - getOrgRepoDetails" -ForegroundColor Cyan}
    #write-host "*** ORG REPO LINK" $orgRepoLink -ForegroundColor Green
    $url = $orgRepoLink

    $headers = @{ "Content-Type"= "multipart/form-data"; "Authorization" = "Bearer $accessToken"; }
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

$orgLinks = getAllOrgLinks($orgName)

$orgJobsDetails = getOrgJobsDetails($orgLinks.jobs)
if($debug){
    write-host "*** JOBS ***" -ForegroundColor Green -NoNewline
    $orgJobsDetails | ft
}


$orgRepoLinks = getOrgRepoLinks($orgLinks.usedRepos)
$orgRepoDetails = @()
foreach($orgRepoLink in $orgRepoLinks){
    $orgRepoDetails += getOrgRepoDetails($orgRepoLink)
}
if($debug){
    write-host "*** REPOS ****" -ForegroundColor Green -NoNewline
    $orgRepoDetails | ft
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

   $channel = "Job: " + $job.Jobname + " | Success"
    $value = $job.Success
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>Count</unit>"
                "<VolumeSize>One</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"

    $channel = "Job: " + $job.Jobname + " | Warning"
    $value = $job.Warning
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>Count</unit>"
                "<VolumeSize>One</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "<LimitMaxWarning>10</LimitMaxWarning>"
                "<LimitMaxError>20</LimitMaxError>"
                "<LimitMode>1</LimitMode>"
                "</result>"

    $channel = "Job: " + $job.Jobname + " | Failed"
    $value = $job.Failed
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>Count</unit>"
                "<VolumeSize>One</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "<LimitMaxWarning>1</LimitMaxWarning>"
                "<LimitMaxError>2</LimitMaxError>"
                "<LimitMode>1</LimitMode>"
                "</result>"
}
#endregion

#region: Repositories to PRTG results
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
#endregion
Write-Host "<text>LastRun:" $job.LastRun"</text>"
Write-Host "</prtg>"