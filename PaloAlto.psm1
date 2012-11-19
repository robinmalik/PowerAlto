﻿function Get-PaConnectionString {
	<#
	.SYNOPSIS
		Connects to a Palo Alto firewall and returns an connection string with API key.
	.DESCRIPTION
		Connects to a Palo Alto firewall and returns an connection string with API key.
	.EXAMPLE
		Connect-Pa -Address 192.168.1.1 -Cred PSCredential
	.EXAMPLE
		Connect-Pa 192.168.1.1
	.PARAMETER Address
		Specifies the IP or DNS name of the system to connect to.
    .PARAMETER User
        Specifies the username to make the connection with.
    .PARAMETER Password
        Specifies the password to make the connection with.
	#>

    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$Address,

        [Parameter(Mandatory=$True,Position=1)]
        [System.Management.Automation.PSCredential]$Cred
    )

    BEGIN {
        $WebClient = New-Object System.Net.WebClient
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        Add-Type -AssemblyName System.Management.Automation
    }

    PROCESS {
        $user = $cred.UserName.Replace("\","")
        $ApiKey = ([xml]$WebClient.DownloadString("https://$Address/api/?type=keygen&user=$user&password=$($cred.getnetworkcredential().password)"))
        if ($ApiKey.response.status -eq "success") {
            return "https://$Address/api/?key=$($ApiKey.response.result.key)"
        } else {
            Throw "$($ApiKey.response.result.msg)"
        }
    }
}

function Get-PaSystemInfo {
	<#
	.SYNOPSIS
		Returns the version number of various components of a Palo Alto firewall.
	.DESCRIPTION
		Returns the version number of various components of a Palo Alto firewall.
	.EXAMPLE
        Get-PaVersion -PaConnectionString https://192.168.1.1/api/?key=apikey
	.EXAMPLE
		Get-PaVersion https://192.168.1.1/api/?key=apikey
	.PARAMETER PaConnectionString
		Specificies the Palo Alto connection string with address and apikey.
	#>

    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$PaConnectionString
    )

    BEGIN {
        $WebClient = New-Object System.Net.WebClient
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    }

    PROCESS {
        $Url = "$PaConnectionString&type=op&cmd=<show><system><info></info></system></show>"
        $SystemInfo = ([xml]$WebClient.DownloadString($Url)).response.result.system
        return $SystemInfo
        
    }
}

function Get-PaCustom {
    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$PaConnectionString,

        [Parameter(Mandatory=$True,Position=1)]
        [string]$Type,

        [Parameter(Mandatory=$True,Position=2)]
        [string]$Action,

        [Parameter(Mandatory=$True,Position=3)]
        [string]$XPath
    )

    BEGIN {
        $WebClient = New-Object System.Net.WebClient
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    }

    PROCESS {
        $url = "$PaConnectionString&type=$type&action=$action&xpath=$xpath"
        $CustomData = [xml]$WebClient.DownloadString($Url)
        if ($CustomData.response.status -eq "success") {
            if ($action -eq "show") {
                return $CustomData
            } else {
                return $customdata.response.status
            }
        } else {
            Throw "$($CustomData.response.result.msg)"
        }
    }
}



