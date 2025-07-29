<#
.SYNOPSIS
Deploys a fault-tolerant, two-node Microsoft Active Directory domain in Azure.

.DESCRIPTION
This advanced function automates the entire process of setting up a highly available Active Directory environment.
It handles the creation of all necessary Azure resources, including a resource group, virtual network with two subnets,
network security group, public IPs, network interfaces, and two virtual machines.

After provisioning the infrastructure, it remotely configures the virtual machines to act as domain controllers,
creating a new AD forest on the first DC and joining the second DC to it for redundancy. Finally, it updates the
VNet's DNS settings to point to the new domain controllers.

The function includes robust error handling, verbose output, and progress indicators for a professional deployment experience.

.PARAMETER ResourceGroupName
The name of the resource group to create for the AD deployment.

.PARAMETER Location
The Azure region where the resources will be deployed (e.g., 'East US').

.PARAMETER DomainName
The fully qualified domain name for the new Active Directory forest (e.g., 'mycorp.local').

.PARAMETER Credential
A PSCredential object containing the username and password for the local VM administrator account.
This password will also be used for the AD Directory Services Restore Mode (DSRM) password.

.PARAMETER VmSize
The size of the virtual machines to be deployed (e.g., 'Standard_D2s_v5').

.EXAMPLE
# Example 1: Deploy a new Active Directory environment with verbose output
$adminCred = Get-Credential -UserName 'azureadmin' -Message 'Enter password for VM admin and AD Safe Mode'
.\Deploy-ADInAzure.ps1 -ResourceGroupName 'ad-prod-rg' -Location 'East US' -DomainName 'prod.corp.com' -Credential $adminCred -Verbose

This command will prompt for credentials and then deploy a full AD environment named 'prod.corp.com' into the 'ad-prod-rg' resource group in the 'East US' region.
It will provide detailed step-by-step output as it runs.

.OUTPUTS
[PSCustomObject]
Outputs a custom object containing the resource group name, the public IP addresses of the two domain controllers, and the administrator username.

