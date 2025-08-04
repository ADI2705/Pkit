#!/bin/bash

# === Cross-Platform Server Testing Suite - Dependency Installer ===
# Automatically detects OS and installs all required dependencies

set -e

# Colors for output
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
MAG='\033[0;35m'
CYN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GRN}[$timestamp] [INFO] $message${NC}"
            ;;
        "WARN")
            echo -e "${YEL}[$timestamp] [WARN] $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}"
            ;;
        "DEBUG")
            echo -e "${BLU}[$timestamp] [DEBUG] $message${NC}"
            ;;
        *)
            echo -e "${CYN}[$timestamp] [$level] $message${NC}"
            ;;
    esac
}

# Function to detect OS
detect_os() {
    log "INFO" "Detecting operating system..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_NAME="$NAME"
            OS_VERSION="$VERSION_ID"
            OS_ID="$ID"
        elif [ -f /etc/redhat-release ]; then
            OS_NAME=$(cat /etc/redhat-release)
            OS_ID="rhel"
        elif [ -f /etc/debian_version ]; then
            OS_NAME="Debian"
            OS_ID="debian"
        else
            OS_NAME="Unknown Linux"
            OS_ID="unknown"
        fi
        log "INFO" "Detected: $OS_NAME ($OS_ID)"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        OS_NAME="macOS"
        OS_VERSION=$(sw_vers -productVersion)
        OS_ID="macos"
        log "INFO" "Detected: $OS_NAME $OS_VERSION"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Windows with MSYS2/Cygwin
        OS_NAME="Windows (MSYS2/Cygwin)"
        OS_ID="windows"
        log "INFO" "Detected: $OS_NAME"
    else
        log "ERROR" "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is root/sudo
check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        log "INFO" "Running as root"
        return 0
    elif command_exists sudo; then
        log "INFO" "Using sudo for privileged operations"
        SUDO_CMD="sudo"
        return 0
    else
        log "ERROR" "This script requires root privileges or sudo access"
        exit 1
    fi
}

# Function to install package manager dependencies
install_package_manager() {
    log "INFO" "Installing package manager dependencies..."
    
    case "$OS_ID" in
        "ubuntu"|"debian")
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y curl wget build-essential
            ;;
        "rhel"|"centos"|"fedora")
            if command_exists dnf; then
                $SUDO_CMD dnf install -y curl wget gcc make
            else
                $SUDO_CMD yum install -y curl wget gcc make
            fi
            ;;
        "macos")
            if ! command_exists brew; then
                log "INFO" "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            ;;
        *)
            log "WARN" "Unknown OS, skipping package manager setup"
            ;;
    esac
}

# Function to install core dependencies
install_core_dependencies() {
    log "INFO" "Installing core dependencies..."
    
    case "$OS_ID" in
        "ubuntu"|"debian")
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y \
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
            ;;
        "rhel"|"centos")
            $SUDO_CMD yum install -y epel-release
            $SUDO_CMD yum install -y \
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
            ;;
        "fedora")
            $SUDO_CMD dnf install -y \
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
            ;;
        "macos")
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
            ;;
        *)
            log "WARN" "Unknown OS, please install dependencies manually"
            ;;
    esac
}

# Function to install vendor-specific tools
install_vendor_tools() {
    log "INFO" "Installing vendor-specific tools..."
    
    # Install Adaptec arcconf if available
    if [ -f "Arcconf-4.26-27449.x86_64.rpm" ]; then
        log "INFO" "Installing Adaptec arcconf..."
        case "$OS_ID" in
            "rhel"|"centos"|"fedora")
                $SUDO_CMD rpm -i Arcconf-4.26-27449.x86_64.rpm
                ;;
            "ubuntu"|"debian")
                # Convert RPM to DEB using alien if available
                if command_exists alien; then
                    $SUDO_CMD alien -d Arcconf-4.26-27449.x86_64.rpm
                    $SUDO_CMD dpkg -i arcconf_4.26-1_amd64.deb
                else
                    log "WARN" "Install alien to convert RPM to DEB: sudo apt-get install alien"
                fi
                ;;
        esac
    fi
    
    # Install IPMICFG if available
    if [ -f "IPMICFG-Linux.x86_64" ]; then
        log "INFO" "Installing IPMICFG..."
        $SUDO_CMD cp IPMICFG-Linux.x86_64 /usr/local/bin/ipmicfg
        $SUDO_CMD chmod +x /usr/local/bin/ipmicfg
    fi
    
    # Install CPU-X if available
    if [ -f "CPU-X-5.3.1-x86_64.AppImage" ]; then
        log "INFO" "Installing CPU-X..."
        chmod +x CPU-X-5.3.1-x86_64.AppImage
        if [ ! -L "/usr/bin/cpu-x" ]; then
            $SUDO_CMD ln -sf "$(pwd)/CPU-X-5.3.1-x86_64.AppImage" /usr/bin/cpu-x
        fi
    else
        log "INFO" "Downloading CPU-X..."
        wget -q --show-progress "https://github.com/TheTumultuousUnicornOfDarkness/CPU-X/releases/download/5.3.1/CPU-X-5.3.1-x86_64.AppImage"
        chmod +x CPU-X-5.3.1-x86_64.AppImage
        $SUDO_CMD ln -sf "$(pwd)/CPU-X-5.3.1-x86_64.AppImage" /usr/bin/cpu-x
    fi
}

