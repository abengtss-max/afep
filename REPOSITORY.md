# Azure Firewall Explicit Proxy (AFEP) - Lab Environment

Welcome to the **Azure Firewall Explicit Proxy (AFEP) Lab Environment**! This repository provides comprehensive lab exercises to help you master AFEP configuration and deployment.

## 🎯 Purpose

This lab environment is designed for:
- **Azure Landing Zone support engineers** needing hands-on AFEP experience
- **Cloud architects** implementing centralized web proxy solutions
- **Security engineers** managing internet traffic control
- **DevOps teams** deploying hub-spoke network topologies

## 📚 Documentation

This repository contains **TWO guides** - choose the one that fits your learning style:

### 1. 📘 [README.md](README.md) - Comprehensive Manual Guide
**Best for**: Deep learning and understanding every step

**Features**:
- ✅ Detailed explanations of AFEP concepts
- ✅ Step-by-step Azure Portal navigation (exact button clicks)
- ✅ 3 complete labs with 10-13 steps each
- ✅ Best practices validated against Microsoft documentation
- ✅ Troubleshooting guide
- ✅ Configuration validation checklist

**Labs included**:
1. **Lab 1**: Basic AFEP deployment (10 steps, 45-60 minutes)
2. **Lab 2**: PAC file configuration (10 steps, 30-45 minutes)
3. **Lab 3**: Hub-spoke topology (13 steps, 60-90 minutes)

**Time investment**: 2.5-4 hours total for all labs

---

### 2. ⚡ [READMEAUTO.md](READMEAUTO.md) - Automated Infrastructure Guide
**Best for**: Fast deployment with focused AFEP learning

**Features**:
- ✅ Automated PowerShell scripts for infrastructure
- ✅ Focus on AFEP-specific configuration (manual)
- ✅ Same 3 labs with automated setup
- ✅ Deployment info automatically saved to JSON files
- ✅ Quick cleanup scripts

**Labs included**:
1. **Lab 1**: Basic AFEP (20-30 minutes with automation)
2. **Lab 2**: PAC files (15-25 minutes with automation)
3. **Lab 3**: Hub-spoke (30-45 minutes with automation)

**Time investment**: 1-2 hours total for all labs

---

## 🚀 Quick Start

### Choose Your Learning Path

**Path A: Manual (Comprehensive Learning)**
```powershell
# Read README.md and follow step-by-step
# You'll manually create everything in Azure Portal
# Best for: First-time AFEP users
```

**Path B: Automated (Fast Learning)**
```powershell
# 1. Clone this repository
git clone https://github.com/abengtss-max/azfw.git
cd azfw

# 2. Install Azure PowerShell
Install-Module -Name Az -Repository PSGallery -Force

# 3. Connect to Azure
Connect-AzAccount

# 4. Run Lab 1 automation script
cd scripts
.\Deploy-Lab1-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force)

# 5. Follow READMEAUTO.md for manual AFEP configuration
```

---

## 📂 Repository Structure

```
azfw/
├── README.md                           # Comprehensive manual guide
├── READMEAUTO.md                       # Automated infrastructure guide
├── REPOSITORY.md                       # This file - repository overview
└── scripts/                            # PowerShell automation scripts
    ├── README.md                       # Scripts documentation
    ├── Deploy-Lab1-Infrastructure.ps1  # Lab 1 infrastructure
    ├── Deploy-Lab2-PAC-Infrastructure.ps1  # Lab 2 PAC files
    ├── Deploy-Lab3-HubSpoke-Infrastructure.ps1  # Lab 3 hub-spoke
    └── Cleanup-Labs.ps1                # Resource cleanup
```

---

## 🎓 What You'll Learn

### Core AFEP Concepts
- ✅ Enabling Explicit Proxy on Azure Firewall
- ✅ Configuring HTTP/HTTPS proxy ports
- ✅ Creating Application Rules (not network rules!)
- ✅ PAC file generation and hosting
- ✅ Client proxy configuration
- ✅ Testing and validation techniques

### Advanced Topics
- ✅ Hub-and-spoke topology with centralized firewall
- ✅ VNet peering and route tables
- ✅ Dynamic proxy routing with PAC files
- ✅ Azure Monitor log analysis
- ✅ Security best practices
- ✅ High availability and disaster recovery

---

## ⚙️ Prerequisites

