# Replace with your HubSpot API token and table ID/name
$apiToken = ""
$tableIdOrName = "6814391"
$endpoint = "https://api.hubapi.com/cms/v3/hubdb/tables/$tableIdOrName/export"

# Set output file name
$outputFile = "hubdb_export.csv"

# Download HubDB export using Invoke-WebRequest
Invoke-WebRequest -Uri $endpoint -Headers @{ "Authorization" = "Bearer $apiToken" } -OutFile $outputFile
