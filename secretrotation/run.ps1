# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# Connect to Azure with the credentials 
Connect-AzAccount -Identity

# Azure DevOps Variables
$OrganizationName = "<NAME OF AZDO ORG NAME>" 
$ProjectName = "<YOUR PROJECT NAME>"
$PAT = "<AZDO PERSONAL ACCESS TOKEN>"
$Serviceconnectionname = "<NAME OF AZDO SERVICE CONNECTION NAME>"
$AcrUrl = "<URL of ACR>"

# Fetch registered app 
$app = Get-AzADServicePrincipal -SearchString "spnrotator"

# fetch application id
$appId = $app.ApplicationId

# Removes the existing secrets from registered application
Remove-AzADAppCredential -ApplicationId $app.ApplicationId -Force

# Creates a new random secret for the registered application
$charlist = [char]94..[char]126 + [char]65..[char]90 +  [char]47..[char]57
$pwlength = Get-Random -Minimum 32 -Maximum 47 
$pwdList = @()
For ($i = 0; $i -lt $pwlength; $i++) {
   $pwdList += $charList | Get-Random

}

$password = -join $pwdList

#convert string to secure strings.
$secureAppPassword = $Password | ConvertTo-SecureString -AsPlainText -Force

# Lets generate a the time for the spn to be valid for, in this example we will take the current time and add one day to it.
# we only want the spn to be short lived.
$appEndDate = (get-date).AddDays(1) | get-date -Format "yyyy-MM-dd"

# Lets create a new SPN secret which is only valid for 24 hours.
New-AzADAppCredential -ApplicationId $app.ApplicationId  -Password $secureAppPassword -EndDate $appEndDate

function Set-AzureDevopServiceEndPointUpdate {

   Write-Host "Executing the Update Service Connection Script.."

    # Create the header to authenticate to Azure DevOps
    Write-Host "Create the header to authenticate to Azure DevOps"
    $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($PAT)"))

    $Headers = @{
        Authorization = "Basic $token"
    }

    # Get the Project ID
    Write-Host "Construct the API URL to get the project ID.."
    $project = "https://dev.azure.com/" + "$OrganizationName/_apis/projects/$ProjectName ?api-version=6.0"
    Write-Host "Project API URL :: $project"
    try {
        Write-Host "Get the Project [$ProjectName] ID.."
        $response = Invoke-RestMethod -Uri $project -Headers $Headers -Method GET
        $ProjectID = $response.id
        if (!$ProjectID) {
            Write-Host "ProjectID value is null"
            Write-Error "Script step has been aborted." -ErrorAction stop
        } else {
            Write-Host "Project ID :: $ProjectID"
        }
    }
    catch {
        $ErrorMessage = $_ | ConvertFrom-Json
        throw "Could not Get the project [$ProjectName] ID: $($ErrorMessage.message)"
    }

    # Get Endpoint ID Details
    $endpoint = "https://dev.azure.com/" + "$OrganizationName/$ProjectName/_apis/serviceendpoint/endpoints?endpointNames=$Serviceconnectionname&api-version=6.0-preview.4"

    try {
        Write-Host "Get the Service Connection [$Serviceconnectionname] ID.."
        $response = Invoke-RestMethod -Uri $endpoint -Headers $Headers -Method GET
        $endpointId = $response.value.id
        if (!$endpointId) {
            Write-Host "Service Endpoint ID value is null"
            Write-Error "Script step has been aborted." -ErrorAction stop
        } else {
            Write-Host "Service Endpoint ID :: $endpointId"
        }

    }
    catch {
        $ErrorMessage = $_ | ConvertFrom-Json
        throw "Could not Get the service connection [$Serviceconnectionname] ID: $($ErrorMessage.message)"
    }

    # Create a body for the API call
    $url = "https://dev.azure.com/" + "$OrganizationName/_apis/serviceendpoint/endpoints/$endpointId ?api-version=6.1-preview.4"
    $body = @"
{
    "data": {},
    "id": "$endpointId",
    "name": "$Serviceconnectionname",
    "type": "dockerregistry",
    "url": "https://hub.docker.com/",
    "description": null,
    "authorization": {
      "parameters": {
        "username": "$appId",
        "password": "$password",
        "registry": "$AcrUrl"
        },
        "scheme": "UsernamePassword"
    },
    "isShared": false,
    "isReady": true,
    "owner": "Library",
    "serviceEndpointProjectReferences": [
      {
        "name": "$Serviceconnectionname",
        "projectReference": {
          "id": "$ProjectID",
          "name": "$ProjectName"
        }
      }
    ]
  }
"@

    try { 
    Write-Host "Updating the Service Connection [$Serviceconnectionname]"
    $response = Invoke-RestMethod -Uri $url -Headers $Headers -Method PUT -Body $body -ContentType application/json
    Write-Host "Connection Updated"
    $response
    }
    catch {
      Write-Host "An error occurred:"
      Write-Host $_
    }
    
}

Set-AzureDevopServiceEndPointUpdate