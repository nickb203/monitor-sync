# API credentials
$api_clientid = "Enter your client ID here"
$api_clientsecret = "Enter your client secret here"

# Function to authenticate with the API and retrieve the access token
function Get-AccessToken {
    param (
        [string]$ClientId,
        [string]$ClientSecret
    )

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }

    $headers = @{
        "Content-Type" = "application/x-www-form-urlencoded"
        "Accept"       = "application/vnd.api+json"
    }

    $response = Invoke-RestMethod -Method Post -Uri "https://add-your-link-here/oauth2/token/" -Body $body -Headers $headers
    return $response.access_token
}

# Dynamic paramater based function to call the API and perform a variety of actions
function Invoke-API {
    param (
        [string]$AccessToken,
        [string]$Method,
        [string]$Uri,
        [string]$Body = "nil"
    )

    $headers = @{
        "Content-Type"  = "application/x-www-form-urlencoded"
        "Authorization" = "Bearer $AccessToken"
    }
    
    # Check if a body is provided and set the content type accordingly
    if ($Body -ne "nil") {
        $headers["Content-Type"] = "application/json; charset=utf-8"
        $response = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $Body
    }

    # If no body is provided, make a GET request
    else {
        $response = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    }

    return $response
}


# Retrieve monitor information
$Monitors = Get-WmiObject WmiMonitorID -Namespace root\wmi -ComputerName $Env:COMPUTERNAME

# Get the UDN of the user
$endpointUser = (Get-WmiObject Win32_ComputerSystem).UserName
$endpointUser = $endpointUser.Split("\")[1]

# Initialize an array to store the list of monitors
$listOfMonitors = @()

# Loop through each monitor and extract the relevant information
if ($Monitors) {
    foreach ($monitor in $Monitors) {

        # Initialize variables inside the loop
        $Manufacturer = ""
        foreach ($char in $monitor.ManufacturerName) {
            if ($char -ne 0) {
                $Manufacturer += [char]$char
            }
        }

        $Model = ""
        foreach ($char in $monitor.UserFriendlyName) {
            if ($char -ne 0) {
                $Model += [char]$char
            }
        }
        $Model = $Model -replace '^.*DELL\s*', ''

        $Serial = ""
        foreach ($char in $monitor.SerialNumberID) {
            if ($char -ne 0) {
                $Serial += [char]$char
            }
        }

        # Skip laptop screens (assuming their Manufacturer is 'LEN')
        if ($Manufacturer -eq "LEN") {
            continue
        }

        # Add the monitor to the list of monitors
        $listOfMonitors += @{
            Manufacturer = $Manufacturer
            Model        = $Model
            Serial       = $Serial
        }
    }
}

# Authenticate with the API
$access_token = Get-AccessToken -ClientId $api_clientid -ClientSecret $api_clientsecret

# Retrieve the user ID from the API
$userid = Invoke-API -AccessToken $access_token -Method "Get" -Uri "https://add-your-link-here/public-api/people/?username=$endpointUser"

# Convert the ID to a string
$userid = $userid.data.id | Out-String

# Check if the monitor is already in the database and if not, add it
# Compare the serial number of the monitor to the serial numbers of the monitors in the database
for ($i = 0; $i -lt $listOfMonitors.Count; $i++) {

    $uri = "https://add-your-link-here/public-api/assets-lite/?serial=$($listOfMonitors[$i].Serial)&status_behavior=tracked"
    
    # Invoke the API
    $response = Invoke-API -AccessToken $access_token -Method "Get" -Uri $uri
    
    # Check if response contains any data
    if ($response -and $response.data) {
        # API call successful, add result to found list
        $syncBody = @{
            custom_field_id = 27
            asset_id        = $($response.data[0].id)
            value           = (Get-Date).ToString("yyyy-MM-dd")
        }
    
        $syncBody = $syncBody | ConvertTo-Json
        Invoke-API -AccessToken $access_token -Method "Post" -Uri "https://add-your-link-here/public-api/v2/custom-field-value/" -Body $syncBody
    
        # Update last connected user
        $userBody = @{
            custom_field_id = 28
            asset_id        = $($response.data[0].id)
            value           = $endpointUser
        }
        $userBody = $userBody | ConvertTo-Json
        Invoke-API -AccessToken $access_token -Method "Post" -Uri "https://add-your-link-here/public-api/v2/custom-field-value/" -Body $userBody
    }
    else {
        # Create the monitor in the database
        $body = @{
            name         = "Dell Monitor"
            serial       = $listOfMonitors[$i].Serial
            manufacturer = "Dell"
            model        = $listOfMonitors[$i].Model 
            asset_type   = "Monitor"
            location     = "18" # Location Remote
            owner        = $userid 
        }

        $body = $body | ConvertTo-Json
        $response = Invoke-API -AccessToken $access_token -Method "Post" -Uri "https://add-your-link-here/public-api/v2/assets-lite/" -Body $body
        
    }   
    
}