function Get-PaRules {
    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$PaConnectionString
    )

    BEGIN {

    }

    PROCESS {
        $type = "config"
        $action = "show"
        $xpath = "/config/devices/entry/vsys/entry/rulebase/security/rules"
        $SecurityRulebase = (Get-PaCustom $PaConnectionString $type $action $xpath).response.result.rules.entry

        #Create hashtable for SecurityRule PSObject.  For new properties just append string to $ExportString
        $SecurityRule = @{}
        $ExportString = @("Name","Description","Tag","SourceZone","SourceAddress","SourceNegate","SourceUser","HipProfile","DestinationZone","DestinationAddress","DestinationNegate","Application","Service","UrlCategory","Action","ProfileType","ProfileGroup","ProfileVirus","ProfileVuln","ProfileSpy","ProfileUrl","ProfileFile","ProfileData","LogStart","LogEnd","LogForward","DisableSRI","Schedule","QosType","QosMarking","Disabled")

        foreach ($Value in $ExportString) {
            $SecurityRule.Add($Value,$null)
        }

        $SecurityRules = @()

        #Covert results into PSobject
        foreach ($entry in $SecurityRulebase) {
            $CurrentRule = New-Object PSObject -Property $SecurityRule
                $CurrentRule.Name               = $entry.name
                $CurrentRule.Description        = $entry.description
                $CurrentRule.Tag                = $entry.tag.member
                $CurrentRule.SourceZone         = $entry.from.member
                $CurrentRule.SourceAddress      = $entry.source.member
                $CurrentRule.SourceNegate       = $entry."negate-source"
                $CurrentRule.SourceUser         = $entry."source-user".member
                $CurrentRule.HipProfile         = $entry."hip-profiles".member
                $CurrentRule.DestinationZone    = $entry.to.member
                $CurrentRule.DestinationAddress = $entry.destination.member
                $CurrentRule.DestinationNegate  = $entry."negate-destination"
                $CurrentRule.Application        = $entry.application.member
                $CurrentRule.Service            = $entry.service.member
                $CurrentRule.UrlCategory        = $entry.category.member
                $CurrentRule.Action             = $entry.action
                if ($entry."profile-setting".group) {
                    $CurrentRule.ProfileGroup   = $entry."profile-setting".group.member
                    $CurrentRule.ProfileType    = "group"
                } elseif ($entry."profile-setting".profiles) {
                    $CurrentRule.ProfileType    = "profiles"
                    $CurrentRule.ProfileVirus   = $entry."profile-setting".profiles.virus.member
                    $CurrentRule.ProfileVuln    = $entry."profile-setting".profiles.vulnerability.member
                    $CurrentRule.ProfileSpy     = $entry."profile-setting".profiles.spyware.member
                    $CurrentRule.ProfileUrl     = $entry."profile-setting".profiles."url-filtering".member
                    $CurrentRule.ProfileFile    = $entry."profile-setting".profiles."file-blocking".member
                    $CurrentRule.ProfileData    = $entry."profile-setting".profiles."data-filtering".member
                }
                $CurrentRule.LogStart           = $entry."log-start"
                $CurrentRule.LogEnd             = $entry."log-end"
                $CurrentRule.LogForward         = $entry."log-setting"
                $CurrentRule.Schedule           = $entry.schedule
                if ($entry.qos.marking."ip-dscp") {
                    $CurrentRule.QosType        = "ip-dscp"
                    $CurrentRule.QosMarking     = $entry.qos.marking."ip-dscp"
                } elseif ($entry.qos.marking."ip-precedence") {
                    $CurrentRule.QosType        = "ip-precedence"
                    $CurrentRule.QosMarking     = $entry.qos.marking."ip-precedence"
                }
                $CurrentRule.DisableSRI         = $entry.option."disable-server-response-inspection"
                $CurrentRule.Disabled           = $entry.disabled
            $SecurityRules += $CurrentRule
        }
        return $SecurityRules | select $ExportString
    }
}

