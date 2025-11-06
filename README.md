# Azure Firewall Explicit Proxy (AFEP) – Complete Guide

## Introduction in Simple Terms

Azure Firewall Explicit Proxy (AFEP) acts like a checkpoint for internet traffic in Azure. Instead of letting servers and apps go straight to the internet, AFEP makes them send traffic through Azure Firewall first, giving you control and visibility.

### Why AFEP?

- **Better control**: Decide which websites or services are allowed.
- **Security**: Block risky traffic and keep logs for audits.
- **Simpler management**: No need for complex routing tables everywhere.
- **Scalable**: Works well in large environments with many networks.

### Important Notes

⚠️ **Azure Firewall Explicit Proxy is currently in Public Preview**  
⚠️ **AzureFirewallSubnet must be exactly /26** (64 IP addresses) - This is mandatory for proper scaling  
⚠️ **Application rules must be used** - Network rules will not work with explicit proxy  
⚠️ **HTTP and HTTPS ports cannot be the same**

---

## PAC Files – Dynamic Proxy Routing

PAC files are scripts that tell apps when to use the proxy and when to go direct.

**Example:**
```javascript
function FindProxyForURL(url, host) {
    if (dnsDomainIs(host, ".company.com")) return "DIRECT";
    return "PROXY 10.0.1.4:8080";
}
```

**Benefits:**
- Route internal traffic directly.
- Send external traffic through the proxy.
- Update rules centrally without touching every device.

---

## LABS

### ✅ Lab 1: Basic Explicit Proxy Deployment

**Goal**: Deploy Azure Firewall with AFEP and test basic web traffic.

**Estimated Time**: 45-60 minutes

#### Step 1: Create Resource Group

