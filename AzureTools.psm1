# script variables

$Script:AzureConnected = $false

$Script:AzureSubscriptionInfo = $null

$Script:AzureLoginInfo = $null

$Script:SubNames = @()

$Script:SubNames += ""

$Script:CurrentSubName = ""

# helper functions. not exported.
function new-SubscriptionParameter
{
    $parameterName = "Subscription"

    # Create the attribute collection
    $attributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]

    # Create the Parameter() block
    $subAttribute = New-Object -TypeName System.Management.Automation.ParameterAttribute       
    $subAttribute.Position = 1
    $subAttribute.Mandatory = $true
    $subAttribute.HelpMessage = "The name of the subscription to connect to"

    # Create the ValidateSetAttribute() block using the subscription names
    $validateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($Script:SubNames)


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
        $sb = {"PS [Azure:\$($Script:CurrentSubName)] $((Get-Location).Path)> " }
        
        Set-Item -Path function:prompt -Value $sb
    }
    catch
    {
        # swallow because this isn't really important
    }
}

function set-DateFormat
{
    Param([DateTime] $Date, [string] $Granularity)

    if ($Granularity -eq "Daily")
    {
        Get-Date -Year $Date.Year -Month $date.Month -Day $date.Day -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    }
    else
    {
        Get-Date -Year $Date.Year -Month $date.Month -Day $date.Day -Hour $date.Hour -Minute 0 -Second 0 -Millisecond 0
    }
}


# AzureRM function wrappers
function Connect-AzureTools
{
    <#
    .SYNOPSIS
    Run before using any other Azure or non-AzureAPI AzureTools cmdlets. Use instead of the Login-AzureRmAccount cmdlet.

    .DESCRIPTION
    Wrapper for the Login-AzureRmAccount cmdlet. Connects, then adds some information to the environment for use later. Must be used instead of Login-AzureRmAccount if this module's functions are to be used. Other AzureRm cmdlets are available to use normally.

    .PARAMETER Credential
    The credential to use to connect to Azure. Leave blank if not using an organization account.

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
        Write-Warning -Message "You are connected to the $($Script:AzureLoginInfo.Context.Subscription.Name) subscription."
    }

    $Script:AzureSubscriptionInfo = Get-AzureRmSubscription -WarningAction SilentlyContinue

    $Script:SubNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty Name

    Write-Verbose -Message "$($Script:SubNames.Count) available subscriptions"

    $Script:AzureConnected = $true

    Write-Verbose -Message "AzureTools module is ready for use"

    $Script:CurrentSubName = $Script:AzureLoginInfo.Context.Subscription.Name

    set-Prompt
}