.NOTES
Author: Niraj Kumar, linkedIn.com/in/nirajkumar
Date: 2025-07-28
Version: 2.6
- Updated VNet DNS configuration to use the more reliable DhcpOptions property.
#>
param(
    [string]$ResourceGroupName = 'ad-lab-rg',
    [string]$Location = 'East US',
    [string]$DomainName = 'mylab.local',
    [System.Management.Automation.PSCredential]$Credential = $null,
    [string]$VmSize = 'Standard_D2s_v5'
)
function New-AzFaultTolerantAD {
    [CmdletBinding(SupportsShouldProcess = $true, HelpUri = "https://docs.microsoft.com/powershell/module/az.resources/new-azfaulttolerantad",DefaultParameterSetName = "Default")]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, HelpMessage = "The name of the resource group to create.")]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true, HelpMessage = "The Azure region for deployment (e.g., 'East US').")]
        [string]$Location,

        [Parameter(Mandatory = $true, HelpMessage = "The FQDN for the new AD forest (e.g., 'mycorp.local').")]
        [string]$DomainName,

        [Parameter(Mandatory = $true, HelpMessage = "Credentials for the local VM admin and AD Safe Mode.")]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(HelpMessage = "The size of the virtual machines.")]
        [string]$VmSize = "Standard_D2s_v5"
    )

    begin {
        Write-Verbose "Initializing deployment script with the following parameters:"
        Write-Verbose "Resource Group: $ResourceGroupName"
        Write-Verbose "Location: $Location"
        Write-Verbose "Domain Name: $DomainName"
        Write-Verbose "VM Size: $VmSize"
        
        # --- Internal Static Configuration ---
        $vnetName = "ad-vnet-ps"
        $vnetAddressPrefix = "10.0.0.0/16"
        $subnet1Name = "subnet-dc1"
        $subnet1Prefix = "10.0.1.0/24"
        $subnet2Name = "subnet-dc2"
        $subnet2Prefix = "10.0.2.0/24"
        $dc1Name = "ad-dc1"
        $dc2Name = "ad-dc2"
        $dc1PrivateIp = "10.0.1.4"
        $dc2PrivateIp = "10.0.2.4"
        $vmImageSku = "2019-Datacenter"
    }

    process {
        try {
            # --- 1. NETWORK INFRASTRUCTURE ---
            Write-Verbose "--- Step 1: Creating Network Infrastructure ---"
            
            if ($PSCmdlet.ShouldProcess("Resource Group '$ResourceGroupName'", "Create")) {
                Write-Progress -Activity "Creating Azure Resources" -Status "Creating Resource Group..." -PercentComplete 5
                New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop
            }

            if ($PSCmdlet.ShouldProcess("Virtual Network '$vnetName'", "Create")) {
                Write-Progress -Activity "Creating Azure Resources" -Status "Creating Virtual Network and Subnets..." -PercentComplete 10
                $subnet1Config = New-AzVirtualNetworkSubnetConfig -Name $subnet1Name -AddressPrefix $subnet1Prefix
                $subnet2Config = New-AzVirtualNetworkSubnetConfig -Name $subnet2Name -AddressPrefix $subnet2Prefix
                $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $vnetAddressPrefix -Subnet $subnet1Config, $subnet2Config -ErrorAction Stop
            }

            if ($PSCmdlet.ShouldProcess("Network Security Group 'ad-nsg'", "Create")) {
                Write-Progress -Activity "Creating Azure Resources" -Status "Creating Network Security Group and Rules..." -PercentComplete 15
                $nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
                $nsgRuleInternal = New-AzNetworkSecurityRuleConfig -Name "AllowAllInternal" -Protocol * -Direction Inbound -Priority 200 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix "VirtualNetwork" -DestinationPortRange * -Access Allow
                $nsg = New-AzNetworkSecurityGroup -Name "ad-nsg" -ResourceGroupName $ResourceGroupName -Location $location -SecurityRules $nsgRuleRDP, $nsgRuleInternal -ErrorAction Stop
            }

            # --- 2. FIRST DOMAIN CONTROLLER (DC1) ---
            Write-Verbose "`n--- Step 2: Deploying First Domain Controller ($dc1Name) ---"
            if ($PSCmdlet.ShouldProcess($dc1Name, "Deploy Virtual Machine")) {
                Write-Progress -Activity "Creating Azure Resources" -Status "Provisioning resources for $dc1Name..." -PercentComplete 20
                $dc1Pip = New-AzPublicIpAddress -Name "$dc1Name-pip" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku Standard
                $dc1Nic = New-AzNetworkInterface -Name "$dc1Name-nic" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $dc1Pip.Id -PrivateIpAddress $dc1PrivateIp -NetworkSecurityGroupId $nsg.Id

                $dc1Vm = New-AzVMConfig -VMName $dc1Name -VMSize $VmSize -SecurityType "Standard"
                $dc1Vm = Set-AzVMOperatingSystem -VM $dc1Vm -Windows -ComputerName $dc1Name -Credential $Credential
                $dc1Vm = Set-AzVMSourceImage -VM $dc1Vm -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus $vmImageSku -Version "latest"
                $dc1Vm = Add-AzVMNetworkInterface -VM $dc1Vm -Id $dc1Nic.Id

                Write-Progress -Activity "Creating Azure Resources" -Status "Deploying VM for $dc1Name (This may take several minutes)..." -PercentComplete 30
                New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $dc1Vm -ErrorAction Stop
            }

            # --- 3. SECOND DOMAIN CONTROLLER (DC2) ---
            Write-Verbose "`n--- Step 3: Deploying Second Domain Controller ($dc2Name) ---"
             if ($PSCmdlet.ShouldProcess($dc2Name, "Deploy Virtual Machine")) {
                Write-Progress -Activity "Creating Azure Resources" -Status "Provisioning resources for $dc2Name..." -PercentComplete 50
                $dc2Pip = New-AzPublicIpAddress -Name "$dc2Name-pip" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku Standard
                $dc2Nic = New-AzNetworkInterface -Name "$dc2Name-nic" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vnet.Subnets[1].Id -PublicIpAddressId $dc2Pip.Id -PrivateIpAddress $dc2PrivateIp -DnsServer $dc1PrivateIp -NetworkSecurityGroupId $nsg.Id

                $dc2Vm = New-AzVMConfig -VMName $dc2Name -VMSize $VmSize -SecurityType "Standard"
                $dc2Vm = Set-AzVMOperatingSystem -VM $dc2Vm -Windows -ComputerName $dc2Name -Credential $Credential
                $dc2Vm = Set-AzVMSourceImage -VM $dc2Vm -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus $vmImageSku -Version "latest"
                $dc2Vm = Add-AzVMNetworkInterface -VM $dc2Vm -Id $dc2Nic.Id

                Write-Progress -Activity "Creating Azure Resources" -Status "Deploying VM for $dc2Name (This may take several minutes)..." -PercentComplete 60
                New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $dc2Vm -ErrorAction Stop
            }

            # --- 4. CONFIGURE AD ON DOMAIN CONTROLLERS ---
            Write-Verbose "`n--- Step 4: Configuring Active Directory Remotely ---"
            
            if ($PSCmdlet.ShouldProcess($dc1Name, "Configure Active Directory Forest")) {
                Write-Progress -Activity "Configuring Domain Controllers" -Status "Installing AD Forest on $dc1Name..." -PercentComplete 70
                $safeModePassword = $Credential.GetNetworkCredential().Password
                $scriptDc1 = "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools; Install-ADDSForest -DomainName '$($DomainName)' -SafeModeAdministratorPassword (ConvertTo-SecureString '$($safeModePassword)' -AsPlainText -Force) -Force -NoRebootOnCompletion"
                Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $dc1Name -CommandId "RunPowerShellScript" -ScriptString $scriptDc1 -ErrorAction Stop
                
                Write-Verbose "AD Forest installation complete. Rebooting $dc1Name..."
                Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $dc1Name
            }

            Write-Verbose "Waiting for $dc1Name to reboot and stabilize (approx. 2 minutes)..."
            Write-Progress -Activity "Configuring Domain Controllers" -Status "Waiting for $dc1Name to reboot and stabilize..." -PercentComplete 80
            Start-Sleep -Seconds 120

            if ($PSCmdlet.ShouldProcess($dc2Name, "Configure as Additional Domain Controller")) {
                Write-Progress -Activity "Configuring Domain Controllers" -Status "Installing AD role on $dc2Name..." -PercentComplete 90
                $domainAdminPassword = $Credential.GetNetworkCredential().Password
                $localAdminUsername = $Credential.UserName
                $scriptDc2 = @"
                Write-Host 'Waiting for the first domain controller to become available...'
                `$domainReady = `$false
                for (`$i=0; `$i -le 10; `$i++) {
                    try {
                        `$null = Resolve-DnsName -Name '$($DomainName)' -Type A -Server '$($dc1PrivateIp)' -ErrorAction Stop
                        Write-Host 'Domain controller is reachable!'
                        `$domainReady = `$true
                        break
                    }
                    catch {
                        Write-Host 'Domain not yet ready, waiting 30 seconds...'
                        Start-Sleep -Seconds 30
                    }
                }
                if (-not `$domainReady) {
                    Write-Error 'Could not contact the first domain controller. Aborting configuration.'
                    exit 1
                }
                Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
                `$domainCred = New-Object System.Management.Automation.PSCredential('$($DomainName)\$($localAdminUsername)', (ConvertTo-SecureString '$($domainAdminPassword)' -AsPlainText -Force))
                Install-ADDSDomainController -DomainName '$($DomainName)' -Credential `$domainCred -SafeModeAdministratorPassword (ConvertTo-SecureString '$($safeModePassword)' -AsPlainText -Force) -Force -NoRebootOnCompletion
"@
                Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $dc2Name -CommandId "RunPowerShellScript" -ScriptString $scriptDc2 -ErrorAction Stop

                Write-Verbose "AD Role installation complete. Rebooting $dc2Name..."
                Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $dc2Name
            }
            
            # --- 5. FINALIZE VNET DNS SETTINGS ---
            Write-Verbose "`n--- Step 5: Finalizing VNet DNS Settings ---"
            if ($PSCmdlet.ShouldProcess($vnetName, "Set VNet DNS Servers")) {
                 Write-Progress -Activity "Finalizing Configuration" -Status "Setting VNet DNS Servers to point to new DCs..." -PercentComplete 95
                 # FIX: Use the more reliable DhcpOptions property to set DNS servers
                 $vnetToUpdate = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName
                 $vnetToUpdate.DhcpOptions.DnsServers = @($dc1PrivateIp, $dc2PrivateIp)
                 Set-AzVirtualNetwork -VirtualNetwork $vnetToUpdate -ErrorAction Stop
                 Write-Verbose "VNet '$vnetName' DNS servers updated to $dc1PrivateIp, $dc2PrivateIp"
            }

            # --- 6. SCRIPT COMPLETION ---
            Write-Progress -Activity "Deployment Complete" -Status "Finalizing..." -PercentComplete 100
            Write-Verbose "`n--- Step 6: Deployment Finished ---"
            
            $finalDc1Pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$dc1Name-pip"
            $finalDc2Pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$dc2Name-pip"

            $output = [PSCustomObject]@{
                ResourceGroupName = $ResourceGroupName
                DC1_PublicIP      = $finalDc1Pip.IpAddress
                DC2_PublicIP      = $finalDc2Pip.IpAddress
                AdminUsername     = $Credential.UserName
            }
            
            Write-Information "`nDeployment script finished successfully." -InformationAction Continue
            Write-Information "It may take another 5-10 minutes for DC2 to finish its configuration and reboot." -InformationAction Continue
            Write-Information "You can RDP to the VMs using the public IP addresses and the credentials you provided." -InformationAction Continue
            
            return $output

        }
        catch {
            Write-Error "The script failed with the following error: $_"
            # You could add cleanup logic here if desired
            return $null
        }
    }
}


# --- SCRIPT EXECUTION ---
# This section calls the function defined above to start the deployment.
# It sets the required parameters and prints the final summary.

Write-Host "`n--- Starting Active Directory Deployment ---" -ForegroundColor Magenta

# Prompt for credential if not provided
if ($null -eq $Credential) {
    $Credential = Get-Credential -UserName 'azureadmin' -Message 'Enter password for VM admin and AD Safe Mode'
}

# Validate that the user provided credentials before proceeding.
if ($null -eq $Credential) {
    Write-Error "Credential prompt was canceled. Halting script."
}
else {
    # Call the main function with parameters and verbose output
    $deploymentResult = New-AzFaultTolerantAD -ResourceGroupName $ResourceGroupName -Location $Location -DomainName $DomainName -Credential $Credential -VmSize $VmSize -Verbose

    # Print the final output object if the deployment was successful
    if ($null -ne $deploymentResult) {
        Write-Host "`n--- Deployment Summary ---" -ForegroundColor Magenta
        $deploymentResult | Format-List
    } else {
        Write-Error "Deployment did not complete successfully. Please review the error messages above."
    }
}