1. Sign in to the [Azure Portal](https://portal.azure.com)
2. In the top search bar, type **Resource groups**
3. Click **Resource groups** from the results
4. Click **+ Create** button (top left)
5. Fill in the following:
   - **Subscription**: Select your subscription
   - **Resource group**: `RG-AFEP-Lab1`
   - **Region**: `Sweden Central`
6. Click **Review + create** button (bottom left)
7. Click **Create** button
8. Wait for "Deployment complete" message (~5 seconds)

#### Step 2: Create Virtual Network

1. In the Azure Portal search bar, type **Virtual networks**
2. Click **Virtual networks** from the results
3. Click **+ Create** button (top left)
4. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-Lab1`
   - **Virtual network name**: `VNet-Lab1`
   - **Region**: `Sweden Central`
5. Click **Next: IP Addresses** button (bottom)
6. On the **IP Addresses** tab:
   - **IPv4 address space**: Verify it shows `10.0.0.0/16`
   - Click **default** subnet to edit it
7. On the **Edit subnet** pane (right side):
   - **Subnet purpose**: Select **Azure Firewall** from dropdown
   - **Starting address**: Will auto-populate to `10.0.0.0`
   - **Subnet size**: Verify it shows **/26** (64 addresses) - **This is mandatory**
   - Click **Save** button (bottom of pane)
8. Click **+ Add a subnet** button:
   - **Subnet template**: Select **Default**
   - **Name**: `ClientSubnet`
   - **Starting address**: `10.0.2.0`
   - **Subnet size**: Select **/24** (256 addresses)
   - Click **Add** button
9. Click **Review + create** button (bottom)
10. Click **Create** button
11. Wait for "Deployment complete" message (~1 minute)

#### Step 3: Create Public IP Address for Firewall

1. In the Azure Portal search bar, type **Public IP addresses**
2. Click **Public IP addresses** from the results
3. Click **+ Create** button (top left)
4. Fill in the following:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-Lab1`
   - **Region**: `Sweden Central`
   - **Name**: `pip-firewall-lab1`
   - **SKU**: Select **Standard** (required for Azure Firewall)
   - **Tier**: Select **Regional**
   - **Assignment**: **Static** (auto-selected)
5. Click **Review + create** button (bottom)
6. Click **Create** button
7. Wait for "Deployment complete" message (~10 seconds)

#### Step 4: Deploy Azure Firewall

1. In the Azure Portal search bar, type **Firewalls**
2. Click **Firewalls** from the results
3. Click **+ Create** button (top left)
4. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-Lab1`
   - **Name**: `afw-lab1`
   - **Region**: `Sweden Central`
   - **Availability zones**: Leave blank (for simplicity in lab)
   - **Firewall SKU**: Select **Standard** (Premium supports TLS inspection)
   - **Firewall management**: Select **Use a Firewall Policy to manage this firewall**
   - **Firewall policy**: Click **Add new**
     - **Policy name**: `afp-lab1`
     - **Region**: `Sweden Central`
     - **Policy tier**: **Standard**
     - Click **OK**
   - **Virtual network**: Select **Use existing**
   - Click the dropdown and select `VNet-Lab1`
   - **Public IP address**: Select **Use existing**
   - Click the dropdown and select `pip-firewall-lab1`
5. Click **Review + create** button (bottom)
6. Click **Create** button
7. **Wait 5-10 minutes** for deployment to complete
8. When complete, click **Go to resource** button

#### Step 5: Enable Explicit Proxy on Firewall Policy

1. From your firewall resource page, under **Settings**, click **Firewall Policy**
2. Click on the policy name link `afp-lab1`
3. In the left menu under **Settings**, click **Explicit Proxy (Preview)**
4. Click the **Enable Explicit Proxy** toggle switch to ON
5. Configure the ports:
   - **HTTP Port**: `8080` (standard HTTP proxy port)
   - **HTTPS Port**: `8443` (standard HTTPS proxy port)
   - ⚠️ **Important**: HTTP and HTTPS ports CANNOT be the same
6. Leave **Enable proxy auto-configuration** unchecked (we'll do this in Lab 2)
7. Click **Apply** button (top of page)
8. Wait for "Update succeeded" notification (~30 seconds)

#### Step 6: Create Application Rule Collection

⚠️ **Critical**: You MUST use Application Rules, not Network Rules, for explicit proxy

1. From the Firewall Policy page (`afp-lab1`), under **Settings**, click **Application Rules**
2. Click **+ Add a rule collection** button
3. Fill in the **Rule collection** settings:
   - **Name**: `AllowWebTraffic`
   - **Rule collection type**: **Application**
   - **Priority**: `200` (lower number = higher priority)
   - **Rule collection action**: **Allow**
   - **Rule collection group**: Select **DefaultApplicationRuleCollectionGroup**
4. Under **Rules**, add first rule:
   - **Name**: `AllowMicrosoft`
   - **Source type**: **IP Address**
   - **Source**: `*` (or specific subnet like `10.0.2.0/24`)
   - **Protocol**: `http:80,https:443`
   - **Destination type**: **FQDN**
   - **Destination**: `*.microsoft.com`
5. Click **Add** button to add another rule:
   - **Name**: `AllowBing`
   - **Source type**: **IP Address**
   - **Source**: `*`
   - **Protocol**: `http:80,https:443`
   - **Destination type**: **FQDN**
   - **Destination**: `www.bing.com`
6. Click **Add** button to add another rule:
   - **Name**: `AllowTestSites`
   - **Source type**: **IP Address**
   - **Source**: `*`
   - **Protocol**: `http:80,https:443`
   - **Destination type**: **FQDN**
   - **Destination**: `www.example.com,httpbin.org`
7. Click **Add** button (bottom of page)
8. Wait for "Successfully added rule collection" (~1-2 minutes)

#### Step 7: Deploy Client VM

1. In the Azure Portal search bar, type **Virtual machines**
2. Click **Virtual machines** from the results
3. Click **+ Create** → **Azure virtual machine**
4. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-Lab1`
   - **Virtual machine name**: `vm-client-lab1`
   - **Region**: `Sweden Central`
   - **Availability options**: **No infrastructure redundancy required**
   - **Image**: **Windows Server 2022 Datacenter: Azure Edition - x64 Gen2**
   - **Size**: Click **See all sizes** → Search for **B2s** → Select **Standard_B2s** → Click **Select**
   - **Username**: `azureadmin`
   - **Password**: Enter a strong password (save this!)
   - **Confirm password**: Re-enter password
   - **Public inbound ports**: **Allow selected ports**
   - **Select inbound ports**: Check **RDP (3389)**
5. Click **Networking** tab (top)
6. On the **Networking** tab:
   - **Virtual network**: Select `VNet-Lab1`
   - **Subnet**: Select `ClientSubnet (10.0.2.0/24)`
   - **Public IP**: **(new) vm-client-lab1-ip** (auto-created)
   - **NIC network security group**: **Basic**
   - **Public inbound ports**: **Allow selected ports**
   - **Select inbound ports**: **RDP (3389)**
7. Click **Review + create** button (bottom)
8. Click **Create** button
9. **Wait 3-5 minutes** for VM deployment to complete
10. When complete, click **Go to resource** button
11. **Copy the Public IP address** from the Overview page (you'll need this for RDP)

#### Step 8: Configure Proxy Settings on Client VM

1. **Connect to VM via RDP**:
   - Open **Remote Desktop Connection** on your local computer
   - Enter the **Public IP address** you copied
   - Click **Connect**
   - Enter username: `azureadmin`
   - Enter the password you created
   - Click **OK**
   - Accept certificate warning if prompted

2. **Configure Windows Proxy Settings** (on the VM):
   - Press **Windows key + I** to open Settings
   - Click **Network & Internet** (left menu)
   - Scroll down and click **Proxy** (left menu)
   - Under **Manual proxy setup**:
     - Toggle **Use a proxy server** to **ON**
     - **Address**: Enter the **Firewall Private IP** (find this in Azure Portal → Firewall → Overview → Private IP)
       - It should be `10.0.0.4` (first usable IP in AzureFirewallSubnet)
     - **Port**: `8080`
     - Check **Don't use the proxy server for local (intranet) addresses**
     - Click **Save** button

3. **Alternative: Configure using PowerShell** (on the VM):
   - Open **PowerShell as Administrator**
   - Run:
     ```powershell
     netsh winhttp set proxy proxy-server="10.0.0.4:8080" bypass-list="<local>"
     ```
   - Verify:
     ```powershell
     netsh winhttp show proxy
     ```

#### Step 9: Test the Configuration

1. **On the Client VM**, open **Microsoft Edge** or **Internet Explorer**
2. Navigate to `http://www.bing.com`
   - ✅ **Expected**: Page loads successfully (allowed by firewall rule)
3. Navigate to `https://www.microsoft.com`
   - ✅ **Expected**: Page loads successfully (allowed by firewall rule)
4. Navigate to `http://www.google.com`
   - ❌ **Expected**: Connection fails (not allowed by firewall rules)

#### Step 10: Verify in Azure Monitor Logs

1. In Azure Portal, go to your Firewall resource (`afw-lab1`)
2. Under **Monitoring**, click **Logs**
3. Close the "Queries" popup if it appears
4. In the query window, paste:
   ```kusto
   AzureDiagnostics
   | where Category == "AzureFirewallApplicationRule"
   | where TimeGenerated > ago(30m)
   | project TimeGenerated, msg_s, SourceIp = split(msg_s, " ")[3], DestinationUrl = split(msg_s, " ")[7], Action = split(msg_s, " ")[11]
   | order by TimeGenerated desc
   ```
5. Click **Run** button
6. Review the logs showing allowed/denied traffic

---

### ✅ Lab 2: PAC File Configuration (Detailed Steps)

**Goal**: Automate proxy settings using PAC file hosted in Azure Storage.

**Estimated Time**: 30-45 minutes

**Prerequisites**: Complete Lab 1

#### Step 1: Create Storage Account

1. In the Azure Portal search bar, type **Storage accounts**
2. Click **Storage accounts** from the results
3. Click **+ Create** button (top left)
4. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-Lab1`
   - **Storage account name**: `afepstorage` + random characters (must be globally unique)
     - Example: `afepstorage12345` (only lowercase letters and numbers, no hyphens)
   - **Region**: `Sweden Central`
   - **Performance**: **Standard**
   - **Redundancy**: **Locally-redundant storage (LRS)** (sufficient for lab)
5. Click **Next: Advanced** button (bottom)
6. On the **Advanced** tab:
   - **Allow enabling public access on containers**: Check this box (for testing)
   - Leave other settings as default
7. Click **Review + create** button (bottom)
8. Click **Create** button
9. Wait for "Deployment complete" message (~1-2 minutes)
10. Click **Go to resource** button

#### Step 2: Create Blob Container

1. From your Storage Account page, in the left menu under **Data storage**, click **Containers**
2. Click **+ Container** button (top left)
3. On the **New container** pane (right side):
   - **Name**: `pacfiles` (must be lowercase)
   - **Public access level**: **Private (no anonymous access)** (we'll use SAS token)
4. Click **Create** button
5. Wait for container to appear in the list (~5 seconds)

#### Step 3: Create PAC File

1. **On your local computer**, open **Notepad** or any text editor
2. Copy and paste the following PAC file content:
   ```javascript
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
           return "PROXY 10.0.0.4:8080";
       }
       
       // All other traffic goes through proxy
       return "PROXY 10.0.0.4:8080";
   }
   ```
3. **Important**: Replace `10.0.0.4` with your actual Firewall Private IP if different
4. Save the file as:
   - **File name**: `proxy.pac`
   - **Save as type**: **All Files**
   - **Encoding**: **ANSI** or **UTF-8**
5. Save to your desktop or downloads folder

#### Step 4: Upload PAC File to Storage

1. In Azure Portal, go back to your Storage Account (`afepstorage...`)
2. Under **Data storage**, click **Containers**
3. Click on the **pacfiles** container name
4. Click **Upload** button (top left)
5. On the **Upload blob** pane (right side):
   - Click **Browse for files** or drag-and-drop
   - Select your **proxy.pac** file
   - **Blob type**: **Block blob** (default)
   - **Block size**: Leave default
6. Click **Upload** button (bottom of pane)
7. Wait for "Successfully uploaded" notification
8. Click **Close** button (top right of pane)
9. Verify `proxy.pac` appears in the blob list

#### Step 5: Generate SAS Token for PAC File

⚠️ **Important**: SAS token must have READ permissions only

1. In the **pacfiles** container, find the **proxy.pac** file
2. Click the **three dots (...)** on the right side of the proxy.pac row
3. Click **Generate SAS** from the dropdown menu
4. On the **Generate SAS** pane (right side):
   - **Signing method**: Select **Account key** (creates a service SAS)
   - **Signing key**: Select **key1**
   - **Permissions**: Check **Read** only (uncheck all others)
   - **Start date/time**: Leave as current date/time
   - **Expiry date/time**: Set to **7 days from now** (or longer for production)
     - Click the calendar icon
     - Select a date 7 days in the future
     - Set time (e.g., 23:59:59)
   - **Allowed protocols**: **HTTPS only** (recommended)
5. Click **Generate SAS token and URL** button (bottom)
6. **Copy the entire Blob SAS URL** (bottom field) - this includes the SAS token
   - It looks like: `https://afepstorage12345.blob.core.windows.net/pacfiles/proxy.pac?sp=r&st=2025-11-06T...`