# Function to install Python dependencies (if needed for future cross-platform version)
install_python_dependencies() {
    log "INFO" "Installing Python dependencies..."
    
    if command_exists python3; then
        log "INFO" "Python 3 found, installing pip dependencies..."
        
        # Install pip if not available
        if ! command_exists pip3; then
            case "$OS_ID" in
                "ubuntu"|"debian")
                    $SUDO_CMD apt-get install -y python3-pip
                    ;;
                "rhel"|"centos"|"fedora")
                    $SUDO_CMD yum install -y python3-pip
                    ;;
                "macos")
                    brew install python3
                    ;;
            esac
        fi
        
        # Install Python packages
        pip3 install --user psutil py-cpuinfo click rich PyYAML loguru pandas numpy matplotlib seaborn
    else
        log "WARN" "Python 3 not found, skipping Python dependencies"
    fi
}

# Function to verify installations
verify_installations() {
    log "INFO" "Verifying installations..."
    
    local failed_checks=()
    local total_checks=0
    
    # Core tools
    local core_tools=("fio" "smartctl" "nvme" "parallel" "ipmitool" "dmidecode" "lspci" "hdparm" "bc" "jq")
    
    for tool in "${core_tools[@]}"; do
        ((total_checks++))
        if command_exists "$tool"; then
            log "INFO" "✓ $tool installed"
        else
            log "ERROR" "✗ $tool not found"
            failed_checks+=("$tool")
        fi
    done
    
    # Vendor tools
    if [ -L "/usr/bin/cpu-x" ] || [ -f "/usr/bin/cpu-x" ]; then
        log "INFO" "✓ CPU-X available"
    else
        log "WARN" "⚠ CPU-X not found"
    fi
    
    if command_exists arcconf; then
        log "INFO" "✓ arcconf available"
    else
        log "WARN" "⚠ arcconf not found (vendor-specific)"
    fi
    
    if command_exists ipmicfg; then
        log "INFO" "✓ ipmicfg available"
    else
        log "WARN" "⚠ ipmicfg not found (vendor-specific)"
    fi
    
    # Summary
    if [ ${#failed_checks[@]} -eq 0 ]; then
        log "INFO" "All core dependencies installed successfully!"
        return 0
    else
        log "ERROR" "Failed to install: ${failed_checks[*]}"
        log "INFO" "Please install missing dependencies manually"
        return 1
    fi
}

# Function to create test directories
create_directories() {
    log "INFO" "Creating test directories..."
    
    local dirs=("logs" "reports" "data" "temp" "tests")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "INFO" "Created directory: $dir"
        else
            log "INFO" "Directory exists: $dir"
        fi
    done
}

# Function to set up configuration
setup_configuration() {
    log "INFO" "Setting up configuration..."
    
    # Create config.yaml if it doesn't exist
    if [ ! -f "config.yaml" ]; then
        log "INFO" "Creating default config.yaml..."
        cat > config.yaml << 'EOF'
# Cross-Platform Server Testing Suite Configuration
app:
  name: "Cross-Platform Server Test Suite"
  version: "2.0.0"
  description: "Cross-platform server hardware testing and benchmarking"
  author: "Server Test Team"
  license: "MIT"

paths:
  base_dir: "."
  config_dir: "./config"
  scripts_dir: "./scripts"
  tests_dir: "./tests"
  logs_dir: "./logs"
  reports_dir: "./reports"
  data_dir: "./data"
  temp_dir: "./temp"

testing:
  runtime: 60
  loops: 2
  max_parallel_jobs: 8
  test_file_size: "100G"
  block_sizes:
    sequential: "128k"
    random: "4k"
    mixed: "64k"
  io_depths:
    sequential: [1, 2, 4, 8, 16, 32]
    random: [1, 2, 4, 8, 16, 32]
  num_jobs:
    sequential: [1, 2, 4, 8, 16, 32]
    random: [1, 2, 4, 8, 16, 32]

monitoring:
  interval: 10
  temperature_warning: 70
  temperature_critical: 85
  cpu_warning: 90
  cpu_critical: 95
  memory_warning: 90
  memory_critical: 95
  min_free_space: "10GB"
  health_check_interval: 300

hardware:
  auto_detect: true
  skip_os_disks: true
  skip_mounted_disks: true
  supported_disk_types: ["sata", "nvme", "sas", "scsi"]
  supported_platforms: ["linux", "windows", "macos"]

logging:
  level: "INFO"
  format: "{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}"
  rotation: "1 day"
  retention: "30 days"
  console_output: true
  file_output: true
  json_output: false

safety:
  require_confirmation: true
  max_concurrent_operations: 4
  backup_before_format: false
  dry_run_mode: false
EOF
    else
        log "INFO" "Configuration file exists: config.yaml"
    fi
}

# Function to display usage
usage() {
    echo -e "${CYN}Cross-Platform Server Testing Suite - Dependency Installer${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -v, --verbose        Enable verbose output"
    echo "  --skip-vendor        Skip vendor-specific tools"
    echo "  --skip-python        Skip Python dependencies"
    echo "  --verify-only        Only verify existing installations"
    echo ""
    echo "This script will:"
    echo "  1. Detect your operating system"
    echo "  2. Install all required dependencies"
    echo "  3. Set up vendor-specific tools"
    echo "  4. Create necessary directories"
    echo "  5. Verify all installations"
    echo ""
    echo "Supported operating systems:"
    echo "  - Ubuntu/Debian"
    echo "  - RHEL/CentOS/Fedora"
    echo "  - macOS (with Homebrew)"
    echo "  - Windows (with MSYS2/Cygwin)"
}

# Main function
main() {
    local verbose=false
    local skip_vendor=false
    local skip_python=false
    local verify_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --skip-vendor)
                skip_vendor=true
                shift
                ;;
            --skip-python)
                skip_python=true
                shift
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose mode
    if [ "$verbose" = true ]; then
        set -x
    fi
    
    # Display banner
    echo -e "${MAG}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAG}║              Cross-Platform Server Testing Suite              ║${NC}"
    echo -e "${MAG}║                    Dependency Installer                       ║${NC}"
    echo -e "${MAG}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Detect OS
    detect_os
    
    # Check privileges
    check_privileges
    
    if [ "$verify_only" = true ]; then
        verify_installations
        exit $?
    fi
    
    # Install dependencies
    log "INFO" "Starting dependency installation..."
    
    # Install package manager dependencies
    install_package_manager
    
    # Install core dependencies
    install_core_dependencies
    
    # Install vendor tools (unless skipped)
    if [ "$skip_vendor" = false ]; then
        install_vendor_tools
    else
        log "INFO" "Skipping vendor-specific tools"
    fi
    
    # Install Python dependencies (unless skipped)
    if [ "$skip_python" = false ]; then
        install_python_dependencies
    else
        log "INFO" "Skipping Python dependencies"
    fi
    
    # Create directories
    create_directories
    
    # Setup configuration
    setup_configuration
    
    # Verify installations
    if verify_installations; then
        echo ""
        echo -e "${GRN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GRN}║                    Installation Complete!                     ║${NC}"
        echo -e "${GRN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYN}Next steps:${NC}"
        echo -e "  1. Run tests: ${YEL}./servertest.sh${NC}"
        echo -e "  2. Check hardware: ${YEL}./scripts/hw_details.sh${NC}"
        echo -e "  3. Monitor system: ${YEL}./scripts/monitor_temp.sh temp.csv 30${NC}"
        echo ""
        echo -e "${CYN}For help:${NC}"
        echo -e "  - Run: ${YEL}./servertest.sh${NC} and select option 7 for device summary"
        echo -e "  - Check logs in: ${YEL}./logs/${NC}"
        echo ""
    else
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                   Installation Incomplete                     ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YEL}Please install missing dependencies manually and run:${NC}"
        echo -e "  ${YEL}$0 --verify-only${NC}"
        echo ""
        exit 1
    fi
}

# Run main function with all arguments
main "$@" 