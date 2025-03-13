# ------------------------------------------
# Azure DevOps Variable Group Update Script
# ------------------------------------------

# Define Variables
$organization      = "yasirmushtaq7"           # Your Azure DevOps organization
$project           = "yasir_mushtaq7"            # Your project name
$variableGroupId   = "2"                       # The Variable Group ID to update
$variableGroupName = "Group"                   # The name of the Variable Group
$description       = "Group Variables"         # Description for the Variable Group
$variableName      = "MY_VAR"                  # Name of the variable to add/update
$newValue          = "UpdatedValue"            # The new value for the variable
$projectID         = "YOUR_PROJECT_ID"         # Your project's GUID (update this!)
$pat               = "YOUR_PERSONAL_ACCESS_TOKEN"  # Your Personal Access Token

# Build Authentication Header (using Bearer token as in your sample)
$authHeader = @{ Authorization = "Bearer $pat" }

# Construct the JSON payload
$body = @{
    description = $description
    name        = $variableGroupName
    type        = "Vsts"
    variables   = @{
        $variableName = @{
            isSecret   = "false"
            isReadOnly = "false"
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
$uri = "https://dev.azure.com/$organization/$project/_apis/distributedtask/variablegroups/$variableGroupId?api-version=7.2-preview.2"

# Execute the PUT request to update the variable group
Invoke-RestMethod -Uri $uri -Method Put -Body $body -Headers $authHeader -ContentType "application/json"