7. **Save this URL securely** - you'll need it in the next step
   - ⚠️ **Important**: This URL is shown only once and cannot be retrieved later

#### Step 6: Configure PAC File in Firewall Policy

1. In Azure Portal, navigate to your Firewall resource (`afw-lab1`)
2. Under **Settings**, click **Firewall Policy**
3. Click on the policy name link `afp-lab1`
4. In the left menu under **Settings**, click **Explicit Proxy (Preview)**
5. In the **Proxy auto-configuration (PAC)** section:
   - Toggle **Enable proxy auto-configuration** to **ON**
   - **PAC file URL**: Paste the entire **Blob SAS URL** you copied
   - **PAC file port**: `8090` (different from HTTP/HTTPS proxy ports)
6. Click **Apply** button (top of page)
7. Wait for "Update succeeded" notification (~30-60 seconds)

#### Step 7: Configure Client to Use PAC File

1. **RDP into your Client VM** (`vm-client-lab1`) using the method from Lab 1
2. **Remove manual proxy settings first** (to test PAC file exclusively):
   - Press **Windows key + I** to open Settings
   - Click **Network & Internet** → **Proxy**
   - Under **Manual proxy setup**, toggle **Use a proxy server** to **OFF**
   - Click **Save**

3. **Configure automatic proxy using PAC**:
   - Still in **Network & Internet** → **Proxy** settings
   - Under **Automatic proxy setup**:
     - Toggle **Automatically detect settings** to **OFF** (for testing PAC explicitly)
     - Toggle **Use setup script** to **ON**
     - **Script address**: Paste your **Blob SAS URL** (same one from Step 5)
     - Click **Save** button

