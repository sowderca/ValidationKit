#requires -Version 5

Import-Module 'OperationValidation';

# Report colored output
$script:theme = data {
    @{
        Pass = 'Green'
        Fail = 'Red'
        Inconclusive = 'Yellow'
        Incomplete = 'Magenta'
    }
};

# Status symobls for test results. ** NOTE: only supported on Windows 10+ without a terminal emulater ( cmder, hyper, mobx, putty...) **
[char] $check = '✔';
[char] $x = '✖';
[char] $caution = '⚠';
[char] $info = 'ℹ';

function Write-ValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $ValidationResult
    )
    begin {
        Write-Verbose -Message 'Processing validation test results...';
    } process {
        switch ($ValidationResult.Result) {
            Passed {
                Write-Host "[$($check)] $($ValidationResult.Result) $($ValidationResult.Name)" -ForegroundColor $script:theme.Pass;
                break;
            }
            Failed {
                Write-Host "[$($x)] $($ValidationResult.Result) $($ValidationResult.Name)" -ForegroundColor $script:theme.Fail;
                break;
            }
            Inconclusive {
                Write-Host "[$($caution)] $($ValidationResult.Result) $($ValidationResult.Name)" -ForegroundColor $script:theme.Inconclusive;
            }
            default {
                if ($ValidationResult.Raw.Time -eq $null) {
                    Write-Host "[$($info)] $($ValidationResult.Result) $($ValidationResult.Name)" -ForegroundColor $script:theme.Incomplete;
                }
            }
        }
    } end {
        Write-Verbose -Message 'Validation processing complete!';
    }
};

function Convert-PackageSpecToManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Path = "$($env:ChocolateyInstall)\lib"
    )
    [System.IO.FileInfo[]] $packages = Get-ChildItem -Path $Path -Recurse -Depth 1 | Where-Object { $_.Extension -eq '.nuspec' };
    [string[]] $options = ((Get-Help -Name 'New-ModuleManifest').parameters.parameter | ForEach-Object { $_.Name });
    foreach ($package in $packages) {
        [System.Xml.XmlElement] $packageSpec = (Select-Xml -Path $package.FullName -XPath '*').Node.metadata;
        $params = @{
            Path = $package.FullName.Replace('.nuspec', '.psd1')
        }
        [Microsoft.PowerShell.Commands.MemberDefinition[]] $properties = ($packageSpec | Get-Member -MemberType Property);
        foreach ($option in $options) {
            if ($properties | ForEach-Object { $_.Name -like "*$($option)*" }) {
                [Microsoft.PowerShell.Commands.MemberDefinition] $property = ($properties | Where-Object { $_.Name -like "*$($option)*" });
                if ($packageSpec.($property.Name)) {
                    $params.Add($option, $packageSpec.($property.Name));
                }
            }
        }
        New-ModuleManifest @params;
    }

};

function Remove-PackageManifests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Path = "$($env:ChocolateyInstall)\lib"
    )
    Get-ChildItem -Path $Path -Recurse -Depth 1 | Where-Object { $_.Extension -eq '.psd1' } | Remove-Item -Force;
};

function Test-SystemData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Path = "$($env:ChocolateyInstall)\lib",
        [Parameter(Mandatory = $false)]
        [switch] $IncludePesterOutput,
        [Parameter(Mandatory = $false)]
        [switch] $IncludeReport
    )
    Convert-PackageSpecToManifest -Path $Path;
    $testResults = Invoke-OperationValidation -LiteralPath $Path -IncludePesterOutput:$IncludePesterOutput;
    Remove-PackageManifests -Path $Path;
    if ($IncludeReport.IsPresent) {
        return $testResults;
    } else {
        $testResults | Write-ValidationResults;
    }
};
