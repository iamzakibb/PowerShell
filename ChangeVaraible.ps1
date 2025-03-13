$pat = ""
$orgname= ""
$projectName = ""
$authHeader = @{Authorization = "Bearer $pat"}
$projectID  = "ba259a5c-a105-49a5-a371-cf83d0abbfbc"

$body = @{
      description = "Variable Group"
      name = "Sys_id"
      type = "Vsts"
      variables = @{
         sys_id  = @{
             isSecret = "false"
             isReadOnly = "false"
             value = "2" 
           }
         }
      variableGroupProjectReferences = @(
               @{
                     name = "Sys_id"
                     description = "Varaible Group"
                     projectReference = @{
                          id = $projectID
                          name = $projectName
                      }
                  }
              )
 }| ConvertTo-Json -Depth 10


Invoke-RestMethod -Uri "https://tfs.clev.frb.org/$orgname/$projectName/_apis/distributedtask/variablegroups/183?api-version=7.2-preview.2" -Method Put -Body $body -Headers $authHeader -ContentType "application/json"