4. **Alternative: Configure using Registry** (on the VM):
   - Open **PowerShell as Administrator**
   - Run:
     ```powershell
     $pacUrl = "YOUR_BLOB_SAS_URL_HERE"
     Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "AutoConfigURL" -Value $pacUrl
     ```

#### Step 8: Test PAC File Configuration

1. **On the Client VM**, open **Command Prompt** or **PowerShell**
2. **Clear DNS cache** to ensure fresh resolution:
   ```cmd
   ipconfig /flushdns
   ```

3. **Restart browser** (close all instances and reopen)

4. **Test internal traffic (should go DIRECT)**:
   - Open **PowerShell**
   - Test connectivity to internal address:
     ```powershell
     Test-NetConnection -ComputerName 10.0.0.4 -Port 443
     ```
   - ✅ **Expected**: Connection succeeds directly

5. **Test external traffic (should go via proxy)**:
   - Open **Microsoft Edge**
   - Navigate to `http://www.microsoft.com`
   - ✅ **Expected**: Page loads (allowed by firewall, routed via proxy)
   - Navigate to `http://www.bing.com`
   - ✅ **Expected**: Page loads (allowed by firewall, routed via proxy)
   - Navigate to `http://www.google.com`
   - ❌ **Expected**: Connection fails (not in firewall rules)

#### Step 9: Verify PAC File is Being Served

1. **On the Client VM**, open **Command Prompt**
2. Test PAC file accessibility:
   ```cmd
   curl http://10.0.0.4:8090/proxy.pac
   ```
3. ✅ **Expected**: You should see the PAC file JavaScript content displayed

4. **Verify proxy resolution**:
   - Open **PowerShell**
   - Run:
     ```powershell
     [System.Net.WebRequest]::GetSystemWebProxy().GetProxy("http://www.microsoft.com")
     ```
   - ✅ **Expected**: Should show `http://10.0.0.4:8080`

#### Step 10: Monitor PAC File Usage in Azure Monitor

1. In Azure Portal, go to your Firewall resource (`afw-lab1`)
2. Under **Monitoring**, click **Logs**
3. Paste this query:
   ```kusto
   AzureDiagnostics
   | where Category == "AzureFirewallApplicationRule"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Protocol = split(msg_s, " ")[0], SourceIP = split(msg_s, " ")[3], URL = split(msg_s, " ")[7], Action = split(msg_s, " ")[11]
   | order by TimeGenerated desc
   ```
4. Click **Run** button
5. Review logs to see traffic going through the explicit proxy

#### Troubleshooting Tips

- **PAC file not loading**: Verify SAS token hasn't expired, regenerate if needed
- **Proxy not working**: Check firewall private IP is correct in PAC file
- **Certificate errors**: Expected for HTTPS with explicit proxy (TLS inspection requires Premium SKU)
- **Verify PAC syntax**: Use online PAC file testers to validate JavaScript syntax

---

### ✅ Lab 3: Advanced Hub-and-Spoke Integration (Detailed Steps)

**Goal**: Implement AFEP in a landing zone with hub-and-spoke topology.

**Estimated Time**: 60-90 minutes

**Prerequisites**: Understanding of VNet peering and routing concepts

#### Step 1: Create Hub VNet

1. In the Azure Portal search bar, type **Virtual networks**
2. Click **Virtual networks** from the results
3. Click **+ Create** button
4. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Click **Create new**
     - Name: `RG-AFEP-HubSpoke`
     - Click **OK**
   - **Virtual network name**: `Hub-VNet`
   - **Region**: `Sweden Central`
5. Click **Next: IP Addresses** button
6. On the **IP Addresses** tab:
   - **IPv4 address space**: Change to `10.0.0.0/16`
   - Click **default** subnet to edit:
     - **Subnet purpose**: Select **Azure Firewall**
     - **Starting address**: `10.0.0.0`
     - **Subnet size**: **/26** (mandatory - 64 addresses)
     - Click **Save**