function Set-PaRule {
	<#
	.SYNOPSIS
		Edits settings on a Palo Alto Security Rule
	.DESCRIPTION
		Edits settings on a Palo Alto Security Rule
	.EXAMPLE
        Needs to write some examples
	.EXAMPLE
		Needs to write some examples
	.PARAMETER PaConnectionString
		Specificies the Palo Alto connection string with address and apikey.
	#>
    
    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$PaConnectionString,

        [Parameter(Mandatory=$True,Position=1)]
        [string]$Name,

        [alias('r')]
        [string]$Rename,

        [alias('d')]
        [string]$Description,

        [alias('t')]
        [string]$Tag,

        [alias('sz')]
        [string]$SourceZone,

        [alias('sa')]
        [string]$SourceAddress,

        [alias('su')]
        [string]$SourceUser,

        [alias('h')]
        [string]$HipProfile,

        [alias('dz')]
        [string]$DestinationZone,

        [alias('da')]
        [string]$DestinationAddress,

        [alias('app')]
        [string]$Application,

        [alias('s')]
        [string]$Service,

        [alias('u')]
        [string]$UrlCategory,

        [alias('sn')]
        [ValidateSet("yes","no")] 
        [string]$SourceNegate,

        [alias('dn')]
        [ValidateSet("yes","no")] 
        [string]$DestinationNegate,

        [alias('a')]
        [ValidateSet("allow","deny")] 
        [string]$Action,

        [alias('ls')]
        [ValidateSet("yes","no")] 
        [string]$LogStart,

        [alias('le')]
        [ValidateSet("yes","no")] 
        [string]$LogEnd,

        [alias('lf')]
        [string]$LogForward,

        [alias('sc')]
        [string]$Schedule,

        [alias('dis')]
        [ValidateSet("yes","no")]
        [string]$Disabled,

        [alias('pg')]
        [string]$ProfileGroup,

        [alias('pvi')]
        [string]$ProfileVirus,

        [alias('pvu')]
        [string]$ProfileVuln,

        [alias('ps')]
        [string]$ProfileSpy,

        [alias('pu')]
        [string]$ProfileUrl,

        [alias('pf')]
        [string]$ProfileFile,

        [alias('pd')]
        [string]$ProfileData,

        [alias('qd')]
        [ValidateSet("af11","af12","af13","af21","af22","af23","af31","af32","af33","af41","af42","af43","cs0","cs1","cs2","cs3","cs4","cs5","cs6","cs7","ef")] 
        [string]$QosDscp,

        [alias('qp')]
        [ValidateSet("cs0","cs1","cs2","cs3","cs4","cs5","cs6","cs7")] 
        [string]$QosPrecedence,

        [alias('ds')]
        [ValidateSet("yes","no")] 
        [string]$DisableSri
    )

    BEGIN {
        $WebClient = New-Object System.Net.WebClient
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $type = "config"
        function EditWithMembers ($parameter,$element,$xpath) {
            if ($parameter) {
                $type = "config"
                $action = "edit"
                $Members = $null
                foreach ($Member in $parameter.split()) {
                    $Members += "<member>$Member</member>"
                }
                $xpath += "/$element&element=<$element>$Members</$element>"
                return Get-PaCustom $PaConnectionString $type $action $xpath
            }
        }

        function EditWithoutMembers ($parameter,$element,$xpath) {
            if ($parameter) {
                $parameter = $parameter.replace(" ",'%20')
                $action = "edit"
                $xpath += "/$element&element=<$element>$parameter</$element>"
                Get-PaCustom $PaConnectionString $type $action $xpath
            }
        }
    }

    PROCESS {
        $xpath = "/config/devices/entry/vsys/entry/rulebase/security/rules/entry[@name='$Name']"
        if ($Rename) {
            $apiaction = 'rename'
            $xpath += "&newname=$Rename"
            Get-PaCustom $PaConnectionString $type $apiaction $xpath
        }

        EditWithoutMembers $Description "description" $xpath
        EditWithoutMembers $SourceNegate "negate-source" $xpath
        EditWithoutMembers $DestinationNegate "negate-destination" $xpath
        EditWithoutMembers $Action "action" $xpath
        EditWithoutMembers $LogStart "log-start" $xpath
        EditWithoutMembers $LogEnd "log-end" $xpath
        EditWithoutMembers $LogForward "log-setting" $xpath
        EditWithoutMembers $Schedule "schedule" $xpath
        EditWithoutMembers $Disabled "disabled" $xpath
        EditWithoutMembers $QosDscp "ip-dscp" "$xpath/qos/marking"
        EditWithoutMembers $QosPrecedence "ip-precedence" "$xpath/qos/marking"
        EditWithoutMembers $DisableSri "disable-server-response-inspection" "$xpath/option"

        EditWithMembers $SourceAddress "source" $xpath
        EditWithMembers $SourceZone "from" $xpath
        EditWithMembers $Tag "tag" $xpath
        EditWithMembers $SourceUser "source-user" $xpath
        EditWithMembers $HipProfile "hip-profiles" $xpath
        EditWithMembers $DestinationZone "to" $xpath
        EditWithMembers $DestinationAddress "destination" $xpath
        EditWithMembers $Application "application" $xpath
        EditWithMembers $Service "service" $xpath
        EditWithMembers $UrlCategory "category" $xpath
        EditWithMembers $HipProfile "hip-profiles" $xpath
        EditWithMembers $ProfileGroup "group" "$xpath/profile-setting"
        EditWithMembers $ProfileVirus "virus" "$xpath/profile-setting/profiles"
        EditWithMembers $ProfileVuln "vulnerability" "$xpath/profile-setting/profiles"
        EditWithMembers $ProfileSpy "spyware" "$xpath/profile-setting/profiles"
        EditWithMembers $ProfileUrl "url-filtering" "$xpath/profile-setting/profiles"
        EditWithMembers $ProfileFile "file-blocking" "$xpath/profile-setting/profiles"
        EditWithMembers $ProfileData "data-filtering" "$xpath/profile-setting/profiles"
    }
}

function Invoke-PaCommit {
	<#
	.SYNOPSIS
		Commits candidate config to Palo Alto firewall
	.DESCRIPTION
		Commits candidate config to Palo Alto firewall and returns resulting job stats.
	.EXAMPLE
        Needs to write some examples
	.EXAMPLE
		Needs to write some examples
	.PARAMETER PaConnectionString
		Specificies the Palo Alto connection string with address and apikey.
    .PARAMETER Force
		Forces the commit command in the event of a conflict.
	#>
    
    Param (
        [Parameter(Mandatory=$True,Position=0)]
        [string]$PaConnectionString,

        [Parameter(Position=1)]
        [switch]$Force
    )

    BEGIN {
        $WebClient = New-Object System.Net.WebClient
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $type = "commit"
        $cmd = "<commit></commit>"
        if ($Force) {
            $cmd = "<commit><force></force></commit>"
        }   
    }

    PROCESS {
        $url = "$PaConnectionString&type=$type&cmd=$cmd"
        $CustomData = [xml]$WebClient.DownloadString($Url)
        if ($CustomData.response.status -eq "success") {
            if ($CustomData.response.msg -match "no changes") {
                Return "There are no changes to commit."
            }
            $job = $CustomData.response.result.job
            $cmd = "<show><jobs><id>$job</id></jobs></show>"
            $url = "$PaConnectionString&type=op&cmd=$cmd"
            $JobStatus = [xml]$WebClient.DownloadString($Url)
            while ($JobStatus.response.result.job.status -ne "FIN") {
                Write-Progress -Activity "Commiting to PA" -Status "$($JobStatus.response.result.job.progress)% complete"-PercentComplete ($JobStatus.response.result.job.progress)
                $JobStatus = [xml]$WebClient.DownloadString($Url)
            }
            return $JobStatus.response.result.job
        }
        return "Error"
    }
}