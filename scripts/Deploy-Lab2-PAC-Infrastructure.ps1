# Lab 2 - PAC File Infrastructure Script
# Deploy Azure Storage and PAC file for Azure Firewall Explicit Proxy

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "RG-AFEP-Lab1",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "afepstorage$(Get-Random -Maximum 99999)",
    
    [Parameter(Mandatory=$false)]
    [string]$FirewallPrivateIP = "10.0.0.4"
)

Write-Host "🚀 Starting Lab 2 PAC File Infrastructure Setup..." -ForegroundColor Cyan

# Check and install required modules
Write-Host "`n🔍 Checking required Azure PowerShell modules..." -ForegroundColor Yellow
$requiredModules = @('Az.Storage')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "   Installing $module..." -ForegroundColor Cyan
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $module -ErrorAction Stop
}
Write-Host "✅ All required modules loaded" -ForegroundColor Green

# 1. Get Resource Group
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "❌ Resource Group $ResourceGroupName not found. Run Lab 1 first!" -ForegroundColor Red
    exit
}

# 2. Create Storage Account
Write-Host "`n📦 Creating Storage Account: $StorageAccountName" -ForegroundColor Yellow
$storageAccount = New-AzStorageAccount `
    -ResourceGroupName $ResourceGroupName `
    -Name $StorageAccountName `
    -Location $rg.Location `
    -SkuName Standard_LRS `
    -Kind StorageV2 `
    -AllowBlobPublicAccess $false

Write-Host "✅ Storage Account created" -ForegroundColor Green

# 3. Create Container
Write-Host "`n📁 Creating blob container 'pacfiles'..." -ForegroundColor Yellow
$ctx = $storageAccount.Context
$container = New-AzStorageContainer `
    -Name "pacfiles" `
    -Context $ctx `
    -Permission Off

Write-Host "✅ Container created" -ForegroundColor Green

# 4. Create PAC File
Write-Host "`n📝 Creating PAC file..." -ForegroundColor Yellow
$pacContent = @"
function FindProxyForURL(url, host) {
    // Internal domains go direct (bypass proxy)
    if (dnsDomainIs(host, ".company.com") || 
        dnsDomainIs(host, ".internal.local") ||
        isInNet(host, "10.0.0.0", "255.0.0.0")) {
        return "DIRECT";
    }
    
    // Microsoft services go through proxy
    if (dnsDomainIs(host, ".microsoft.com") || 
        dnsDomainIs(host, ".bing.com")) {
        return "PROXY $FirewallPrivateIP:8080";
    }
    
    // All other traffic goes through proxy
    return "PROXY $FirewallPrivateIP:8080";
}
"@

$pacFile = "$env:TEMP\proxy.pac"
$pacContent | Out-File -FilePath $pacFile -Encoding ASCII -Force

Write-Host "✅ PAC file created locally" -ForegroundColor Green

# 5. Upload PAC File
Write-Host "`n⬆️  Uploading PAC file to blob storage..." -ForegroundColor Yellow

# Get fresh storage account keys and context
$keys = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $keys[0].Value

$blob = Set-AzStorageBlobContent `
    -File $pacFile `
    -Container "pacfiles" `
    -Blob "proxy.pac" `
    -Context $ctx `
    -Force

Write-Host "✅ PAC file uploaded" -ForegroundColor Green

# 6. Generate SAS Token
Write-Host "`n🔑 Generating SAS token (valid for 7 days)..." -ForegroundColor Yellow

# Use UTC time for SAS token
$startTime = (Get-Date).ToUniversalTime()
$expiryTime = $startTime.AddDays(7)

$sasToken = New-AzStorageBlobSASToken `
    -Container "pacfiles" `
    -Blob "proxy.pac" `
    -Permission "r" `
    -StartTime $startTime `
    -ExpiryTime $expiryTime `
    -Context $ctx

$sasUrl = $blob.ICloudBlob.Uri.AbsoluteUri + $sasToken

Write-Host "✅ SAS token generated" -ForegroundColor Green

# Summary
Write-Host "`n" + ("="*80) -ForegroundColor Cyan
Write-Host "🎉 Lab 2 PAC File Infrastructure Setup Complete!" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "`nPAC File Information:" -ForegroundColor Yellow
Write-Host "  Storage Account: $StorageAccountName"
Write-Host "  Container: pacfiles"
Write-Host "  Blob Name: proxy.pac"
Write-Host "  Firewall IP in PAC: $FirewallPrivateIP"
Write-Host "`n🔗 PAC File SAS URL:" -ForegroundColor Yellow
Write-Host "  $sasUrl" -ForegroundColor Cyan
Write-Host "`n⚠️  IMPORTANT: Copy this URL - you'll need it in Step 2!" -ForegroundColor Red
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Configure PAC file in Firewall Policy (see READMEAUTO.md Step 2)"
Write-Host "  2. Configure client to use PAC file (see READMEAUTO.md Step 3)"
Write-Host "  3. Test PAC file configuration (see READMEAUTO.md Step 4)"
Write-Host ("="*80) -ForegroundColor Cyan

# Save info to file
$pacInfo = @{
    StorageAccount = $StorageAccountName
    Container = "pacfiles"
    BlobName = "proxy.pac"
    SASUrl = $sasUrl
    FirewallPrivateIP = $FirewallPrivateIP
    ExpiryDate = (Get-Date).AddDays(7).ToString()
} | ConvertTo-Json

$pacInfo | Out-File -FilePath ".\Lab2-PAC-Info.json" -Force
Write-Host "`n💾 PAC info saved to: Lab2-PAC-Info.json" -ForegroundColor Green