7. Click **+ Add a subnet**:
   - **Subnet template**: **Default**
   - **Name**: `SharedServices`
   - **Starting address**: `10.0.2.0`
   - **Subnet size**: **/24**
   - Click **Add**
8. Click **Review + create** → **Create**
9. Wait for deployment (~1 minute)

#### Step 2: Create Spoke VNets

**Create Spoke 1:**

1. Click **+ Create a resource** → Search for **Virtual network** → Click **Create**
2. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-HubSpoke`
   - **Name**: `Spoke1-VNet`
   - **Region**: `Sweden Central`
3. Click **Next: IP Addresses**
4. On the **IP Addresses** tab:
   - **IPv4 address space**: Change to `10.1.0.0/16`
   - Click **default** subnet to edit:
     - **Name**: `Workload1-Subnet`
     - **Starting address**: `10.1.0.0`
     - **Subnet size**: **/24**
     - Click **Save**
5. Click **Review + create** → **Create**
6. Wait for deployment (~1 minute)

**Create Spoke 2:**

1. Repeat the same steps as Spoke 1, but with:
   - **Name**: `Spoke2-VNet`
   - **IPv4 address space**: `10.2.0.0/16`
   - **Subnet name**: `Workload2-Subnet`
   - **Subnet address**: `10.2.0.0/24`

#### Step 3: Create VNet Peering (Hub to Spoke 1)

1. In Azure Portal, navigate to **Hub-VNet**
2. In the left menu under **Settings**, click **Peerings**
3. Click **+ Add** button (top left)
4. On the **Add peering** page:
   
   **This virtual network** section:
   - **Peering link name**: `Hub-to-Spoke1`
   - **Traffic to remote virtual network**: **Allow**
   - **Traffic forwarded from remote virtual network**: **Allow**
   - **Virtual network gateway or Route Server**: **Use this virtual network's gateway or Route Server** (select after deploying firewall)
   
   **Remote virtual network** section:
   - **Peering link name**: `Spoke1-to-Hub`
   - **Virtual network deployment model**: **Resource Manager**
   - **Subscription**: Select your subscription
   - **Virtual network**: Select **Spoke1-VNet**
   - **Traffic to remote virtual network**: **Allow**
   - **Traffic forwarded from remote virtual network**: **Allow**
   - **Virtual network gateway or Route Server**: **Use the remote virtual network's gateway or Route Server**
5. Click **Add** button (bottom)
6. Wait for "Peering succeeded" notification (~30 seconds)
7. Verify **Peering status** shows **Connected**

#### Step 4: Create VNet Peering (Hub to Spoke 2)

1. Still in **Hub-VNet** → **Peerings**
2. Click **+ Add** button
3. Configure peering:
   - **This VNet peering link name**: `Hub-to-Spoke2`
   - **Remote VNet peering link name**: `Spoke2-to-Hub`
   - **Virtual network**: Select **Spoke2-VNet**
   - Same settings as Spoke 1 peering
4. Click **Add** button
5. Wait for "Peering succeeded" notification

#### Step 5: Deploy Azure Firewall in Hub

1. In Azure Portal search bar, type **Firewalls**
2. Click **Firewalls** → **+ Create**
3. On the **Basics** tab:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-HubSpoke`
   - **Name**: `afw-hub`
   - **Region**: `Sweden Central`
   - **Firewall SKU**: **Premium** (for advanced features)
   - **Firewall management**: **Use a Firewall Policy**
   - **Firewall policy**: Click **Add new**
     - **Name**: `afp-hub-policy`
     - **Region**: `Sweden Central`
     - **Policy tier**: **Premium**
     - Click **OK**
   - **Virtual network**: **Use existing** → Select **Hub-VNet**
   - **Public IP address**: Click **Add new**
     - **Name**: `pip-firewall-hub`
     - Click **OK**
4. Click **Review + create** → **Create**
5. **Wait 8-12 minutes** for deployment

#### Step 6: Enable Explicit Proxy with PAC File

1. Navigate to Firewall resource `afw-hub` → **Firewall Policy**
2. Click policy name **afp-hub-policy**
3. Under **Settings**, click **Explicit Proxy (Preview)**
4. Configure:
   - **Enable Explicit Proxy**: Toggle **ON**
   - **HTTP Port**: `8080`
   - **HTTPS Port**: `8443`
   - **Enable proxy auto-configuration**: Toggle **ON**
   - **PAC file URL**: Upload new PAC file (see Step 7)
   - **PAC file port**: `8090`
5. Click **Apply** (don't close yet - we'll update the PAC URL)

#### Step 7: Create Advanced PAC File for Hub-Spoke

1. **On your local computer**, create a new file named **proxy-hubspoke.pac**:

   ```javascript
   function FindProxyForURL(url, host) {
       // Define internal networks (bypass proxy)
       var internalNetworks = [
           "10.0.0.0/16",  // Hub VNet
           "10.1.0.0/16",  // Spoke1 VNet
           "10.2.0.0/16"   // Spoke2 VNet
       ];
       
       // Internal domain names (go direct)
       if (dnsDomainIs(host, ".internal.company.com") ||
           dnsDomainIs(host, ".corp.local") ||
           isPlainHostName(host)) {
           return "DIRECT";
       }
       
       // Check if destination is in internal IP ranges
       var hostIP = dnsResolve(host);
       if (hostIP) {
           if (isInNet(hostIP, "10.0.0.0", "255.0.0.0") ||
               isInNet(hostIP, "172.16.0.0", "255.240.0.0") ||
               isInNet(hostIP, "192.168.0.0", "255.255.0.0")) {
               return "DIRECT";
           }
       }
       
       // All external traffic goes through Azure Firewall explicit proxy
       return "PROXY 10.0.0.4:8080; DIRECT";
   }
   ```

