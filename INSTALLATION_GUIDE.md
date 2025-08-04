# Cross-Platform Server Testing Suite - Installation Guide

## 🚀 Quick Start

### Automatic Installation (Recommended)

```bash
# Make the installer executable
chmod +x install_dependencies.sh

# Run the automatic installer
./install_dependencies.sh
```

### Manual Installation

If the automatic installer doesn't work for your system, follow the manual installation steps below.

## 📋 Prerequisites

- **Linux**: Ubuntu 18.04+, Debian 9+, RHEL/CentOS 7+, Fedora 28+
- **macOS**: 10.14+ (with Homebrew)
- **Windows**: Windows 10+ (with WSL, MSYS2, or Cygwin)
- **Root/Sudo Access**: Required for installing system packages
- **Internet Connection**: Required for downloading dependencies

## 🔧 Supported Operating Systems

### Linux Distributions
- **Ubuntu/Debian**: Full support with apt package manager
- **RHEL/CentOS**: Full support with yum/dnf package manager
- **Fedora**: Full support with dnf package manager
- **Other Linux**: Partial support (manual installation may be required)

### macOS
- **macOS 10.14+**: Full support with Homebrew package manager
- **Older versions**: Limited support

### Windows
- **Windows 10+ with WSL**: Full Linux support
- **Windows with MSYS2/Cygwin**: Limited support
- **Native Windows**: Not supported (use WSL)

## 📦 Dependencies Overview

### Core Tools (Required)
| Tool | Purpose | Package Name |
|------|---------|--------------|
| `fio` | Performance testing | fio |
| `smartctl` | Disk health monitoring | smartmontools |
| `nvme` | NVMe drive management | nvme-cli |
| `parallel` | Concurrent execution | parallel |
| `ipmitool` | Hardware monitoring | ipmitool |
| `dmidecode` | Hardware information | dmidecode |
| `lspci` | PCI device listing | pciutils |
| `hdparm` | Disk parameters | hdparm |
| `bc` | Mathematical calculations | bc |
| `jq` | JSON processing | jq |

### Vendor-Specific Tools (Optional)
| Tool | Purpose | Source |
|------|---------|--------|
| `cpu-x` | Hardware information | AppImage |
| `arcconf` | Adaptec RAID management | Vendor RPM |
| `ipmicfg` | IPMI configuration | Vendor binary |

### Python Dependencies (Future Use)
| Package | Purpose |
|---------|---------|
| `psutil` | System monitoring |
| `py-cpuinfo` | CPU information |
| `click` | CLI framework |
| `rich` | Rich terminal output |
| `PyYAML` | YAML configuration |
| `loguru` | Advanced logging |

## 🛠️ Installation Options

### Full Installation (Default)
```bash
./install_dependencies.sh
```

### Skip Vendor Tools
```bash
./install_dependencies.sh --skip-vendor
```

### Skip Python Dependencies
```bash
./install_dependencies.sh --skip-python
```

### Verify Only (Check Existing Installation)
```bash
./install_dependencies.sh --verify-only
```

### Verbose Output
```bash
./install_dependencies.sh -v
```

### Help
```bash
./install_dependencies.sh --help
```

## 🔍 Manual Installation by OS

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y \
    fio \
    smartmontools \
    nvme-cli \
    parallel \
    ipmitool \
    dmidecode \
    pciutils \
    hdparm \
    bc \
    jq \
    wget \
    curl \
    build-essential \
    git
```

### RHEL/CentOS
```bash
sudo yum install -y epel-release
sudo yum install -y \
    fio \
    smartmontools \
    nvme-cli \
    parallel \
    ipmitool \
    dmidecode \
    pciutils \
    hdparm \
    bc \
    jq \
    wget \
    curl \
    gcc \
    make \
    git
```

### Fedora
```bash
sudo dnf install -y \
    fio \
    smartmontools \
    nvme-cli \
    parallel \
    ipmitool \
    dmidecode \
    pciutils \
    hdparm \
    bc \
    jq \
    wget \
    curl \
    gcc \
    make \
    git
```

### macOS
```bash
# Install Homebrew if not installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install \
    fio \
    smartmontools \
    parallel \
    jq \
    wget \
    curl \
    gcc \
    make \
    git
```

## 🔧 Vendor-Specific Tools

### CPU-X (Hardware Information)
```bash
# Download CPU-X AppImage
wget https://github.com/TheTumultuousUnicornOfDarkness/CPU-X/releases/download/5.3.1/CPU-X-5.3.1-x86_64.AppImage

# Make executable and create symlink
chmod +x CPU-X-5.3.1-x86_64.AppImage
sudo ln -sf "$(pwd)/CPU-X-5.3.1-x86_64.AppImage" /usr/bin/cpu-x
```

### Adaptec arcconf (RAID Management)
```bash
# For RHEL/CentOS/Fedora
sudo rpm -i Arcconf-4.26-27449.x86_64.rpm

