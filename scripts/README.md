# AFEP Lab Deployment Scripts

This directory contains PowerShell automation scripts for deploying Azure Firewall Explicit Proxy (AFEP) lab environments.

## 📋 Available Scripts

### 1. Deploy-Lab1-Infrastructure.ps1
**Purpose**: Deploy basic AFEP infrastructure with single VNet  
**What it creates**:
- Resource Group (RG-AFEP-Lab1)
- Virtual Network with AzureFirewallSubnet (/26) and ClientSubnet
- Azure Firewall (Standard SKU) with DNS Proxy enabled
- Firewall Policy
- Network Security Group for RDP access
- Windows Server 2022 VM for testing
- All necessary networking components

**Usage**:
```powershell
.\Deploy-Lab1-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force)
```

**Parameters**:
- `AdminPassword` (Required): Secure password for VM admin account
- `Location` (Optional): Azure region, default is "Sweden Central"
- `ResourceGroupName` (Optional): Default is "RG-AFEP-Lab1"

**Deployment Time**: ~10-15 minutes  
**Output**: `Lab1-DeploymentInfo.json` with deployment details

---

### 2. Deploy-Lab2-PAC-Infrastructure.ps1
**Purpose**: Deploy PAC file infrastructure for automatic proxy configuration  
**What it creates**:
- Azure Storage Account
- Blob container for PAC files
- PAC file with proxy routing logic
- 7-day SAS token for secure PAC file access

**Prerequisites**: Lab 1 must be deployed first

**Usage**:
```powershell
.\Deploy-Lab2-PAC-Infrastructure.ps1
```

**Parameters**:
- `ResourceGroupName` (Optional): Default is "RG-AFEP-Lab1"
- `StorageAccountName` (Optional): Auto-generated random name
- `FirewallPrivateIP` (Optional): Default is "10.0.0.4"

**Deployment Time**: ~2-3 minutes  
**Output**: `Lab2-PAC-Info.json` with PAC file URL and SAS token

---

### 3. Deploy-Lab3-HubSpoke-Infrastructure.ps1
**Purpose**: Deploy enterprise hub-and-spoke topology with centralized firewall  
**What it creates**:
- Resource Group (RG-AFEP-HubSpoke)
- Hub VNet (10.0.0.0/16) with AzureFirewallSubnet
- Spoke1 VNet (10.1.0.0/16) for workload 1
- Spoke2 VNet (10.2.0.0/16) for workload 2
- VNet peering between Hub and Spokes
- Azure Firewall Premium in Hub
- Route tables for traffic steering
- Windows Server VMs in both spoke networks

**Usage**:
```powershell
.\Deploy-Lab3-HubSpoke-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force)
```

**Parameters**:
- `AdminPassword` (Required): Secure password for VM admin accounts
- `Location` (Optional): Azure region, default is "Sweden Central"
- `ResourceGroupName` (Optional): Default is "RG-AFEP-HubSpoke"

**Deployment Time**: ~15-20 minutes  
**Output**: `Lab3-DeploymentInfo.json` with deployment details

---

### 4. Cleanup-Labs.ps1
**Purpose**: Remove lab resource groups and all resources  
**What it deletes**:
- Resource groups created during lab exercises
- All resources within those groups

**Usage**:
```powershell
# Delete specific lab
.\Cleanup-Labs.ps1 -Lab Lab1    # Deletes RG-AFEP-Lab1
.\Cleanup-Labs.ps1 -Lab Lab3    # Deletes RG-AFEP-HubSpoke

# Delete all labs
.\Cleanup-Labs.ps1 -Lab All
```

**Parameters**:
- `Lab` (Optional): "Lab1", "Lab2", "Lab3", or "All" (default: "All")

**⚠️ Warning**: This operation cannot be undone. You will be prompted for confirmation.

---

## 🔐 Security Notes

1. **Never commit passwords** to version control
2. Use **Azure Key Vault** for production credentials
3. Update **NSG rules** to restrict RDP access to your specific IP address
4. **SAS tokens expire** after 7 days - regenerate as needed
5. Use **Azure Bastion** for secure VM access in production

---

## 📊 Output Files

Each script generates a JSON file with deployment information:

| Script | Output File | Contains |
|--------|------------|----------|
| Lab 1 | `Lab1-DeploymentInfo.json` | Firewall IPs, VM IPs, Policy ID |
| Lab 2 | `Lab2-PAC-Info.json` | PAC file URL, SAS token, expiry date |
| Lab 3 | `Lab3-DeploymentInfo.json` | Hub-spoke IPs, VM IPs, Policy ID |

**These files are created in the directory where you run the script.**

---

## 🎯 Typical Workflow

### Lab 1 - Basic AFEP
1. Run `Deploy-Lab1-Infrastructure.ps1`
2. Manually configure Explicit Proxy in Azure Portal
3. Create Application Rules
4. Test from client VM
5. Run `Cleanup-Labs.ps1 -Lab Lab1` when done

### Lab 2 - PAC Files (requires Lab 1)
1. Ensure Lab 1 is deployed
2. Run `Deploy-Lab2-PAC-Infrastructure.ps1`
3. Manually configure PAC file in Firewall Policy
4. Configure client to use PAC file
5. Test PAC file routing logic

### Lab 3 - Hub-Spoke Topology (standalone)
1. Run `Deploy-Lab3-HubSpoke-Infrastructure.ps1`
2. Manually configure Explicit Proxy with PAC file
3. Create Application Rules for hub-spoke
4. Configure proxy on spoke VMs
5. Test hub-spoke connectivity
6. Run `Cleanup-Labs.ps1 -Lab Lab3` when done

---

## 🔧 Troubleshooting

### Script fails with "Az module not found"
```powershell
Install-Module -Name Az -Repository PSGallery -Force
```

### Script fails with "Not logged in"
```powershell
Connect-AzAccount
```

### Firewall deployment takes longer than expected
- Azure Firewall deployment typically takes 8-15 minutes
- Check Azure Portal for deployment progress
- Check Activity Log for any errors

### VM deployment fails
- Verify VM SKU is available in your region
- Check subscription quota limits
- Ensure you have permissions to create VMs

---

## 📚 Related Documentation

- [READMEAUTO.md](../READMEAUTO.md) - Automated infrastructure guide with manual AFEP configuration steps
- [README.md](../README.md) - Comprehensive manual guide with detailed explanations

---

## ⚙️ Script Maintenance

**Last Updated**: November 6, 2025  
**Tested With**: 
- Azure PowerShell Az module 11.x
- PowerShell 7.x
- Azure Firewall API version 2023-xx-xx

**Known Issues**: None

---

## 💡 Tips

1. **Save your passwords securely** - Use a password manager
2. **Check deployment info files** - They contain all IPs and IDs you need
3. **Run one lab at a time** - Labs 1 and 3 are independent
4. **Monitor costs** - Stop/deallocate VMs when not in use
5. **Use Azure Advisor** - Review recommendations after deployment
