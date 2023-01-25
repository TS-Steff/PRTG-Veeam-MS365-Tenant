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
    - In parameters set: -username "%windowsdomain\%windowsuser" -password "%windowspassword" -apiUrl "https://<url-to-vbo-api>:443" -orgName "tenant.onmicrosoft.com" -ignoreDefRepo $false -ignoreSSL $false
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

 #>



param (
    [string]$apiUrl = $(throw "<prtg><error>1</error><text>-apiUrl is missing in parameters</text></prtg>"),
    [string]$username = $(throw "<prtg><error>1</error><text>-username is missing in parameters</text></prtg>"),
    [string]$password = $(throw "<prtg><error>1</error><text>-password is missing in parameters</text></prtg>"),
    [string]$orgName = $(throw "<prtg><error>1</error><text>-orgName is missing in parameters</text></prtg>"),
    [string]$ignoreDefRepo = $(throw "<prtg><error>1</error><text>-ignoreDefRepo is missing in parameters</text></prtg>"),
    [string]$ignoreSSL = $(throw "<prtg><error>1</error><text>-ignoreSSL is missing in parameters</text></prtg>")
)

cls 

if($ignoreSSL -eq $true){
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
$vboRepositories = @()
$vboProxies = @()

#region: Authenticate
$url = '/v6/Token'
$body = @{
    "username" = $username;
    "password" = $password;
    "grant_type" = "password";
}
$headers = @{
    "Content-Type"= "multipart/form-data"
}

Try {
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Body $body -Headers $headers -Method Post -UseBasicParsing
} Catch {
   Write-Error "Error invoking web request"
}

Try {
    $authResult = ConvertFrom-Json($jsonResult.Content)
    $accessToken = $authResult.access_token
} Catch {
    Write-Error "Error authentication result"
}
#endregion


function getOrgaForJob($url){
    <#
        function to get job organization for job _links.organization
    #>
    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

    Try {
        $orgs = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in organization result"
        Exit 1
    }

    if($jsonResult.Count -ne 1){
        Write-Error "More then one organization in result"
        Exit 1
    }

    $organizations = $jsonResult | ConvertFrom-Json
    return $organizations.name
}


function getOrgaRepos($link){
    $url = $link + '/UsedRepositories'
    $headers = @{
        "Content-Type"= "multipart/form-data";
        "Authorization" = "Bearer $accessToken";
    }
    $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

    Try {
        $repos = ConvertFrom-Json($jsonResult.Content)
    } Catch {
        Write-Error "Error in jobs result"
        Exit 1
    }

    $repos = $jsonResult | ConvertFrom-Json
    $tenantRepos = @()
    
    ForEach ($result in $repos.results){
        $url = $result._links.backupRepository.href
        $headers = @{
            "Content-Type"= "multipart/form-data";
            "Authorization" = "Bearer $accessToken";
        }
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

        Try {
            $repositories = ConvertFrom-Json($jsonResult.Content)
        } Catch {
            Write-Error "Error in repositories result"
        }

        #write-host $jsonResult -ForegroundColor red
        $repository = $jsonResult | ConvertFrom-Json
        if(($ignoreDefRepo -eq $true) -and ($repository.name -eq 'Default Backup Repository')){
            #write-host "ignore def repo" -ForegroundColor Green
            #write-host $repository.name
        }else{
            #write-host "do not ignore def repo" -ForegroundColor Green
            #write-host $repository.name
            $myObj = "" | Select Name, Capacity, Free
			            $myObj.Name = $repository.name
                        $myObj.Capacity = $repository.capacityBytes
                        $myObj.Free = $repository.freeSpaceBytes
        }

        $tenantRepos += $myObj
    }

    
    return $tenantRepos
}


#region: Get VBO Jobs
$url = '/v6/Jobs?limit=1000000'
$headers = @{
    "Content-Type"= "multipart/form-data";
    "Authorization" = "Bearer $accessToken";
}
$jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

Try {
    $jobs = ConvertFrom-Json($jsonResult.Content)
} Catch {
    Write-Error "Error in jobs result"
    Exit 1
}

#endregion


#region: Loop jobs and process session results
ForEach ($job in $jobs) {
    # Sessions
    $jobOrgLink = $job._links.organization.href
    $jobOrgName = getOrgaForJob($jobOrgLink)

    
    if($jobOrgName -eq $orgName){
        #write-host "all OK" -ForegroundColor Green

        $url = '/v6/Jobs/' + $job.id + '/JobSessions'
        $headers = @{
            "Content-Type"= "multipart/form-data";
            "Authorization" = "Bearer $accessToken";
        }
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

    
        Try {
            $sessions = (ConvertFrom-Json($jsonResult.Content)).results
        } Catch {
            Write-Error "Error in jobsession result"
	    Exit 1
        }

        # Skip session currently active or user aborted, get last known run status
        if ($sessions[0].status.ToLower() -in @('running', 'queued', 'stopped')) {
            $session = $sessions[1]
        } else {
            $session = $sessions[0]
        }

        # Log items
        $url = '/v6/JobSessions/' + $session.id + '/LogItems?limit=1000000'
        $headers = @{
            "Content-Type"= "multipart/form-data";
            "Authorization" = "Bearer $accessToken";
        }
        $jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

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

        $myObj = "" | Select Jobname, Status, Start, End, Transferred, Success, Warning, Failed
			        $myObj.Jobname = $job.name
                    $myObj.Status = $jobStatus
                    $myObj.Start = Get-Date($session.creationTime)
                    $myObj.End = Get-Date($session.endTime)
                    $myObj.Transferred = $transferred
                    $myObj.Success = $sCnt
                    $myObj.Warning = $wCnt
                    $myObj.Failed = $fCnt

        $vboJobs += $myObj
    }else{
        #skip this job
        #write-host "not OK" -ForegroundColor Red
    }
}


#region: VBO Repositories
$vboRepositories = getOrgaRepos($jobOrgLink)
#endregion




<#
#region: VBO Proxies
$url = '/v6/Proxies'
$headers = @{
    "Content-Type"= "multipart/form-data";
    "Authorization" = "Bearer $accessToken";
}
$jsonResult = Invoke-WebRequest -Uri $apiUrl$url -Headers $headers -Method Get -UseBasicParsing

Try {
    $proxies = ConvertFrom-Json($jsonResult.Content)
} Catch {
    Write-Error "Error in proxies result"
    Exit 1
}

ForEach ($proxy in $proxies) {
    $myObj = "" | Select Name, Status
			    $myObj.Name = $proxy.hostName
                $myObj.Status = $proxy.status
    
    $vboProxies += $myObj
}
#endregion
#>

#region: Jobs to PRTG results
Write-Host "<prtg>"
ForEach ($job in $vboJobs) {
    $channel = "Job - " + $job.Jobname + " - Status"
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
    
    $channel = "Job - " + $job.Jobname + " - Runtime"
    $value = [math]::Round(($job.end - $job.start).TotalSeconds)
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>TimeSeconds</unit>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"

    $channel = "Job - " + $job.Jobname + " - Transferred"
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

    $channel = "Job - " + $job.Jobname + " - Success"
    $value = $job.Success
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>Count</unit>"
                "<VolumeSize>One</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"

    $channel = "Job - " + $job.Jobname + " - Warning"
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

    $channel = "Job - " + $job.Jobname + " - Failed"
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


#region: VBO Reposities to PRTG results
ForEach ($repository in $vboRepositories) {
    $channel = "Repository - " + $repository.Name + " - Capacity"
    $value = $repository.Capacity
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>BytesDisk</unit>"
                "<VolumeSize>GigaByte</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"
    
    $channel = "Repository - " + $repository.Name + " - Free"
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
    
    $channel = "Repository - " + $repository.Name + " - Used"
    $value = $repository.Capacity - $repository.Free
    Write-Host "<result>"
                "<channel>$channel</channel>"
                "<value>$value</value>"
                "<unit>BytesDisk</unit>"
                "<VolumeSize>GigaByte</VolumeSize>"
                "<showChart>1</showChart>"
                "<showTable>1</showTable>"
                "</result>"

    $channel = "Repository - " + $repository.Name + " - Used %"
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
#endregion

<#
#region: VBO Proxies to PRTG results
if($listProxy){
    ForEach ($proxy in $vboProxies) {
        $channel = "Proxy - " + $proxy.Name + " - Status"
        $value = [int]($proxy.Status -like "*Online*")
        Write-Host "<result>"
                   "<channel>$channel</channel>"
                   "<value>$value</value>"
                   "<customunit>Status</customunit>"
                   "<showChart>1</showChart>"
                   "<showTable>1</showTable>"
                   "<LimitMinError>0</LimitMinError>"
                   "<LimitMode>1</LimitMode>"
                   "</result>"
    }
}
#endregion
#>
Write-Host "</prtg>"