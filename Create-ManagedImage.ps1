<#PSScriptInfo
.VERSION 1.0

.GUID f95c92d8-5ccf-479c-bb92-93500f7d93d4

.AUTHOR oaltawil@microsoft.com

.LICENSEURI https://www.gnu.org/licenses/gpl-3.0.en.html

.PROJECTURI https://github.com/oaltawil/Create-ManagedImage
#>

<#
.SYNOPSIS
This script creates a managed image using a virtual machine as the source.

.DESCRIPTION
This script generalizes a virtual machine by running Sysprep.exe and then creates a managed image using the generalized virtual machine as the source.

.NOTES
DISCLAIMER
The sample script is not supported under any Microsoft standard support program or service. The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample script and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample script or documentation, even if Microsoft has been advised of the possibility of such damages.

.PARAMETER SubscriptionId
Azure Subscription Id 

.PARAMETER VmName
Name of the source Virtual Machine used to create the managed image

.PARAMETER ResourceGroupName
Name of the Resource Group that contains the source virtual machine and where the managed image will be created

.PARAMETER VmGeneration
The Hyper-V generation of the virtual machine (V1 or V2)

.PARAMETER ImageName
Name of the managed image that will be created by the script

.PARAMETER Location
Azure region where the managed image will be created

.EXAMPLE
# The following example creates a managed image called "img-basevm-eu-001" using a Generation 2 virtual machine called "vm-build-001" as the source. The image will be created in the "East US" Azure region in the same resource group "rg-build-eu-001" as the source virtual machine.
Create-ManagedImage -SubscriptionId 3b40569e-99c2-4a87-9267-b97db08e7088 -VmName vm-build-001 -ResourceGroupName rg-build-eu-001 -VmGeneration V2 -ImageName img-basevm-eu-001 -Location eastus
#>

Param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $SubscriptionId,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $VmName,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $ResourceGroupName,
    [Parameter(Mandatory = $true, Position = 3)]
    [ValidateSet("V1", "V2")]
    [String] $VmGeneration,
    [Parameter(Mandatory = $true, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $ImageName,
    [Parameter(Mandatory = $true, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $Location
)

# Terminate script execution upon encountering any errors (including non-terminating errors)
$ErrorActionPreference = "Stop"

#
# Install the required Az PowerShell modules
#

# Use TLS 1.2 to connect to the PowerShell Gallery
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# It might be a good idea to update the NuGet package provider and PowerShellGet module. Please refer to https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget?view=powershell-7.2.
<#
    Install-PackageProvider -Name NuGet -Force -Confirm:$false -ErrorAction SilentlyContinue
    Install-PackageProvider -Name PowerShellGet -Force -Confirm:$false -ErrorAction SilentlyContinue
    
    Install-Module -Name PackageManagement -Repository PSGallery -SkipPublisherCheck -AcceptLicense -AllowClobber -Force -Confirm:$false -ErrorAction SilentlyContinue
    Install-Module -Name PowerShellGet -Repository PSGallery -SkipPublisherCheck -AcceptLicense -AllowClobber -Force -Confirm:$false -ErrorAction SilentlyContinue
#>

# Install the latest version of the Az.Compute module (and its dependent Az.Accounts module) and overwrite any older versions
Install-Module -Name Az.Compute -Repository PSGallery -SkipPublisherCheck -AcceptLicense -AllowClobber -Force -Confirm:$false

#
# Generalize the Virtual Machine
#

Write-Output "`nLogin to your Azure subscription using the new browser window. Please note that the window might be hidden in the background.`n"

# Connect to the Azure Subscription, e.g. interactively or passively using a Managed Identity or Service Principal.
# Please refer to https://docs.microsoft.com/en-us/powershell/module/az.accounts/connect-azaccount for all the possible ways of connecting to Azure
Connect-AzAccount

Write-Output "`nSetting subscription $SubscriptionId as the default subscription.`n"

# Select the active Azure Subscription
Set-AzContext -Subscription $SubscriptionId

# Retrieve the Virtual Machine's Resource Id.
$VmResourceId = (Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName).Id

Write-Output "`nStarting virtual machine $vmname.`n"

# Start the virtual machine if it is not running
Start-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName

# Define the path for a new PowerShell script called Generalize-Computer.ps1 in the parent folder of this script file
$SysprepScriptFilePath = Join-Path -Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -ChildPath "Generalize-Computer.ps1"

# Add the Sysprep command to the Generalize-Computer.ps1 PowerShell script
Set-Content -Path $SysprepScriptFilePath -Value "Start-Process -FilePath 'C:\Windows\system32\Sysprep\Sysprep.exe' -ArgumentList '/oobe', '/generalize', '/shutdown' -Wait -NoNewWindow"

Write-Output "`nRunning 'sysprep.exe /oobe /generalize /shutdown' in the guest OS of the virtual machine.`n"

# Run Sysprep inside the Virtual Machine to generalize it and then shut it down. 
Invoke-AzVMRunCommand -Name $VmName -ResourceGroupName $ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptPath $SysprepScriptFilePath

Write-Output "`nDeallocating the virtual machine.`n"

# Deallocate the virtual machine. The previous command should have stopped the virtual machine but left it allocated.
Stop-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName

Write-Output "`nConfiguring the state of the virtual machine to 'Generalized'.`n"

# Set the state of the virtual machine to Generalized
Set-AzVm -Id $VmResourceId -Generalized

#
# Create the Managed Image
#

# Create an Image Configuration using the generalized virtual machine as the source
$ImageConfig = New-AzImageConfig -Location $Location -SourceVirtualMachineId $VmResourceId -HyperVGeneration $VmGeneration

Write-Output "Creating managed image $ImageName in resource group $ResourceGroupName from the generalized virtual machine $VmName.`n"

# Create an Managed Image from the image configuration
New-AzImage -ResourceGroupName $ResourceGroupName -ImageName $ImageName -Image $ImageConfig