2. Replace `10.0.0.4` with your actual Firewall Private IP (check in Azure Portal → Firewall → Overview)
3. Upload to Storage Account (use Lab 2 steps):
   - Create container or use existing `pacfiles`
   - Upload `proxy-hubspoke.pac`
   - Generate SAS token with READ permission (7 days expiry)
   - Copy Blob SAS URL

4. Return to Firewall Policy **Explicit Proxy** settings
5. Paste the new PAC file SAS URL
6. Click **Apply**

#### Step 8: Create Route Tables for Spokes

**Create Route Table for Spoke 1:**

1. In Azure Portal search bar, type **Route tables**
2. Click **Route tables** → **+ Create**
3. Fill in:
   - **Subscription**: Select your subscription
   - **Resource group**: Select `RG-AFEP-HubSpoke`
   - **Region**: `Sweden Central`
   - **Name**: `rt-spoke1`
   - **Propagate gateway routes**: **No**
4. Click **Review + create** → **Create**
5. When complete, click **Go to resource**
6. Under **Settings**, click **Routes**
7. Click **+ Add** button:
   - **Route name**: `default-via-firewall`
   - **Destination type**: **IP Addresses**
   - **Destination IP addresses/CIDR ranges**: `0.0.0.0/0`
   - **Next hop type**: **Virtual appliance**
   - **Next hop address**: `10.0.0.4` (Firewall private IP)
   - Click **Add**
8. Under **Settings**, click **Subnets**
9. Click **+ Associate** button:
   - **Virtual network**: Select **Spoke1-VNet**
   - **Subnet**: Select **Workload1-Subnet**
   - Click **OK**

**Create Route Table for Spoke 2:**

1. Repeat the same steps with:
   - **Name**: `rt-spoke2`
   - Same route: `0.0.0.0/0` → `10.0.0.4`
   - Associate with **Spoke2-VNet** → **Workload2-Subnet**

#### Step 9: Configure Application Rules for Hub-Spoke

1. Navigate to Firewall Policy **afp-hub-policy**
2. Under **Settings**, click **Application Rules**
3. Click **+ Add a rule collection**
4. Configure:
   - **Name**: `AllowWebTrafficHubSpoke`
   - **Priority**: `100`
   - **Rule collection action**: **Allow**
   - **Rule collection group**: **DefaultApplicationRuleCollectionGroup**
5. Add rules:
   
   **Rule 1**:
   - **Name**: `AllowMicrosoft`
   - **Source**: `10.1.0.0/16,10.2.0.0/16` (both spoke subnets)
   - **Protocol**: `http:80,https:443`
   - **Destination type**: **FQDN**
   - **Destination**: `*.microsoft.com,*.azure.com`
   
   **Rule 2**:
   - **Name**: `AllowWindowsUpdate`
   - **Source**: `10.1.0.0/16,10.2.0.0/16`
   - **Protocol**: `http:80,https:443`
   - **Destination type**: **FQDN Tag**
   - **Destination**: Select **WindowsUpdate**

6. Click **Add** button
7. Wait for deployment (~2 minutes)

#### Step 10: Deploy VMs in Spoke Networks

**Deploy VM in Spoke 1:**

1. Create VM (follow Lab 1 VM steps):
   - **Name**: `vm-spoke1`
   - **Resource group**: `RG-AFEP-HubSpoke`
   - **Region**: `Sweden Central`
   - **Image**: **Windows Server 2022**
   - **Size**: **Standard_B2s**
   - **VNet**: **Spoke1-VNet**
   - **Subnet**: **Workload1-Subnet**
   - **Public IP**: Create new (for RDP access)
   - **Username**: `azureadmin`
   - **Password**: Your secure password

**Deploy VM in Spoke 2:**

1. Repeat with:
   - **Name**: `vm-spoke2`
   - **VNet**: **Spoke2-VNet**
   - **Subnet**: **Workload2-Subnet**

#### Step 11: Configure Proxy on Spoke VMs

**On both VMs** (RDP into each):

1. **Option A: Use PAC file URL**:
   - Open Settings → Network & Internet → Proxy
   - Enable **Use setup script**
   - Enter PAC file Blob SAS URL
   - Click Save

2. **Option B: Manual proxy**:
   - Enable **Use a proxy server**
   - Address: `10.0.0.4`
   - Port: `8080`
   - Click Save

#### Step 12: Test Hub-Spoke Topology

1. **From vm-spoke1**, test:
   - Ping vm-spoke2 private IP (should work - VNet peering)
   - Browse to `https://www.microsoft.com` (should work via proxy)
   - Browse to `https://www.google.com` (should fail - not in rules)

2. **From vm-spoke2**, test:
   - Ping vm-spoke1 private IP
   - Same web browsing tests

3. **Verify in Azure Monitor**:
   - Check firewall logs
   - Confirm traffic from both spokes appears
   - Verify source IPs show spoke subnet addresses

