# ------------------------------------------
# Azure DevOps Variable Group Update Script
# ------------------------------------------

# Define Variables
$organization      = "yasirmushtaq7"           # Your Azure DevOps organization
$project           = "yasir_mushtaq7"            # Your project name
$variableGroupId   = "2"                     # The Variable Group ID to update
$variableGroupName = "Sys_id"                   # The name of the Variable Group
$description       = "Group Variables"         # Description for the Variable Group
$variableName      = "sys_id"                  # Name of the variable to add/update
$newValue          = "UpdatedValue"            # The new value for the variable
$projectID         = "ba259a5c-a105-49a5-a371-cf83d0abbfbc"         # Your project's GUID (update this!)
$pat             = "3izhbKBUHwjQssuKzJ8TKj69VTS3YrUHeaESbwkBw6PWiQxqZBnwJQQJ99BCACAAAAAAAAAAAAASAZDO2JvU"  # Your Personal Access Token

# Build Authentication Header (using Bearer token as in your sample)
$authHeader = @{ Authorization = "Bearer $pat" }

# Construct the JSON payload
$body = @{
    description = $description
    name        = $variableGroupName
    type        = "Vsts"
    variables   = @{
        $variableName = @{
            isSecret   = $false
            isReadOnly = $false
            value      = $newValue
        }
    }
    variableGroupProjectReferences = @(
        @{
            name        = $variableGroupName
            description = $description
            projectReference = @{
                id   = $projectID
                name = $project
            }
        }
    )
} | ConvertTo-Json -Depth 10

# Build the API URL (note: the URL includes both organization and project)
$uri = "https://dev.azure.com/$organization/$project/_apis/distributedtask/variablegroups/2?api-version=7.1"

# Execute the PUT request to update the variable group
Invoke-RestMethod -Uri $uri -Method Put -Body $body -Headers $authHeader -ContentType "application/json"