function Get-AzureActiveSubscription
{
    <#
    .SYNOPSIS
    Return information about your currently active subscription

    .DESCRIPTION
    Return information about your currently active subscription

    .OUTPUTS
    The currently active subscription
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
    Use this switch to indicate you want to refresh the subscription information stored in memory.

    .OUTPUTS
    A list of all available subscriptions
    #>
    Param([switch] $Update)
    
    if ($Update)
    {
        try
        {
            $Script:AzureSubscriptionInfo = Get-AzureRmSubscription -ErrorAction Stop -WarningAction SilentlyContinue

            $Script:SubNames = $Script:AzureSubscriptionInfo | Select-Object -ExpandProperty Name -ErrorAction Stop
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

    DYNAMIC PARAMETERS
    [-Subscription] <string> The name of the subscription to connect to. Will autopopulate/validate the names of available subscriptions for you once connected.
    
    #>
    [CmdletBinding()]
    Param()
    DynamicParam 
    {
        return (new-SubscriptionParameter)
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

# REST Api functions
function New-AzureAPIAuthorizationHeader
{
    <#
    .SYNOPSIS
    Create an Azure API Authorization header using either ActiveDirectory.AuthentacionContext or OAUTH

    .DESCRIPTION
    Authenticate to https://login.windows.net/{tenantId} with a Client ID and Client Key, and get an Authorization header in return. Useful for RateCard and ResourceUsage aggregate APIs.

    OR

    Authenticate to https://login.microsoftonline.com to get an OAUTH token. Useful for the Azure Graph APIs

    .PARAMETER TenantId
    The Guid ID of the tenant you wish to authenticate with.

    .PARAMETER TenantDomain
    The domain to connect to. consoto.onmicrosoft.com, as an example

    .PARAMETER ClientId
    The Application Id registered at https://portal.azure.com, with a return URL of http://localhost.

    .PARAMETER ClientKey
    The secret key generated from the application registered at https://portal.azure.com.

    .PARAMETER Resource
    The resource to authenticate with. Defaults to https://graph.windows.net

    .OUTPUTS
    An IDictionary object with Authorization = <AUTH>. Add as a header to AzureAPI rest requests, or use in other AzureTools API functions.
    #>
    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ParameterSetName = "AUTHCONTEXT")]
        [Guid] $TenantId,

        [Parameter(
            Mandatory = $true,
            Position = 0,
            ParameterSetName = "OAUTH")]
        [ValidateNotNullOrEmpty()]
        [string] $TenantDomain,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            ParameterSetName = "AUTHCONTEXT")]
        [Parameter(
            Mandatory = $true,
            Position = 1,
            ParameterSetName = "OAUTH")]
        [Guid] $ClientId,

        [Parameter(
            Mandatory = $true,
            Position = 2,
            ParameterSetName = "AUTHCONTEXT")]
        [Parameter(
            Mandatory = $true,
            Position = 2,
            ParameterSetName = "OAUTH")]
        [ValidateNotNullOrEmpty()]
        [string] $ClientKey,

        [Parameter(
            Mandatory = $false,
            Position = 3,
            ParameterSetName = "OAUTH")]
        [string] $Resource = "https://graph.windows.net"
        )

    if ($PSCmdlet.ParameterSetName -eq "AUTHCONTEXT")
    {
        $loginUrl = "https://login.windows.net/$TenantId"

        $authContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]$loginUrl

        $cred = New-Object -TypeName Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential -ArgumentList ($ClientId,$ClientKey)

        try
        {
            $result = $authContext.AcquireToken("https://management.core.windows.net/",$cred)
        }
        catch
        {
            throw
            return
        }

        $authHeader = @{'Authorization' = $result.CreateAuthorizationHeader()}
    }
    else
    {
        $loginUrl = "https://login.microsoftonline.com"

        $body = @{grant_type="client_credentials";resource=$Resource;client_id=$ClientID;client_secret=$ClientKey}
        $oauth = Invoke-RestMethod -Method Post -Uri $loginUrl/$TenantDomain/oauth2/token?api-version=1.0 -Body $body

        if ($oauth.access_token -eq $null)
        {
            throw
            return
        }

        $authHeader = @{'Authorization' = "$($oauth.token_type) $($oauth.access_token)"}
    }

    Write-Output -InputObject $authHeader
}

function Get-AzureAPIResourceUsageAggregates
{
    <#
    .SYNOPSIS
    Get Azure API Resource Usage aggregate data for a subscription.

    .DESCRIPTION
    Get Azure API Resource Usage aggregate data for a subscription, aggregating either daily or hourly.

    .PARAMETER SubscriptionId
    The Guid ID of the subscription you wish to query.

    .PARAMETER StartDate
    The date to begin aggregation. If using Daily aggregation, Time will be set to midnight of the input date per API requirements.

    .PARAMETER EndDate
    The date to end aggregation. If using Daily aggregation, Time will be set to midnight of the input date per API requirements.

    .PARAMETER AggregationGranularity
    Daily or Hourly data aggregation.

    .PARAMETER AuthorizationHeader
    The authorization header from your tenant. Use New-AzureAPIAuthorizationHeader to create one, or make one as an IDictionary object.

    .PARAMETER ApiVersion
    The API version to use. Defaults to 2015-06-01-preview.

    .PARAMETER ShowDetails
    Show extra details in your usage aggregates that are not typically needed.

    .OUTPUTS
    Resource Usage Aggregates matching your request.
    #>

    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0)]
        [Guid] $SubscriptionId,

        [Parameter(
            Mandatory = $true,
            Position = 1)]
        [DateTime] $StartDate,

        [Parameter(
            Mandatory = $true,
            Position = 2)]
        [DateTime] $EndDate,

        [Parameter(
            Mandatory = $true,
            Position = 3)]
        [ValidateSet("Daily","Hourly")]
        [string] $AggregationGranularity,

        [Parameter(
            Mandatory = $true,
            Position = 4)]
        [System.Collections.IDictionary] $AuthorizationHeader,

        [Parameter(
            Mandatory = $false,
            Position = 5)]
        [string] $ApiVersion = "2015-06-01-preview",

        [switch] $ShowDetails
        )

    $infoUrl = "https://management.azure.com/subscriptions/$($SubscriptionId)/providers/Microsoft.Commerce/UsageAggregates"

    $StartDate = set-DateFormat -Date $StartDate -Granularity $AggregationGranularity
    $EndDate = set-DateFormat -Date $EndDate -Granularity $AggregationGranularity

    $body = @{
        "api-version" = $ApiVersion
        "reportedStartTime" = $StartDate.ToString()
        "reportedEndTime" = $EndDate.ToString()
        "aggregationGranularity" = $AggregationGranularity
        "showDetails" = $ShowDetails.ToString()}
     
    Invoke-RestMethod -Uri $infoUrl -Body $body -Headers $AuthorizationHeader
}

