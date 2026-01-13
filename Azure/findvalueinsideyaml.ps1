# Root config path
$configPath = "C:\Users\<username>\Desktop\repo\<repo_name>\<stamp>\<Applications>"

# Get all YAML files
$files = Get-ChildItem -Path $configPath -Recurse -Filter "*.yml" -File

function Get-YAMLValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $regex = "(?m)^\s*${Key}:\s*['""]?(.+?)['""]?\s*$"
    if ($Content -match $regex) {
        return $Matches[1].Trim()
    }

    return $null
}

$result = foreach ($file in $files) {

    $content = Get-Content -Path $file.FullName -Raw

    # Normalize path and split safely
    $relativePath = $file.FullName.Replace($configPath, "").TrimStart("\")
    $parts = $relativePath -split "\\"

    # Expected structure: <stamp>\<env>\Applications\<app>.yml
    $stamp = $parts[0]
    $env   = $parts[1]

    [PSCustomObject]@{
        Stamp              = $stamp
        Environment        = $env
        Application        = Get-YAMLValue -Content $content -Key "name"
        LOB                = Get-YAMLValue -Content $content -Key "lob_name"
        AdminGroupName     = Get-YAMLValue -Content $content -Key "admin_group_name"
        ReaderGroupName    = Get-YAMLValue -Content $content -Key "reader_group_name"
        DeveloperGroupName = Get-YAMLValue -Content $content -Key "developer_group_name"
        FilePath           = $file.FullName
    }
}

$result |
    Sort-Object Stamp, Environment, Application |
    Export-Csv -Path "C:\NewFolder\edai-groups-export.csv" -NoTypeInformation -Encoding UTF8
