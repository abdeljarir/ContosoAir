<#
    Microsoft.TeamFoundation.DistributedTask.Task.Deployment.RemoteDeployment.psm1
#>

function Invoke-RemoteDeployment
{    
    [CmdletBinding()]
    Param
    (
        [parameter(Mandatory=$true)]
        [string]$environmentName,
        [string]$adminUserName,
        [string]$adminPassword,
        [string]$protocol,
        [string]$testCertificate,
        [Parameter(ParameterSetName='TagsPath')]
        [Parameter(ParameterSetName='TagsBlock')]
        [string]$tags,
        [Parameter(ParameterSetName='MachinesPath')]
        [Parameter(ParameterSetName='MachinesBlock')]
        [string]$machineNames,
        [Parameter(Mandatory=$true, ParameterSetName='TagsPath')]
        [Parameter(Mandatory=$true, ParameterSetName='MachinesPath')]
        [string]$scriptPath,
        [Parameter(Mandatory=$true, ParameterSetName='TagsBlock')]
        [Parameter(Mandatory=$true, ParameterSetName='MachinesBlock')]
        [string]$scriptBlockContent,
        [string]$scriptArguments,
        [Parameter(ParameterSetName='TagsPath')]
        [Parameter(ParameterSetName='MachinesPath')]
        [string]$initializationScriptPath,
        [string]$runPowershellInParallel,
        [Parameter(ParameterSetName='TagsPath')]
        [Parameter(ParameterSetName='MachinesPath')]
        [string]$sessionVariables
    )

    Write-Verbose "Entering Remote-Deployment block"
        
    $machineFilter = $machineNames

    # Getting resource tag key name for corresponding tag
    $resourceFQDNKeyName = Get-ResourceFQDNTagKey
    $resourceWinRMHttpPortKeyName = Get-ResourceHttpTagKey
    $resourceWinRMHttpsPortKeyName = Get-ResourceHttpsTagKey

    # Constants #
    $useHttpProtocolOption = '-UseHttp'
    $useHttpsProtocolOption = ''

    $doSkipCACheckOption = '-SkipCACheck'
    $doNotSkipCACheckOption = ''
    $ErrorActionPreference = 'Stop'
    $deploymentOperation = 'Deployment'

    $envOperationStatus = "Passed"

    # enabling detailed logging only when system.debug is true
    $enableDetailedLoggingString = $env:system_debug
    if ($enableDetailedLoggingString -ne "true")
    {
        $enableDetailedLoggingString = "false"
    }

    function Get-ResourceWinRmConfig
    {
        param
        (
            [string]$resourceName,
            [int]$resourceId
        )

        $resourceProperties = @{}

        $winrmPortToUse = ''
        $protocolToUse = ''


        if($protocol -eq "HTTPS")
        {
            $protocolToUse = $useHttpsProtocolOption
        
            Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"
            $winrmPortToUse = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpsPortKeyName -ResourceId $resourceId
            Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId (Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"
        
            if([string]::IsNullOrWhiteSpace($winrmPortToUse))
            {
                throw(Get-LocalizedString -Key "{0} port was not provided for resource '{1}'" -ArgumentList "WinRM HTTPS", $resourceName)
            }
        }
        elseif($protocol -eq "HTTP")
        {
            $protocolToUse = $useHttpProtocolOption
            
            Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"
            $winrmPortToUse = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpPortKeyName -ResourceId $resourceId
            Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"
        
            if([string]::IsNullOrWhiteSpace($winrmPortToUse))
            {
                throw(Get-LocalizedString -Key "{0} port was not provided for resource '{1}'" -ArgumentList "WinRM HTTP", $resourceName)
            }
        }

        elseif($environment.Provider -ne $null)      #  For standerd environment provider will be null
        {
            Write-Verbose "`t Environment is not standerd environment. Https port has higher precedence"

            Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"
            $winrmHttpsPort = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpsPortKeyName -ResourceId $resourceId
            Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId (Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"

            if ([string]::IsNullOrEmpty($winrmHttpsPort))
            {
                Write-Verbose "`t Resource: $resourceName does not have any winrm https port defined, checking for winrm http port"
                    
                   Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"
                   $winrmHttpPort = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpPortKeyName -ResourceId $resourceId 
                   Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"

                if ([string]::IsNullOrEmpty($winrmHttpPort))
                {
                    throw(Get-LocalizedString -Key "Resource: '{0}' does not have WinRM service configured. Configure WinRM service on the Azure VM Resources. Refer for more details '{1}'" -ArgumentList $resourceName, "https://aka.ms/azuresetup" )
                }
                else
                {
                    # if resource has winrm http port defined
                    $winrmPortToUse = $winrmHttpPort
                    $protocolToUse = $useHttpProtocolOption
                }
            }
            else
            {
                # if resource has winrm https port opened
                $winrmPortToUse = $winrmHttpsPort
                $protocolToUse = $useHttpsProtocolOption
            }
        }
        else
        {
            Write-Verbose "`t Environment is standerd environment. Http port has higher precedence"

            Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"
            $winrmHttpPort = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpPortKeyName -ResourceId $resourceId
            Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpPortKeyName"

            if ([string]::IsNullOrEmpty($winrmHttpPort))
            {
                Write-Verbose "`t Resource: $resourceName does not have any winrm http port defined, checking for winrm https port"

                   Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"
                   $winrmHttpsPort = Get-EnvironmentProperty -Environment $environment -Key $resourceWinRMHttpsPortKeyName -ResourceId $resourceId
                   Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with resource id: $resourceId(Name : $resourceName) and key: $resourceWinRMHttpsPortKeyName"

                if ([string]::IsNullOrEmpty($winrmHttpsPort))
                {
                    throw(Get-LocalizedString -Key "Resource: '{0}' does not have WinRM service configured. Configure WinRM service on the Azure VM Resources. Refer for more details '{1}'" -ArgumentList $resourceName, "https://aka.ms/azuresetup" )
                }
                else
                {
                    # if resource has winrm https port defined
                    $winrmPortToUse = $winrmHttpsPort
                    $protocolToUse = $useHttpsProtocolOption
                }
            }
            else
            {
                # if resource has winrm http port opened
                $winrmPortToUse = $winrmHttpPort
                $protocolToUse = $useHttpProtocolOption
            }
        }

        $resourceProperties.protocolOption = $protocolToUse
        $resourceProperties.winrmPort = $winrmPortToUse

        return $resourceProperties;
    }

    function Get-SkipCACheckOption
    {
        [CmdletBinding()]
        Param
        (
            [string]$environmentName
        )

        $skipCACheckOption = $doNotSkipCACheckOption
        $skipCACheckKeyName = Get-SkipCACheckTagKey

        # get skipCACheck option from environment
        Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with key: $skipCACheckKeyName"
        $skipCACheckBool = Get-EnvironmentProperty -Environment $environment -Key $skipCACheckKeyName 
        Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $($environment.Name) with key: $skipCACheckKeyName"

        if ($skipCACheckBool -eq "true")
        {
            $skipCACheckOption = $doSkipCACheckOption
        }

        return $skipCACheckOption
    }

    function Get-ResourceConnectionDetails
    {
        param([object]$resource)

        $resourceProperties = @{}
        $resourceName = $resource.Name
        $resourceId = $resource.Id

        Write-Verbose "Starting Get-EnvironmentProperty cmdlet call on environment name: $environmentName with resource id: $resourceId(Name : $resourceName) and key: $resourceFQDNKeyName"
        $fqdn = Get-EnvironmentProperty -Environment $environment -Key $resourceFQDNKeyName -ResourceId $resourceId 
        Write-Verbose "Completed Get-EnvironmentProperty cmdlet call on environment name: $environmentName with resource id: $resourceId(Name : $resourceName) and key: $resourceFQDNKeyName"

        $winrmconfig = Get-ResourceWinRmConfig -resourceName $resourceName -resourceId $resourceId
        $resourceProperties.fqdn = $fqdn
        $resourceProperties.winrmPort = $winrmconfig.winrmPort
        $resourceProperties.protocolOption = $winrmconfig.protocolOption
        $resourceProperties.credential = Get-ResourceCredentials -resource $resource	
        $resourceProperties.displayName = $fqdn + ":" + $winrmconfig.winrmPort

        return $resourceProperties
    }

    function Get-ResourcesProperties
    {
        param([object]$resources)

        $skipCACheckOption = Get-SkipCACheckOption -environmentName $environmentName
        [hashtable]$resourcesPropertyBag = @{}

        foreach ($resource in $resources)
        {
            $resourceName = $resource.Name
            $resourceId = $resource.Id
            Write-Verbose "Get Resource properties for $resourceName (ResourceId = $resourceId)"
            $resourceProperties = Get-ResourceConnectionDetails -resource $resource
            $resourceProperties.skipCACheckOption = $skipCACheckOption
            $resourcesPropertyBag.add($resourceId, $resourceProperties)
        }

        return $resourcesPropertyBag
    }

    $RunPowershellJobInitializationScript = {
        function Load-AgentAssemblies
        {
            
            if(Test-Path "$env:AGENT_HOMEDIRECTORY\Agent\Worker")
            {
                Get-ChildItem $env:AGENT_HOMEDIRECTORY\Agent\Worker\*.dll | % {
                [void][reflection.assembly]::LoadFrom( $_.FullName )
                Write-Verbose "Loading .NET assembly:`t$($_.name)"
                }

                Get-ChildItem $env:AGENT_HOMEDIRECTORY\Agent\Worker\Modules\Microsoft.TeamFoundation.DistributedTask.Task.DevTestLabs\*.dll | % {
                [void][reflection.assembly]::LoadFrom( $_.FullName )
                Write-Verbose "Loading .NET assembly:`t$($_.name)"
                }
            }
            else
            {
                if(Test-Path "$env:AGENT_HOMEDIRECTORY\externals\vstshost")
                {
                    [void][reflection.assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\externals\vstshost\Microsoft.TeamFoundation.DistributedTask.Task.LegacySDK.dll")
                }
            }
        }

        function Get-EnableDetailedLoggingOption
        {
            param ([string]$enableDetailedLogging)

            if ($enableDetailedLogging -eq "true")
            {
                return '-EnableDetailedLogging'
            }

            return '';
        }
    }

    $RunPowershellJobForScriptPath = {
        param (
        [string]$fqdn, 
        [string]$scriptPath,
        [string]$port,
        [string]$scriptArguments,
        [string]$initializationScriptPath,
        [object]$credential,
        [string]$httpProtocolOption,
        [string]$skipCACheckOption,
        [string]$enableDetailedLogging,
        [object]$sessionVariables
        )

        Write-Verbose "fqdn = $fqdn"
        Write-Verbose "scriptPath = $scriptPath"
        Write-Verbose "port = $port"
        Write-Verbose "scriptArguments = $scriptArguments"
        Write-Verbose "initializationScriptPath = $initializationScriptPath"
        Write-Verbose "protocolOption = $httpProtocolOption"
        Write-Verbose "skipCACheckOption = $skipCACheckOption"
        Write-Verbose "enableDetailedLogging = $enableDetailedLogging"

        Load-AgentAssemblies

        $enableDetailedLoggingOption = Get-EnableDetailedLoggingOption $enableDetailedLogging
    
        Write-Verbose "Initiating deployment on $fqdn"
        [String]$psOnRemoteScriptBlockString = "Invoke-PsOnRemote -MachineDnsName $fqdn -ScriptPath `$scriptPath -WinRMPort $port -Credential `$credential -ScriptArguments `$scriptArguments -InitializationScriptPath `$initializationScriptPath -SessionVariables `$sessionVariables $skipCACheckOption $httpProtocolOption $enableDetailedLoggingOption"
        [scriptblock]$psOnRemoteScriptBlock = [scriptblock]::Create($psOnRemoteScriptBlockString)
        $deploymentResponse = Invoke-Command -ScriptBlock $psOnRemoteScriptBlock
    
        Write-Output $deploymentResponse
    }

    $RunPowershellJobForScriptBlock = {
    param (
        [string]$fqdn, 
        [string]$scriptBlockContent,
        [string]$port,
        [string]$scriptArguments,    
        [object]$credential,
        [string]$httpProtocolOption,
        [string]$skipCACheckOption,
        [string]$enableDetailedLogging    
        )

        Write-Verbose "fqdn = $fqdn"
        Write-Verbose "port = $port"
        Write-Verbose "scriptArguments = $scriptArguments"
        Write-Verbose "protocolOption = $httpProtocolOption"
        Write-Verbose "skipCACheckOption = $skipCACheckOption"
        Write-Verbose "enableDetailedLogging = $enableDetailedLogging"

        Load-AgentAssemblies

        $enableDetailedLoggingOption = Get-EnableDetailedLoggingOption $enableDetailedLogging
   
        Write-Verbose "Initiating deployment on $fqdn"
        [String]$psOnRemoteScriptBlockString = "Invoke-PsOnRemote -MachineDnsName $fqdn -ScriptBlockContent `$scriptBlockContent -WinRMPort $port -Credential `$credential -ScriptArguments `$scriptArguments $skipCACheckOption $httpProtocolOption $enableDetailedLoggingOption"
        [scriptblock]$psOnRemoteScriptBlock = [scriptblock]::Create($psOnRemoteScriptBlockString)
        $deploymentResponse = Invoke-Command -ScriptBlock $psOnRemoteScriptBlock
    
        Write-Output $deploymentResponse
    }

    $connection = Get-VssConnection -TaskContext $distributedTaskContext

    # This is temporary fix for filtering 
    if([string]::IsNullOrEmpty($machineNames))
    {
       $machineNames  = $tags
    }

    Write-Verbose "Starting Register-Environment cmdlet call for environment : $environmentName with filter $machineNames"
    $environment = Register-Environment -EnvironmentName $environmentName -EnvironmentSpecification $environmentName -UserName $adminUserName -Password $adminPassword -WinRmProtocol $protocol -TestCertificate ($testCertificate -eq "true")  -Connection $connection -TaskContext $distributedTaskContext -ResourceFilter $machineNames
	Write-Verbose "Completed Register-Environment cmdlet call for environment : $environmentName"
	
    Write-Verbose "Starting Get-EnvironmentResources cmdlet call on environment name: $environmentName"
    $resources = Get-EnvironmentResources -Environment $environment

    if ($resources.Count -eq 0)
    {
      throw (Get-LocalizedString -Key "No machine exists under environment: '{0}' for deployment" -ArgumentList $environmentName)
    }

    $resourcesPropertyBag = Get-ResourcesProperties -resources $resources

    $parsedSessionVariables = Get-ParsedSessionVariables -inputSessionVariables $sessionVariables

    if($runPowershellInParallel -eq "false" -or  ( $resources.Count -eq 1 ) )
    {
        foreach($resource in $resources)
        {
            $resourceProperties = $resourcesPropertyBag.Item($resource.Id)
            $machine = $resourceProperties.fqdn
            $displayName = $resourceProperties.displayName
            Write-Host (Get-LocalizedString -Key "Deployment started for machine: '{0}'" -ArgumentList $displayName)

            . $RunPowershellJobInitializationScript
            if($PsCmdlet.ParameterSetName.EndsWith("Path"))
            {
                $deploymentResponse = Invoke-Command -ScriptBlock $RunPowershellJobForScriptPath -ArgumentList $machine, $scriptPath, $resourceProperties.winrmPort, $scriptArguments, $initializationScriptPath, $resourceProperties.credential, $resourceProperties.protocolOption, $resourceProperties.skipCACheckOption, $enableDetailedLoggingString, $parsedSessionVariables
            }
            else
            {
                $deploymentResponse = Invoke-Command -ScriptBlock $RunPowershellJobForScriptBlock -ArgumentList $machine, $scriptBlockContent, $resourceProperties.winrmPort, $scriptArguments, $resourceProperties.credential, $resourceProperties.protocolOption, $resourceProperties.skipCACheckOption, $enableDetailedLoggingString 
            }

            Write-ResponseLogs -operationName $deploymentOperation -fqdn $displayName -deploymentResponse $deploymentResponse
            $status = $deploymentResponse.Status
				
			if ($status -ne "Passed")
			{             
			    if($deploymentResponse.Error -ne $null)
                {
					Write-Verbose (Get-LocalizedString -Key "Deployment failed on machine '{0}' with following message : '{1}'" -ArgumentList $displayName, $deploymentResponse.Error.ToString())
                    $errorMessage = $deploymentResponse.Error.Message
					return $errorMessage					
                }
				else
				{
					$errorMessage = (Get-LocalizedString -Key 'Deployment on one or more machines failed.')
					return $errorMessage
				}
           }
		   
		    Write-Host (Get-LocalizedString -Key "Deployment status for machine '{0}' : '{1}'" -ArgumentList $displayName, $status)
        }
    }
    else
    {
        [hashtable]$Jobs = @{} 

        foreach($resource in $resources)
        {
            $resourceProperties = $resourcesPropertyBag.Item($resource.Id)
            $machine = $resourceProperties.fqdn
            $displayName = $resourceProperties.displayName
            Write-Host (Get-LocalizedString -Key "Deployment started for machine: '{0}'" -ArgumentList $displayName)

            if($PsCmdlet.ParameterSetName.EndsWith("Path"))
            {
                $job = Start-Job -InitializationScript $RunPowershellJobInitializationScript -ScriptBlock $RunPowershellJobForScriptPath -ArgumentList $machine, $scriptPath, $resourceProperties.winrmPort, $scriptArguments, $initializationScriptPath, $resourceProperties.credential, $resourceProperties.protocolOption, $resourceProperties.skipCACheckOption, $enableDetailedLoggingString, $parsedSessionVariables
            }
            else
            {
                $job = Start-Job -InitializationScript $RunPowershellJobInitializationScript -ScriptBlock $RunPowershellJobForScriptBlock -ArgumentList $machine, $scriptBlockContent, $resourceProperties.winrmPort, $scriptArguments, $resourceProperties.credential, $resourceProperties.protocolOption, $resourceProperties.skipCACheckOption, $enableDetailedLoggingString                 
            }
            
            $Jobs.Add($job.Id, $resourceProperties)
        }
        While (Get-Job)
        {
            Start-Sleep 10 
            foreach($job in Get-Job)
            {
                 if($job.State -ne "Running")
                {
                    $output = Receive-Job -Id $job.Id
                    Remove-Job $Job
                    $status = $output.Status
                    $displayName = $Jobs.Item($job.Id).displayName
                    $resOperationId = $Jobs.Item($job.Id).resOperationId

                    Write-ResponseLogs -operationName $deploymentOperation -fqdn $displayName -deploymentResponse $output
                    Write-Host (Get-LocalizedString -Key "Deployment status for machine '{0}' : '{1}'" -ArgumentList $displayName, $status)
                    if($status -ne "Passed")
                    {
                        $envOperationStatus = "Failed"
                        $errorMessage = ""
                        if($output.Error -ne $null)
                        {
                            $errorMessage = $output.Error.Message
                        }
                        Write-Host (Get-LocalizedString -Key "Deployment failed on machine '{0}' with following message : '{1}'" -ArgumentList $displayName, $errorMessage)
                    }
                }
            }
        }
    }

    if($envOperationStatus -ne "Passed")
    {
         $errorMessage = (Get-LocalizedString -Key 'Deployment on one or more machines failed.')
         return $errorMessage
    }

}
# SIG # Begin signature block
# MIInqgYJKoZIhvcNAQcCoIInmzCCJ5cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDvZ3uXMKhqjxqP
# pD9BYnyXygrXbhnvSUzwcypxeAztfKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZfzCCGXsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg+93ZpIXY
# Snfs+4KcVbt7ajHRyLO4HxVrM+T768vrJ/QwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBtjvROem+mHCQCzUmjhAR6XOW6PBMAul75c0/5IywJ
# VVJLzjbrrof/rtmpyhL8sjJwAw1jJKjQdTgft5eNeInell1GbzZW6V/+A8pbM/RE
# sKOy84wetU75njkjw2vbQc2nWuLCNG8DQLnczD347TRQpHlRx2Guug1Pn0fBbJH7
# Rs6GUTCSbelXHM/B/JycAogVJ/jqIvE3foO2b9Dow2mwSdWrQMFFd6dUZPsiBaOY
# qmmtskHSbiN8qie9SSSvIGwg0N5A2gLblUV2ZEVPnKupZlgKcTKtzdz/PTF6IXtb
# a2dzqe9/tqv18vGVJdRwHKGwIUpkoPTJrnZwF5TDsCySoYIXCTCCFwUGCisGAQQB
# gjcDAwExghb1MIIW8QYJKoZIhvcNAQcCoIIW4jCCFt4CAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIKAT+R43a5U7kklxHsH8lbzh0gYcE/i08Gj+3pzx
# /RBWAgZjc5gWvccYEzIwMjIxMjEyMTUzNzU2LjY1MVowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGN0E2LUUyNTEtMTUwQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEVwwggcQMIIE+KADAgECAhMzAAABpQDeCMRAB3FOAAEA
# AAGlMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTExOVoXDTIzMDUxMTE4NTExOVowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGN0E2
# LUUyNTEtMTUwQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALqxhuggaki8wuoOMMd7
# rsEQnmAhtV8iU1Y0itsHq30TdCXJDmvZjaZ8yvOHYFVhTyD1b5JGJtwZjWz1fglC
# qsx5qBxP1Wx1CZnsQ1tiRsRWQc12VkETmkY8x46MgHsGyAmhPPpsgRnklGai7HqQ
# FB31x/Qjkx7rbAlr6PblB4tOmaR1nKxl4VIgstDwfneKaoEEw4iN/xTdztZjwyGi
# Y5hNp6beetkcizgJFO3/yRHYh0gtk+bREhrmIgbarrrgbz7MsnA7tlKvGcO9iHc6
# +2symrAVy3CzQ4IMNPFcTTx8wTZ+kpv6lFs1eG8xlfsu2NDWKshrMlKH2JpYzWAW
# 1fCOD5irXsE4LOvixZQvbneQE6+iGfIQwabj+fRdouAU2AiE+iaNsIDapdKab8WL
# xz6VPRbEL+M6MFkcsoiuKHHoshCp7JhmZ9iM0yrEx2XebOha/XQ342KsRGs2h02g
# pX6wByyT8eD3MJVIxSRm4MLIilvWcpd9N3rooawbLU6gdk7goKWS69+w2jtouXCE
# Yt6IPfZq8ldi0L/CwYbtv7mbHmIZ9Oc0JEJc6b9gcVDfoPiemMKcz15BLepyx7np
# Q2MiDKIscOqKhXuZI+PZerNOHhi/vsy2/Fj9lB6kJrMYSfV0F2frvBSBXMB7xjv8
# pgqX5QXUe8nTxb4UfJ0cDAvBAgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUX6aPAwCX
# rq6tcO773FkXS2ipGt8wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAlpsLF+UwMKKER2p0WJno4G6GGGnfg3qjDdaH
# c5uvXYtG6KmHrqAf/YqHkmNotSr6ZEEnlGCJYR7W3uJ+5bpvj03wFqGefvQsKIR2
# +q6TrzozvP4NsodWTT5SVp/C6TEDGuLC9mOQKA4tyL40HTW7txb0cAdfgnyHFoI/
# BsZo/FaXezQ8hO4xUjhDpyNNeJ6WYvX5NC+Hv9nmTyzjqyEg/L2cXAOmxEWvfPAQ
# 1lfxvrtUwG75jGeUaewkhwtzanCnP3l6YjwJFKB6n7/TXtrfik1xY1kgev1JwQ5a
# UdPxwSdDmGE4XTN2s6pPOi8IO199Of6AEvh41eDxRz+11VUcpuGn7tJUeSTUSHsv
# zQ8ECOj5w77Mv55/F8hWu07egnG8SrWj5+TFxNPCpx/AFNvzz+odTRTZd4LWuomc
# MHUmLFiUGOAdetF6SofHG5EcFn0DTD1apBZzCP8xsGQcZgwVqo7ov23/uIJlMCLA
# yTYZV9ITCP09ciUJbKBVCQNrGEnQ/XLFO9mysyyDRrvHhU5uGPdXz4Jt2/ZN7JQY
# RuVNSuCpNwoK0Jr1s6ciDvHEeLyiczxoIe9GH3SyfbHx6v/phI+iE3DWo1TCK75E
# L6pt6k5i36/kn2uSVXdTH44ZVkh3/ihV3vEws78uGlvsiMcrKBgpo3HdcjDHiHoW
# sUf4GIwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYICzzCC
# AjgCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNv
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGN0E2LUUyNTEtMTUwQTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# s8lw20WzmxDKiN1Lhh7mZWXutKiggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOdBrjEwIhgPMjAyMjEyMTIxNzQy
# MDlaGA8yMDIyMTIxMzE3NDIwOVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA50Gu
# MQIBADAHAgEAAgIjEjAHAgEAAgIRujAKAgUA50L/sQIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBBQUAA4GBAAalusjkOGUJvz1oZ/YVBSV/TEtwN+HqHToGCZWw0LQcsCru
# /kS8ctTZFdSCen0sg1mIy8afwG8dOZy+1Op78tCBrCM6B1dm9heOP0ahfmnfTgiH
# h2fH+W7hT0fMp5R7dHRPT1aF7SYarjMgHS8U788wd4wLGxId2vdMcVNU0vunMYIE
# DTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGl
# AN4IxEAHcU4AAQAAAaUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg9DzWvqt0QYsKSkRItT8ckObG
# /wZmGfP50JFj8fFk8eUwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCC4Cjhx
# fmYEsaCt2AU83Khh+6JHlyk3B70vfMHMlBLcXDCBmDCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABpQDeCMRAB3FOAAEAAAGlMCIEIN3mjSUL
# 71Onn1f/3YT+h4rPu5lsMCA7s+LqpoMaAU/3MA0GCSqGSIb3DQEBCwUABIICAAU9
# xf3TffD3eZGsBtlxzrhoDzTpImGDJikwbwpi571KQBa2nL6uZLyI7gTNyuMKEflo
# dXPsPEtUT0TZDONd+l3D0nxGjx3HvI1gGFIZG0ovKGHDJRXrs386M2Yyn0tCUCBc
# MAL9wTLnrRUYmr9kJzSSrPe0CZXPDchx1bubIi9SSK6HL2LblHDA5SgcS1mpo7di
# 2U/kfhWF9f/23OdybfNXjTd8GiCJWVzZrlLS6z48bGXvznR2scoRsGlKq82SsN5o
# cUpMhY8utLHNVWLdO/ksQi9hcr5YHOzcXuFsUoyTo1+9QgvZbiVlgUJsmCvNEvlV
# HGpGErVTc4KaFxbyZ0whw0gpj4BAxVkcVJ9tm+A7iz9W3hZogM5jPRUdX4ihxVk2
# IyNOGoyIXEQ/IuVGykVWwBDjBKLae4PummcC4+8LEig3QnSvd2xBCsTu91xu2I03
# rsi2R/Y0o+7b10jV2H6gnB4JYv6HtvBElpsEvfyYNOK13J1lGVRP+GfypREAdcvS
# PTVfBM7+NHzCywR+Cd7fertmjZTnPK4uWLMoYSHD6/Wvg34eK4zqF98LvGDEVLVa
# dFG5UXGyVy+FzWzelUjkSn0E+YbwtYBT2BS2fnu6x1x4xZ0B+Ww4+l6gKzR7D1tA
# bzeVIqT1IiJOtkj4dcqzAxkPLVfng7b0k3WyAycc
# SIG # End signature block