function Get-AzureAPIRateCard
{
    <#
    .SYNOPSIS
    Get Azure API RateCard data for a subscription

    .DESCRIPTION
    Get Azure API RateCard data for a subscription using your Guid subscription ID and OfferDurableId that begins MS-AZR-

    .PARAMETER SubscriptionId
    The Guid ID of the subscription you wish to query

    .PARAMETER StartDate
    The date to begin aggregation. If using Daily aggregation, Time will be set to midnight of the input date per API requirements.

    .PARAMETER EndDate
    The date to end aggregation. If using Daily aggregation, Time will be set to midnight of the input date per API requirements.

    .PARAMETER AggregationGranularity
    Daily or Hourly data aggregation

    .PARAMETER AuthorizationHeader
    The authorization header from your tenant. Use New-AzureAPIAuthorizationHeader to create one, or make one as an IDictionary object.

    .PARAMETER ApiVersion
    The API version to use. Defaults to 2016-08-31-preview.

    .PARAMETER Currency
    The Currency code to use. Defaults to USD.

    .PARAMETER Locale
    The Locale code to use. Defaults to en-US.

    .PARAMETER RegionInfo
    The RegionInfo code to use. Defaults to US.

    .OUTPUTS
    Azure RateCard information
    #>

    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0)]
        [Guid] $SubscriptionId,

        [Parameter(
            Mandatory = $true,
            Position = 1)]
        [ValidatePattern("MS-AZR-")]
        [string] $OfferDurableId,

        [Parameter(
            Mandatory = $true,
            Position = 2)]
        [System.Collections.IDictionary] $AuthorizationHeader,

        [Parameter(
            Mandatory = $false,
            Position = 3)]
        [string] $ApiVersion = "2016-08-31-preview",

        [Parameter(
            Mandatory = $false,
            Position = 4)]
        [ValidateLength(3,3)]
        [string] $Currency = "USD",

        [Parameter(
            Mandatory = $false,
            Position = 5)]
        [ValidateLength(4,4)]
        [string] $Locale = "en-US",

        [Parameter(
            Mandatory = $false,
            Position = 6)]
        [ValidateLength(2,2)]
        [string] $RegionInfo = "US"
        )

    $url = "https://management.azure.com/subscriptions/$($SubscriptionId)/providers/Microsoft.Commerce/RateCard"

    $body = @{
        
        "api-version" = $ApiVersion
        "`$filter" = "OfferDurableId eq '$($OfferDurableId)' and Currency eq '$($Currency)' and Locale eq '$($Locale)' and RegionInfo eq '$($RegionInfo)'"

        }

    Invoke-RestMethod -Uri $url -Headers $AuthorizationHeader -Body $body
}

Export-ModuleMember -Function Connect-AzureTools,Get-AzureActiveSubscription,Get-AzureAvailableSubscriptions,Select-AzureActiveSubscription,New-AzureAPIAuthorizationHeader,Get-AzureAPIResourceUsageAggregates,Get-AzureAPIRateCard