# SOLUTION: Fix Hyper-V Connectivity Issues

## 🎯 **Your Problem - Solved**

**Issue:** Creating Internal and External Hyper-V switches causes permanent WiFi/Ethernet connectivity loss.

**Root Cause:** External switches take over your physical network adapter, breaking your host connectivity.

**Solution:** Use Hyper-V's built-in **Default Switch (NAT)** instead of External switches.

---

## ✅ **Immediate Fix - Run This Script**

**Execute as Administrator:**

```powershell
# Navigate to your project folder
cd <path-to-azfw-folder>

# Run the connectivity fix script
.\Fix-HyperV-Connectivity.ps1
```

**What this script does:**
1. ✅ **Removes problematic External switches** (restores WiFi)
2. ✅ **Creates/verifies NAT switch** (internet for VMs)  
3. ✅ **Creates/verifies Internal-Lab switch** (VM-to-VM network)
4. ✅ **Configures VM network adapters** (proper connectivity)
5. ✅ **Preserves your host WiFi/Ethernet** (no disruption)

---

## 🌐 **Final Network Architecture**

After running the fix script, you'll have:

```
Your Windows 11 PC
├── WiFi/Ethernet → Internet (✅ WORKING - unaffected!)
│
└── Hyper-V Host
    ├── Default Switch (NAT) → Provides internet to OPNsense WAN
    ├── Internal-Lab Switch → Isolated VM network (10.0.1.0/24)
    │
    ├── OPNsense Firewall VM
    │   ├── WAN NIC → Default Switch (gets internet via NAT)
    │   ├── LAN NIC → Internal-Lab (10.0.1.1/24)
    │   ├── ✅ Can establish VPN to Azure (has internet)
    │   └── ✅ Provides firewall/filtering for Windows Server
    │
    └── Windows Server VM  
        ├── NIC → Internal-Lab (10.0.1.10/24)
        ├── Gateway → OPNsense (10.0.1.1)
        ├── ❌ NO direct internet access (proper security)
        └── ✅ All traffic → OPNsense → VPN → Azure
```

---

## 🚀 **After Running the Fix**

**1. Verify Host Connectivity:**
```powershell
# Test your WiFi/Ethernet still works
Test-NetConnection google.com
# Should succeed ✅
```

**2. Start Your VMs:**
```powershell  
# Start both VMs
Start-VM "OPNsense-Lab"
Start-VM "ArcServer-Lab"
```

**3. Continue with Lab Setup:**
- OPNsense will now have internet access (via NAT) for VPN
- Windows Server remains isolated (security requirement)
- Complete enterprise simulation works perfectly

---

## 🔒 **Security Benefits Maintained**

✅ **Proper enterprise simulation:**
- Windows Server has NO direct internet access
- All traffic must go through OPNsense firewall  
- VPN tunnel required to reach Azure resources
- Firewall rules control exactly what's allowed

✅ **Your host PC unaffected:**
- WiFi/Ethernet works normally
- No network adapter binding issues
- No performance impact on host

---

## 💡 **Why This Approach Works**

**Traditional Problem:**
- External Switch = Binds to physical network adapter
- Result = Host loses network connectivity 😞

**Our Solution:**  
- Default Switch (NAT) = Hyper-V provides internet via NAT
- Internal Switch = VM-to-VM communication only
- Result = Host connectivity preserved + VMs get proper network access 😊

**Enterprise Authenticity:**
- Still simulates real datacenter (firewall + isolated servers)
- VPN tunnel works (OPNsense has internet via NAT)
- Security model correct (servers don't have direct internet)

---

This solution gives you **both connectivity AND the complete lab experience** without compromising your host system's network functionality!