### Required
- **Azure Subscription** with Contributor or Owner permissions
- **PowerShell 7.x** or Windows PowerShell 5.1
- **Azure PowerShell Module** (Az 11.x or later)
- **Internet connection** to download resources

### Recommended
- **Azure Portal** access
- **RDP client** to connect to VMs
- **Basic Azure networking** knowledge
- **30-60 minutes** of focused time per lab

---

## 💰 Cost Considerations

**Estimated costs per lab** (Sweden Central region):

| Resource | Estimated Cost/Hour | Lab Duration |
|----------|-------------------|--------------|
| Azure Firewall Standard | ~$1.25/hour | 1-2 hours |
| Azure Firewall Premium | ~$1.85/hour | 1-2 hours |
| Virtual Machines (B2s) | ~$0.05/hour each | 1-2 hours |
| Storage Account | ~$0.01/day | 1 day |

**Total estimated cost**: $3-8 per lab session

**💡 Cost-saving tips**:
- Delete resources immediately after labs (`Cleanup-Labs.ps1`)
- Use Azure Firewall Standard for Labs 1-2 (cheaper)
- Stop/deallocate VMs when not actively testing
- Schedule your learning sessions back-to-back

---

## 🛡️ Security Warnings

⚠️ **IMPORTANT - READ BEFORE DEPLOYING**:

1. **This is for LAB/TESTING ONLY** - Not production-ready
2. **NSG rules allow RDP from ANY source** - Restrict to your IP in production
3. **Passwords are passed via command line** - Use Key Vault in production
4. **Public IPs are assigned to all VMs** - Use Azure Bastion in production
5. **No TLS inspection configured** - Add for production HTTPS filtering
6. **SAS tokens expire in 7 days** - Implement proper secret management

**Never deploy these labs in production environments without proper security hardening!**

---

## 🔧 Troubleshooting

### Common Issues

**Issue**: Script fails with "Az module not found"
```powershell
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber
```

**Issue**: Script fails with "Not logged in"
```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

**Issue**: Firewall deployment takes too long
- **Normal**: Azure Firewall takes 8-15 minutes to deploy
- Check Azure Portal → Resource Groups → Deployments for progress

**Issue**: Can't RDP to VM
- Verify NSG allows port 3389 from your IP
- Check VM is running in Azure Portal
- Verify public IP address is assigned

**Issue**: Proxy not working
- Verify Explicit Proxy is enabled in Firewall Policy
- Check Application Rules are configured (not Network Rules)
- Verify client proxy settings point to Firewall Private IP

For more troubleshooting, see the **Troubleshooting** sections in README.md or READMEAUTO.md.

---

## 📖 Additional Resources

### Official Microsoft Documentation
- [Azure Firewall Explicit Proxy](https://learn.microsoft.com/azure/firewall/explicit-proxy)
- [Azure Firewall Premium features](https://learn.microsoft.com/azure/firewall/premium-features)
- [Hub-spoke network topology](https://learn.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)

### Related Azure Services
- [Azure Firewall documentation](https://learn.microsoft.com/azure/firewall/)
- [Azure Monitor documentation](https://learn.microsoft.com/azure/azure-monitor/)
- [Azure Virtual Network documentation](https://learn.microsoft.com/azure/virtual-network/)

---

## 🤝 Contributing

Found an issue or want to improve the labs? Contributions are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Nov 6, 2025 | Initial release with 3 labs and automation scripts |

---

## 📄 License

This project is provided as-is for educational purposes. Use at your own risk.

---

## 🙋 Support

**For lab-related questions**:
- Review the README.md or READMEAUTO.md documentation
- Check the Troubleshooting sections
- Review Azure Firewall logs in Azure Monitor

**For Azure Firewall product questions**:
- Visit [Microsoft Q&A](https://learn.microsoft.com/answers/)
- Open an Azure Support ticket
- Check [Azure Firewall documentation](https://learn.microsoft.com/azure/firewall/)

---

## 🎯 Next Steps

Ready to start? Choose your path:

1. **📘 Manual Path**: Open [README.md](README.md) and start with Lab 1
2. **⚡ Automated Path**: Open [READMEAUTO.md](READMEAUTO.md) and run the first script

**Good luck with your AFEP learning journey!** 🚀

---

**Document Version**: 1.0  
**Last Updated**: November 6, 2025  
**Repository**: https://github.com/abengtss-max/azfw
