# Cleanup Script for AFEP Labs
# Removes resource groups created during lab exercises

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Lab1", "Lab2", "Lab3", "All")]
    [string]$Lab = "All"
)

Write-Host "🧹 AFEP Lab Cleanup Script" -ForegroundColor Cyan
Write-Host ("="*80) -ForegroundColor Cyan

$resourceGroups = @()

switch ($Lab) {
    "Lab1" {
        $resourceGroups += "RG-AFEP-Lab1"
    }
    "Lab2" {
        # Lab 2 uses Lab 1 resource group
        $resourceGroups += "RG-AFEP-Lab1"
    }
    "Lab3" {
        $resourceGroups += "RG-AFEP-HubSpoke"
    }
    "All" {
        $resourceGroups += "RG-AFEP-Lab1"
        $resourceGroups += "RG-AFEP-HubSpoke"
    }
}

Write-Host "`n⚠️  WARNING: This will delete the following resource groups:" -ForegroundColor Yellow
foreach ($rg in $resourceGroups) {
    Write-Host "  - $rg" -ForegroundColor Red
}

$confirmation = Read-Host "`nAre you sure you want to proceed? (yes/no)"

if ($confirmation -ne "yes") {
    Write-Host "`n❌ Cleanup cancelled." -ForegroundColor Yellow
    exit
}

Write-Host "`n🗑️  Starting cleanup..." -ForegroundColor Yellow

foreach ($rgName in $resourceGroups) {
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    
    if ($rg) {
        Write-Host "`nDeleting resource group: $rgName" -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $rgName -Force -AsJob | Out-Null
        Write-Host "✅ Deletion job started for $rgName (running in background)" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Resource group not found: $rgName (may already be deleted)" -ForegroundColor Yellow
    }
}

Write-Host "`n" + ("="*80) -ForegroundColor Cyan
Write-Host "✅ Cleanup jobs started!" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "`n💡 Note: Resource group deletion runs in the background and may take 5-10 minutes." -ForegroundColor Cyan
Write-Host "   You can check the status in the Azure Portal or run:" -ForegroundColor Cyan
Write-Host "   Get-AzResourceGroup | Where-Object { `$_.ResourceGroupName -like 'RG-AFEP-*' }" -ForegroundColor White
Write-Host ""