# For Ubuntu/Debian (requires alien)
sudo apt-get install alien
sudo alien -d Arcconf-4.26-27449.x86_64.rpm
sudo dpkg -i arcconf_4.26-1_amd64.deb
```

### IPMICFG (IPMI Configuration)
```bash
# Copy binary to system path
sudo cp IPMICFG-Linux.x86_64 /usr/local/bin/ipmicfg
sudo chmod +x /usr/local/bin/ipmicfg
```

## 🧪 Verification

### Check Core Tools
```bash
# Verify all core tools are installed
for tool in fio smartctl nvme parallel ipmitool dmidecode lspci hdparm bc jq; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool installed"
    else
        echo "✗ $tool not found"
    fi
done
```

### Check Vendor Tools
```bash
# Check CPU-X
if [ -L "/usr/bin/cpu-x" ] || [ -f "/usr/bin/cpu-x" ]; then
    echo "✓ CPU-X available"
else
    echo "⚠ CPU-X not found"
fi

# Check arcconf
if command -v arcconf >/dev/null 2>&1; then
    echo "✓ arcconf available"
else
    echo "⚠ arcconf not found"
fi

# Check ipmicfg
if command -v ipmicfg >/dev/null 2>&1; then
    echo "✓ ipmicfg available"
else
    echo "⚠ ipmicfg not found"
fi
```

### Test Basic Functionality
```bash
# Test FIO
fio --version

# Test smartctl
smartctl --version

# Test nvme
nvme version

# Test CPU-X
cpu-x --version
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Permission Denied
```bash
# Solution: Use sudo
sudo ./install_dependencies.sh
```

#### 2. Package Not Found
```bash
# Update package lists
sudo apt-get update  # Ubuntu/Debian
sudo yum update      # RHEL/CentOS
sudo dnf update      # Fedora
```

#### 3. EPEL Repository Not Available (RHEL/CentOS)
```bash
# Install EPEL repository
sudo yum install -y epel-release
```

#### 4. Homebrew Not Found (macOS)
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 5. Alien Not Found (Ubuntu/Debian)
```bash
# Install alien for RPM to DEB conversion
sudo apt-get install alien
```

### OS-Specific Issues

#### Ubuntu/Debian
- **Issue**: `fio` package not found
- **Solution**: Enable universe repository: `sudo add-apt-repository universe`

#### RHEL/CentOS
- **Issue**: `nvme-cli` not found
- **Solution**: Enable EPEL: `sudo yum install -y epel-release`

#### Fedora
- **Issue**: Package conflicts
- **Solution**: Use `--allowerasing` flag: `sudo dnf install --allowerasing package_name`

#### macOS
- **Issue**: `smartmontools` not working
- **Solution**: Install via Homebrew and ensure proper permissions

### Network Issues

#### Proxy Configuration
```bash
# Set proxy for apt
echo 'Acquire::http::Proxy "http://proxy.company.com:8080";' | sudo tee /etc/apt/apt.conf.d/proxy

# Set proxy for yum
echo 'proxy=http://proxy.company.com:8080' | sudo tee -a /etc/yum.conf

# Set proxy for dnf
echo 'proxy=http://proxy.company.com:8080' | sudo tee -a /etc/dnf/dnf.conf
```

#### Firewall Issues
```bash
# Allow package manager traffic
sudo ufw allow out 80/tcp  # HTTP
sudo ufw allow out 443/tcp # HTTPS
```

## 📊 Post-Installation

### Directory Structure
After installation, the following directories will be created:
```
.
├── logs/          # Log files
├── reports/       # Test reports
├── data/          # Test data
├── temp/          # Temporary files
├── tests/         # Test results
└── config/        # Configuration files
```

### Configuration Files
- `config.yaml` - Main configuration file
- `config/servertest.conf` - Legacy configuration
- `config.sh` - Shell configuration

### Next Steps
1. **Run the test suite**: `./servertest.sh`
2. **Check hardware**: `./scripts/hw_details.sh`
3. **Monitor system**: `./scripts/monitor_temp.sh temp.csv 30`
4. **View device summary**: Run `./servertest.sh` and select option 7

## 📞 Support

### Getting Help
1. Check the troubleshooting section above
2. Run verification: `./install_dependencies.sh --verify-only`
3. Check logs in `./logs/` directory
4. Review the main README.md file

### Reporting Issues
When reporting installation issues, please include:
- Operating system and version
- Output of `./install_dependencies.sh --verify-only`
- Any error messages from the installation process
- System architecture (`uname -a`)

## 🔄 Updates

### Updating Dependencies
```bash
# Update package lists
sudo apt-get update  # Ubuntu/Debian
sudo yum update      # RHEL/CentOS
sudo dnf update      # Fedora
brew update          # macOS

# Re-run installer
./install_dependencies.sh
```

### Updating Vendor Tools
```bash
# Update CPU-X
wget -O CPU-X-5.3.1-x86_64.AppImage "https://github.com/TheTumultuousUnicornOfDarkness/CPU-X/releases/download/5.3.1/CPU-X-5.3.1-x86_64.AppImage"
chmod +x CPU-X-5.3.1-x86_64.AppImage
sudo ln -sf "$(pwd)/CPU-X-5.3.1-x86_64.AppImage" /usr/bin/cpu-x
```

## 📝 License

This installation script is part of the Cross-Platform Server Testing Suite and is licensed under the MIT License. 