#### Step 13: Validate Traffic Flow

1. In Azure Portal → Firewall `afw-hub` → **Metrics**
2. Add metrics:
   - **Application rules hit count**
   - **Network rules hit count**
   - **Data processed**
3. Filter by time range (last 1 hour)
4. Verify traffic is flowing through firewall

---

## Best Practices

### 1. Network Design

✅ **Deploy Firewall with /26 Subnet**
- **AzureFirewallSubnet** must be exactly **/26** (64 IP addresses)
- Smaller subnets will prevent deployment
- Larger subnets waste IP space unnecessarily
- Firewall needs room to scale automatically

✅ **Use Multiple Availability Zones**
- Deploy across zones 1, 2, and 3 for 99.99% SLA
- Protects against datacenter failures
- Configure during initial deployment (cannot be changed later)
- Example regions: Sweden Central, West Europe, North Europe

✅ **Implement Hub-Spoke Topology**
- Centralize firewall in hub VNet
- Connect spokes via VNet peering
- Use route tables to direct traffic through firewall
- Reduces complexity and cost

### 2. Explicit Proxy Configuration

✅ **Use Standard Ports**
- HTTP Port: **8080** (industry standard)
- HTTPS Port: **8443** (industry standard)
- PAC File Port: **8090** (must be different from HTTP/HTTPS)
- Ports must be unique from each other

✅ **Implement PAC Files for Flexibility**
- Host PAC files in Azure Blob Storage
- Use SAS tokens with READ permission only
- Set SAS expiry to 7-90 days (renew before expiry)
- Update PAC file centrally without touching clients
- Include fallback: `return "PROXY 10.0.0.4:8080; DIRECT"`

✅ **Use Application Rules, Not Network Rules**
- **Critical**: Explicit proxy requires application rules
- Network rules will not work with explicit proxy
- Use FQDN filtering for granular control
- Leverage FQDN tags for Microsoft services

### 3. Security Hardening

✅ **Enable Threat Intelligence**
- Configure in "Alert and Deny" mode
- Blocks traffic to/from known malicious IPs
- Processes before other rules
- Free feature included with Azure Firewall

