# Replace with your HubSpot API token and table ID/name
$apiToken = "pat-na1-167a2bc3-2417-41e1-a8a0-c55f7f12b2bf"
$tableIdOrName = "6814391"
$endpoint = "https://api.hubapi.com/cms/v3/hubdb/tables/$tableIdOrName/export"

# Set output file name
$outputFile = "hubdb_export.csv"

# Download HubDB export using Invoke-WebRequest
Invoke-WebRequest -Uri $endpoint -Headers @{ "Authorization" = "Bearer $apiToken" } -OutFile $outputFile
