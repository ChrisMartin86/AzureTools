# script variables

$Script:AzureConnected = $false

$Script:AzureSubscriptionInfo = $null

$Script:AzureLoginInfo = $null

$Script:SubscriptionNames = $null

$Script:CurrentSubName = ""

# helper functions. not exported.
function createSubscriptionParameter
{
    $parameterName = "Subscription"
    $SubscriptionNames = $Script:SubscriptionNames

    # Create the attribute collection
    $attributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]

    # Create the Parameter() block
    $subAttribute = New-Object -TypeName System.Management.Automation.ParameterAttribute       
    $subAttribute.Position = 1
    $subAttribute.Mandatory = $true
    $subAttribute.HelpMessage = "The name of the subscription to connect to"

    # Create the ValidateSetAttribute() block using the subscription names
    $validateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($SubscriptionNames)


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

function setPrompt
{
    try
    {
        $sb = { $currentDirPath = Get-Item -Path .\ | Select-Object -ExpandProperty FullName; "PS [Azure:\$($Script:CurrentSubName)] $currentDirPath> " }
        
        Set-Item -Path function:prompt -Value $sb
    }
    catch
    {
        # Break to not cause more errors
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
        Write-Error -Message "There was a problem connecting to Azure - $($Error[0]). Cannot continue."
        return
    }

    if ("" -eq $ActiveSubscription)
    {
        Write-Warning -Message "You are connected to the $($Script:AzureLoginInfo.Context.Subscription.SubscriptionName) subscription."
    }

    $Script:AzureSubscriptionInfo = Get-AzureRmSubscription

    $Script:SubscriptionNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty SubscriptionName

    Write-Verbose -Message "$($Script:SubscriptionNames.Count) available subscriptions"

    $Script:AzureConnected = $true

    $Script:CurrentSubName = $Script:AzureLoginInfo.Context.Subscription.SubscriptionName

    setPrompt

    Write-Verbose -Message "AzureTools module is ready for use"
}

function Get-AzureActiveSubscription
{
    <#
    .SYNOPSIS
    Return information about your currently active subscription

    .DESCRIPTION
    Return information about your currently active subscription
    #>
    if ($Script:AzureConnected -ne $true)
    {
        Write-Error -Exception (New-Object -TypeName System.Management.Automation.PSInvalidOperationException -ArgumentList ("AzureTools is not connected. Run Connect-AzureTools (not Login-AzureRmAccount) to connect."))
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

    if ($Script:AzureConnected -ne $true)
    {
        Write-Error -Exception (New-Object -TypeName System.Management.Automation.PSInvalidOperationException -ArgumentList ("AzureTools is not connected. Run Connect-AzureTools (not Login-AzureRmAccount) to connect."))
        return    
    }
    
    if ($Update)
    {
        try
        {
            $Script:AzureSubscriptionInfo = Get-AzureRmSubscription -ErrorAction Stop

            $Script:SubscriptionNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty SubscriptionName -ErrorAction Stop
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
        return (createSubscriptionParameter)
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
            Write-Error -Exception (New-Object -TypeName System.Management.Automation.PSInvalidOperationException -ArgumentList ("AzureTools is not connected. Run Connect-AzureTools (not Login-AzureRmAccount) to connect."))
        }
    }    
}

Export-ModuleMember -Function Connect-AzureTools,Get-AzureActiveSubscription,Get-AzureAvailableSubscriptions,Select-AzureActiveSubscription