✅ **Use Premium SKU for TLS Inspection**
- Standard SKU: No TLS inspection (can't inspect HTTPS content)
- Premium SKU: Full TLS inspection with certificate management
- Required for deep packet inspection of encrypted traffic
- Configure intermediate CA certificate in Key Vault

✅ **Enable DNS Proxy**
- Firewall acts as DNS forwarder
- Consistent DNS resolution between clients and firewall
- Required for FQDN filtering to work correctly
- Configure in Firewall Policy → DNS settings

✅ **Implement IDPS (Premium SKU)**
- Intrusion Detection and Prevention System
- 67,000+ signature rules across 50+ categories
- Modes: Off, Alert only, Alert and deny
- Essential for production workloads

### 4. Monitoring and Logging

✅ **Enable Diagnostic Settings**
- Send logs to Log Analytics workspace
- Categories to enable:
  - AzureFirewallApplicationRule (explicit proxy traffic)
  - AzureFirewallNetworkRule
  - AzureFirewallDnsProxy
  - AzureFirewallThreatIntelLog
- Retention: 30-90 days minimum

✅ **Use Azure Monitor Workbooks**
- Pre-built dashboards for firewall analytics
- Navigate to: Firewall → Monitoring → Workbooks
- Visualize:
  - Top blocked sites
  - Traffic patterns
  - Rule hit counts
  - Threat intelligence alerts

✅ **Set Up Alerts**
- Alert on firewall health metrics
- Alert on high denied traffic (possible attack)
- Alert on SNAT port exhaustion
- Use Action Groups for notifications

### 5. Policy Management

✅ **Use Firewall Policy (Not Classic Rules)**
- Centralized management across multiple firewalls
- Inheritance model (base + child policies)
- Better for landing zone scenarios
- Required for explicit proxy feature

✅ **Organize Rules by Priority**
- Lower number = higher priority
- Critical allow rules: Priority 100-199
- Standard allow rules: Priority 200-999
- Deny rules: Priority 1000+
- Place frequently used rules first for performance

✅ **Use IP Groups for Scalability**
- Group related IP addresses
- Reusable across multiple rules
- Easier to maintain than individual IPs
- Supports up to 200 IP Groups per firewall

### 6. High Availability and Disaster Recovery

✅ **Deploy in Multiple Regions**
- Primary region: Sweden Central
- Secondary region: North Europe or West Europe
- Use Azure Traffic Manager for failover
- Replicate firewall policies across regions

✅ **Configure Health Probes**
- Monitor firewall availability
- Set up Azure Resource Health alerts
- Test failover procedures quarterly
- Document recovery procedures

✅ **Back Up Configurations**
- Export firewall policies regularly
- Use Azure DevOps/GitHub for version control
- Store ARM templates and Bicep files
- Test restore procedures

### 7. Cost Optimization

✅ **Right-Size Your Deployment**
- Standard SKU: ~$1.25/hour (~$900/month) + data processing
- Premium SKU: ~$0.875/hour (~$630/month) + data processing
- Data processing: ~$0.016/GB
- Use Standard unless you need Premium features (TLS inspection, IDPS)

✅ **Stop/Deallocate When Not Needed**
- Development/test environments: Stop after hours
- Use automation with Azure Automation
- Savings: ~50% for environments running 12 hours/day
- Production: Always keep running

✅ **Monitor Data Processing Costs**
- Review monthly data processed metrics
- Optimize rules to reduce unnecessary inspection
- Use FQDN tags instead of wildcards
- Consider Azure Firewall Manager for multi-firewall deployments

### 8. Compliance and Governance

✅ **Implement Azure Policy**
- **Enforce Explicit Proxy Configuration**: Ensures all firewall policies have explicit proxy enabled
- **Enable PAC File Configuration**: Audits PAC file usage with explicit proxy
- **Enable Threat Intelligence**: Ensures threat intel is enabled
- **DNS Proxy Enabled**: Mandates DNS proxy feature
- Assign at management group or subscription level

✅ **Use Role-Based Access Control (RBAC)**
- Network Contributor: Full firewall management
- Reader: View-only access
- Custom roles for specific operations
- Principle of least privilege

✅ **Enable Resource Locks**
- Apply "CanNotDelete" lock on production firewalls
- Prevents accidental deletion
- Apply to resource group for broader protection

### 9. Troubleshooting Common Issues

❌ **Problem**: PAC file not loading  
✅ **Solution**: 
- Verify SAS token hasn't expired
- Regenerate SAS with READ permission
- Check PAC file URL is accessible from client
- Test: `curl http://<firewall-ip>:8090/proxy.pac`

❌ **Problem**: HTTPS sites not working  
✅ **Solution**:
- Standard SKU cannot inspect HTTPS (by design)
- Upgrade to Premium for TLS inspection
- Or add certificate exceptions in client browsers

❌ **Problem**: Traffic not hitting firewall rules  
✅ **Solution**:
- Verify route table is associated with subnet
- Check route points to firewall private IP
- Ensure "Propagate gateway routes" is disabled
- Use "Next Hop" diagnostics in Network Watcher

❌ **Problem**: DNS resolution failures  
✅ **Solution**:
- Enable DNS Proxy in firewall policy
- Configure VMs to use firewall IP as DNS (10.0.0.4)
- Or use Azure DNS (168.63.129.16) with custom DNS forwarding

### 10. Testing and Validation

✅ **Pre-Deployment Testing**
- Validate Bicep/ARM templates
- Test in non-production environment first
- Verify all required SKUs are available in target region
- Confirm IP address space doesn't conflict

✅ **Post-Deployment Validation**
- Test explicit proxy from client VM
- Verify PAC file is accessible
- Check Azure Monitor logs for traffic
- Test both allowed and blocked sites
- Verify route tables are working

✅ **Performance Testing**
- Baseline throughput before production
- Test concurrent connections (firewall supports 10,000-30,000)
- Monitor SNAT port usage
- Test during peak hours

---

## Configuration Validation Checklist

Before deploying to production, verify:

- [ ] AzureFirewallSubnet is exactly /26
- [ ] Firewall is deployed in multiple availability zones
- [ ] Firewall Policy (not classic rules) is being used
- [ ] Explicit Proxy is enabled with unique HTTP/HTTPS/PAC ports
- [ ] Application rules (not network rules) are configured
- [ ] PAC file is uploaded to storage with valid SAS token
- [ ] DNS Proxy is enabled in firewall policy
- [ ] Threat Intelligence is set to "Alert and Deny"
- [ ] Diagnostic settings are configured
- [ ] Route tables are created and associated with subnets
- [ ] VNet peering is configured with gateway transit
- [ ] Client VMs are configured with proxy settings
- [ ] Testing has been performed on allowed and blocked sites
- [ ] Azure Monitor logs show traffic flowing through firewall
- [ ] Backup/restore procedures are documented
- [ ] Resource locks are applied to production resources

---

## Additional Resources

- [Azure Firewall Documentation](https://learn.microsoft.com/en-us/azure/firewall/)
- [Explicit Proxy Overview](https://learn.microsoft.com/en-us/azure/firewall/explicit-proxy)
- [Azure Firewall Premium Features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)
- [PAC File Reference](https://developer.mozilla.org/en-US/docs/Web/HTTP/Proxy_servers_and_tunneling/Proxy_Auto-Configuration_PAC_file)
- [Azure Firewall Best Practices](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-firewall)
- [Secure Azure Firewall Deployment](https://learn.microsoft.com/en-us/azure/firewall/secure-firewall)
- [Azure Policy for Firewall](https://learn.microsoft.com/en-us/azure/firewall/firewall-azure-policy)

---

## Summary

This guide provides validated, step-by-step procedures for implementing Azure Firewall Explicit Proxy across three comprehensive labs:

- **Lab 1**: Basic explicit proxy deployment with application rules and testing
- **Lab 2**: Advanced PAC file configuration with Azure Storage integration
- **Lab 3**: Enterprise hub-and-spoke topology with multiple spokes and routing

All configurations have been validated against Microsoft documentation and follow Azure best practices. Remember that AFEP is currently in **Public Preview** and features may change before general availability.

---

**Document Version**: 1.0  
**Last Updated**: November 6, 2025  
**Status**: Validated against Azure Firewall documentation
