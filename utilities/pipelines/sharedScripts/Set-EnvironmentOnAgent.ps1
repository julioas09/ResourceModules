# Note: The installation commands in this script are optimized for Linux

#region Helper Functions
<#
.SYNOPSIS
Installes given PowerShell modules

.DESCRIPTION
Installes given PowerShell modules

.PARAMETER Module
Required. Modules to be installed, must be Object
@{
    Name = 'Name'
    Version = '1.0.0' # Optional
}

.PARAMETER installedModules
Optional. Modules that are already installed on the machine. Can be fetched via 'Get-Module -ListAvailable'

.EXAMPLE
Install-CustomModule @{ Name = 'Pester' } C:\Modules

Installes pester and saves it to C:\Modules
#>
function Install-CustomModule {

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Hashtable] $Module,

        [Parameter(Mandatory = $false)]
        [object[]] $installedModules = @()
    )

    # Remove exsisting module in session
    if (Get-Module $Module -ErrorAction 'SilentlyContinue') {
        try {
            Remove-Module $Module -Force
        } catch {
            Write-Error ('Unable to remove module [{0}] because of exception [{1}]. Stack Trace: [{2}]' -f $Module.Name, $_.Exception, $_.ScriptStackTrace)
        }
    }

    # Install found module
    $moduleImportInputObject = @{
        name       = $Module.Name
        Repository = 'PSGallery'
    }
    if ($Module.Version) {
        $moduleImportInputObject['RequiredVersion'] = $Module.Version
    }

    # Get all modules that match a certain name. In case of e.g. 'Az' it returns several.
    $foundModules = Find-Module @moduleImportInputObject

    foreach ($foundModule in $foundModules) {

        # Check if already installed as required
        if ($alreadyInstalled = $installedModules | Where-Object { $_.Name -eq $Module.Name }) {
            if ($Module.Version) {
                $alreadyInstalled = $alreadyInstalled | Where-Object { $_.Version -eq $Module.Version }
            } else {
                # Get latest in case of multiple
                $alreadyInstalled = ($alreadyInstalled | Sort-Object -Property Version -Descending)[0]
            }
            Write-Verbose ('Module [{0}] already installed with version [{1}]' -f $alreadyInstalled.Name, $alreadyInstalled.Version) -Verbose
            continue
        }

        # Check if not to be excluded
        if ($module.ExcludeModules -and $module.excludeModules.contains($foundModule.Name)) {
            Write-Verbose ('Module {0} is configured to be ignored.' -f $foundModule.Name) -Verbose
            continue
        }

        Write-Verbose ('Install module [{0}] with version [{1}]' -f $foundModule.Name, $foundModule.Version) -Verbose
        if ($PSCmdlet.ShouldProcess('Module [{0}]' -f $foundModule.Name, 'Install')) {
            $foundModule | Install-Module -Force -SkipPublisherCheck -AllowClobber
            if ($installed = Get-Module -Name $foundModule.Name -ListAvailable) {
                Write-Verbose ('Module [{0}] is installed with version [{1}]' -f $installed.Name, $installed.Version) -Verbose
            } else {
                Write-Error ('Installation of module [{0}] failed' -f $foundModule.Name)
            }
        }
    }
}
#endregion

<#
.SYNOPSIS
Configure the current agent

.DESCRIPTION
Configure the current agent with e.g. the necessary PowerShell modules.

.PARAMETER PSModules
Optional. The PowerShell modules that should be installed on the agent.

@(
    @{ Name = 'Az.Accounts' },
    @{ Name = 'Az.Compute' },
    @{ Name = 'Az.Resources' },
    @{ Name = 'Az.ContainerRegistry' },
    @{ Name = 'Az.KeyVault' },
    @{ Name = 'Az.RecoveryServices' },
    @{ Name = 'Az.Monitor' },
    @{ Name = 'Az.CognitiveServices' },
    @{ Name = 'Az.OperationalInsights' },
    @{
        Name = 'Pester'
        Version = '5.3.1' # Version is optional
    }
)

.EXAMPLE
Set-EnvironmentOnAgent

Install the default PowerShell modules to configure the agent
#>
function Set-EnvironmentOnAgent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Hashtable[]] $PSModules = @()
    )

    ###########################
    ##   Install Azure CLI   ##
    ###########################

    # AzCLI is pre-installed on GitHub hosted runners.
    # https://github.com/actions/virtual-environments#available-environments

    az --version
    <#
    Write-Verbose ("Install azure cli start") -Verbose
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    Write-Verbose ("Install azure cli end") -Verbose
    #>

    ##############################
    ##   Install Bicep for CLI   #
    ##############################

    # Bicep CLI is pre-installed on GitHub hosted runners.
    # https://github.com/actions/virtual-environments#available-environments

    bicep --version
    <#
    Write-Verbose ("Install bicep start") -Verbose
    # Fetch the latest Bicep CLI binary
    curl -Lo bicep 'https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64'

    # Mark it as executable
    chmod +x ./bicep

    # Add bicep to your PATH (requires admin)
    sudo mv ./bicep /usr/local/bin/bicep
    Write-Verbose ("Install bicep end") -Verbose
    #>

    ###############################
    ##   Install Extensions CLI   #
    ###############################

    # Azure CLI extension for DevOps is pre-installed on GitHub hosted runners.
    # https://github.com/actions/virtual-environments#available-environments

    az extension list | ConvertFrom-Json | Select-Object -Property name, version, preview, experimental

    <#
    Write-Verbose ('Install cli exentions start') -Verbose
    $Extensions = @(
        'azure-devops'
    )
    foreach ($extension in $Extensions) {
        if ((az extension list-available -o json | ConvertFrom-Json).Name -notcontains $extension) {
            Write-Verbose "Adding CLI extension '$extension'" -Verbose
            az extension add --name $extension
        }
    }
    Write-Verbose ('Install cli exentions end') -Verbose
    #>

    ####################################
    ##   Install PowerShell Modules   ##
    ####################################

    $stopwatch = [system.diagnostics.stopwatch]::StartNew()

    $count = 1
    Write-Verbose ('Try installing:') -Verbose
    $modules | ForEach-Object {
        Write-Verbose ('- {0}. [{1}]' -f $count, $_.Name) -Verbose
        $count++
    }

    $installedModules = Get-Module -ListAvailable

    Write-Verbose ('Install-CustomModule start') -Verbose
    $count = 1
    Foreach ($Module in $Modules) {
        Write-Verbose ('=====================') -Verbose
        Write-Verbose ('HANDLING MODULE [{0}/{1}] [{2}] ' -f $count, $Modules.Count, $Module.Name) -Verbose
        Write-Verbose ('=====================') -Verbose
        # Installing New Modules and Removing Old
        $null = Install-CustomModule -Module $Module -InstalledModules $installedModules
        $count++
    }

    Write-Verbose ($stopwatch.Elapsed | Out-String) -Verbose
    $stopwatch.Stop()

    Write-Verbose ('Install-CustomModule end') -Verbose
}
