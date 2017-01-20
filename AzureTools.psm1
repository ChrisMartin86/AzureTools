# script variables

$Script:AzureConnected = $false

$Script:AzureSubscriptionInfo = $null

$Script:AzureLoginInfo = $null

$Script:SubNames = @()

$Script:CurrentSubName = ""

# helper functions. not exported.
function get-SubscriptionParameter
{
    $parameterName = "Subscription"
    $subNames = $Script:SubNames

    # Create the attribute collection
    $attributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]

    # Create the Parameter() block
    $subAttribute = New-Object -TypeName System.Management.Automation.ParameterAttribute       
    $subAttribute.Position = 1
    $subAttribute.Mandatory = $true
    $subAttribute.HelpMessage = "The name of the subscription to connect to"

    # Create the ValidateSetAttribute() block using the subscription names
    $validateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($subNames)


    # Add both attributes to the collection
    $attributeCollection.Add($subAttribute)
    $attributeCollection.Add($validateSetAttribute)

    # Define the parameter
    $subParam = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameter -ArgumentList ($parameterName, [System.String], $attributeCollection)

    # Create the runtime parameter dictionary
    $paramDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

    # Add the parameter to the dictionary with the correct name
    $paramDictionary.Add($parameterName, $subParam)

    return $paramDictionary
}

function set-Prompt
{
    try
    {
        $sb = {$currentDirPath = Get-Item -Path .\ | Select-Object -ExpandProperty FullName; "PS [Azure:\$($Script:CurrentSubName)] $currentDirPath> " }
        
        Set-Item -Path function:prompt -Value $sb
    }
    catch
    {
        # swallow because this isn't really important
    }
}


# functions. exported
function Connect-AzureTools
{
    <#
    .SYNOPSIS
    Run before using any other Azure or AzureTools cmdlets. Use instead of the Login-AzureRmAccount cmdlet.

    .DESCRIPTION
    Wrapper for the Login-AzureRmAccount cmdlet. Connects, then adds some information to the environment for use later. Must be used instead of Login-AzureRmAccount if this module's functions are to be used. Other AzureRm cmdlets are available to use normally.

    .PARAMETER Credential
    The credential to use to connect to Azure

    .PARAMETER ActiveSubscription
    The initial subscription to connect to. If left blank, will connect to the first available subscription.
    #>
    Param(
        [Parameter(
            Mandatory = $false,
            Position = 0)]
        [PSCredential] $Credential = ([PSCredential]::Empty),
        [Parameter(
            Mandatory = $false,
            Position = 1)]
        [string] $ActiveSubscription = ""
        )

    $params = @{ ErrorAction = "Stop"}

    if (([PSCredential]::Empty) -ne $Credential)
    {
        Write-Verbose -Message "Connecting as $($Credential.UserName)"
        $params += @{ Credential = $Credential }
    }
    

    if ("" -ne $ActiveSubscription)
    {
        $params += @{ SubscriptionName = $ActiveSubscription }
        Write-Verbose -Message "Connecting to $ActiveSubscription subscription"
    }
    else
    {
        Write-Warning -Message "You will be connected to the first available subscription."
    }

    try
    {
        $Script:AzureLoginInfo = Login-AzureRmAccount @params
        Write-Verbose -Message "Login success"
    }
    catch
    {
        throw
        return
    }

    if ("" -eq $ActiveSubscription)
    {
        Write-Warning -Message "You are connected to the $($Script:AzureLoginInfo.Context.Subscription.SubscriptionName) subscription."
    }

    $Script:AzureSubscriptionInfo = Get-AzureRmSubscription

    $Script:SubNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty SubscriptionName

    Write-Verbose -Message "$($Script:SubNames.Count) available subscriptions"

    $Script:AzureConnected = $true

    Write-Verbose -Message "AzureTools module is ready for use"

    $Script:CurrentSubName = $Script:AzureLoginInfo.Context.Subscription.SubscriptionName

    set-Prompt
}

function Get-AzureActiveSubscription
{
    <#
    .SYNOPSIS
    Return information about your currently active subscription

    .DESCRIPTION
    Return information about your currently active subscription
    #>
    if ($Script:AzureLoginInfo -eq $null)
    {
        Write-Warning -Message "Command completed successfully, but you are not connected"
        return    
    }
    return $Script:AzureLoginInfo
}

function Get-AzureAvailableSubscriptions
{
    <#
    .SYNOPSIS
    Get all subscriptions available to you.

    .DESCRIPTION
    Get all subscriptions available to you currently stored in memory. Use -Update to update this information from Azure

    .PARAMETER Update
    Use this flag to indicate you want to refresh the subscription information stored in memory.
    #>
    Param([switch] $Update)
    
    if ($Update)
    {
        try
        {
            $Script:AzureSubscriptionInfo = Get-AzureRmSubscription -ErrorAction Stop

            $Script:SubNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty SubscriptionName -ErrorAction Stop
        }
        catch
        {
            Write-Warning -Message "Unable to update subscriptions $($Error[0])"
        }   
    }

    return $Script:AzureSubscriptionInfo 
}

function Select-AzureActiveSubscription
{
    <#
    .SYNOPSIS
    Select the currently active subscription from subscriptions available to you.

    .DESCRIPTION
    Select the currently active subscription from subscriptions available to you. 
    -Subscription parameter will autopopulate the names of available subscriptions for you once connected.
    It is a Dynamic Parameter, so it will not appear in Get-Help or Get-Command
    #>
    [CmdletBinding()]
    Param()
    DynamicParam 
    {
        return (get-SubscriptionParameter)
    }

    Begin
    {
        if ($Script:AzureConnected)
        {
            $Script:AzureLoginInfo = Select-AzureRmSubscription -SubscriptionName $PSBoundParameters.Subscription

            $Script:CurrentSubName = $Script:AzureLoginInfo.Subscription.SubscriptionName
        }
        else
        {
            Write-Error -Exception (New-Object -TypeName System.Management.Automation.PSInvalidOperationException -ArgumentList ("Run Connect-Azure to connect. If you connected using Login-AzureRmAccount, you will not be able to use this module."))
        }
    }
    
    
}

Export-ModuleMember -Function Connect-AzureTools,Get-AzureActiveSubscription,Get-AzureAvailableSubscriptions,Select-AzureActiveSubscription