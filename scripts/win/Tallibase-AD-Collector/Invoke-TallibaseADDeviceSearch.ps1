#Requires -Version 7.0

##TODO get configuration for JSON file and validate


$script:logfile = "$PSScriptRoot\Invoke-TallibaseDeviceSearch.log"
$script:debug = 4


$Settings = Get-Content Settings.json | ConvertFrom-JSON 

if (!$Settings) {
    return "Failed to load JSON settings from Settings.txt, please rename Settings.Example.json to Settings.json "
}

$SiteURL = $Settings.server

#Read encrypted password and then decode and convert to Base65String
$Username,$Password = Get-Content "$PSScriptRoot\Encrypted-Password.txt"
$Password = $Password | ConvertTo-SecureString
$Pair = "$($Username):$([System.Net.NetworkCredential]::new('', $Password).Password)"
$EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$Headers = @{ Authorization = "Basic $EncodedCreds"; 'Content-Type' = "application/json" };


if ($Settings.RESTTest) {

    $TestDevice = @{ 'title' = @{ 'value' = 'NB-JEN' }; 'type' = 'device'; 'field_serialnumber' = @{'value' = '1234'}} | ConvertTo-JSON
    $device = Invoke-RestMethod -Method POST -Uri "$SiteURL/node?_format=json" -Body $TestDevice -Headers $Headers
    $Devices = Invoke-RestMethod -Uri "$SiteURL/views/devices?_format=json" -Headers $headers
    $Devices | Format-Table
}





function Main {

    Write-Log "Loading data from $($Settings.server)"
    $WebDevices = Invoke-RestMethod -Uri "$SiteURL/views/devices?_format=json" -Headers $headers
    $WebDevices = Get-SimplifiedDrupalObject  $WebDevices
    
    $Models = Invoke-RestMethod -Uri "$SiteURL/device_model?_format=json" -Headers $headers
    $Vendors = Invoke-RestMethod -Uri "$SiteURL/vendor?_format=json" -Headers $headers
    
    $Models = Get-SimplifiedDrupalObject $Models
    $Vendors = Get-SimplifiedDrupalObject $Vendors
    



    $Devices = @()

    Write-Log -Level 3 -Text "Searching for ADObjects in $($settings.devices.searchBase)"
    $DeviceADObjects = Get-ADObject -SearchBase $settings.devices.searchBase -Filter $settings.devices.searchFilter | Where-Object ObjectClass -eq 'computer'

    if (!$DeviceADObjects) {
        return "No Objects found"
    }
    Write-Log -Level 5 -Text "Pinging for online devices..."
    $OnlineDevices = Test-ComputerConnections -ComputerNames $DeviceADObjects.Name


    Write-Log -Level 5 -Text "Getting Asset Info..."
    $AssetInfo = @()
    foreach ($Device in $OnlineDevices) {
        $AssetInfo += Get-AssetInfo -DeviceName $Device
    }


    $AssetInfo | Format-Table

    Update-WebDevices -Devices $AssetInfo
    

}

	

function Test-ComputerConnections {
    param (
        [string[]]$ComputerNames
    )

	$Results = @()
    $Results += $ComputerNames | ForEach-Object -Parallel {
        $response = Test-Connection -TargetName $_ -Count 1 -ErrorAction SilentlyContinue
		if ($response.reply.status -eq 'Success') {
            return $_
        } 
    } -ThrottleLimit 100

    return $Results
}

function Write-Log {
param(
  [string]$Text,
  [int]$Level
)
  $Time = get-date -Format "yyyy-MM-dd-hh-mm-ss"
  if ($Level -le $script:debug) { Write-Host "$time[$Level]: $Text" }
  "$time[$Level]: $Text" | Out-File -Append -FilePath $script:logfile -Encoding utf8
}

function Get-SimplifiedDrupalObject {
    param(
        [Parameter(ValueFromPipelineByPropertyName)]$Objects
    )
    process {
        foreach ($Object in $Objects) {
            foreach ($property in $Object.PsObject.Properties) {
                if ($null -ne $property.Value.value) {
                    $property.Value =  $property.Value.value
                }
            }
        }
        return $Objects
    }
}

function Get-AssetInfo {
    param (
        [string]$DeviceName = (Throw "No DeviceName provided for Get-AssetInfo"),
		[bool]$Log = $true
    )
	
    try {
		if ($Log) { Write-Log -Level 5 -Text "Starting CimSession Connecting to $DeviceName..." }
		$DCOM = New-CimSessionOption -Protocol Dcom
		$CimSession = New-CimSession -ComputerName $DeviceName -SessionOption $DCOM -ErrorAction SilentlyContinue
		
		if (! $cimSession) {
			return $null
		}
		# Run Get-CimInstance command to retrieve asset information
		$computersystem = Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $CimSession
		$bios = Get-CimInstance -ClassName Win32_BIOS -CimSession $CimSession
		Remove-CimSession $CimSession
		
		# Create a custom object with relevant information
		$assetInfo = [PSCustomObject]@{
			DeviceName = $DeviceName
			Manufacturer = $computersystem.Manufacturer
			Model = $computersystem.Model
			SerialNumber = $bios.SerialNumber
			BIOSVersion = $bios.SMBIOSBIOSVersion
			SystemType = $computersystem.SystemType
			NumberOfLogicalProcessors = $computersystem.NumberOfLogicalProcessors
			TotalPhysicalMemory = $computersystem.TotalPhysicalMemory
		}
		return $assetInfo
		
        
    } catch {
        if ($Log) { Write-Log -Level 3 -Text  "Error executing PowerShell command: $_" }
        return $null
    }
}
#So we can call in a parallel loop later https://tighetec.co.uk/2022/06/01/passing-functions-to-foreach-parallel-loop/
#$getAssetInfoFunction = ${function:Get-AssetInfo}.ToString()

Main