#!/usr/bin/env sh

# SETUP OS
#
# Boot from OmniTribblix minimal ISO: https://iso.tribblix.org/iso/omnitribblix-0m37lx-minimal.iso
# Follow: http://www.tribblix.org/install.html
# (Install without any additional overlays)
# Reboot
# Get this script: curl -O https://raw.githubusercontent.com/russellallen/meridian/refs/heads/master/setup.sh
# Run the script: chmod +x setup.sh && ./setup.sh
#
#
# Other steps:
#
# Create new SSH key and add to GitHub: ssh-keygen -t ed25519 -C "your_email@example.com"
# 

# Exit on error
set -e

# Global variables
USERNAME=""

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

check_environment() {
    echo ""
    echo "Task 0: Checking environment..."
    echo "-------------------------------"

    # Check if running as root
    if [ "$(id -u)" != "0" ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi

    # Check if this is OmniTribblix
    if [ ! -f "/etc/release" ]; then
        echo "ERROR: /etc/release not found - may not be OmniTribblix"
        exit 1
    fi

    # Check version
    if ! grep -q "OmniTribblix" /etc/release; then
        echo "WARNING: This doesn't appear to be OmniTribblix"
        echo "Contents of /etc/release:"
        cat /etc/release
        echo ""
        printf "Continue anyway? (y/N): "
        read -r response
        case "$response" in
            [yY]) echo "Continuing...";;
            *) echo "Exiting..."; exit 1;;
        esac
    fi

    echo "Environment check passed"
}

create_user() {
    echo ""
    echo "Task 1: Creating user..."
    echo "------------------------"

    printf "Enter username to create: "
    read -r USERNAME

    if [ -z "$USERNAME" ]; then
        echo "ERROR: Username cannot be empty"
        exit 1
    fi

    # Check if user already exists
    if id "$USERNAME" >/dev/null 2>&1; then
        echo "User $USERNAME already exists, skipping creation"
    else
        printf "Enter full name for user (or press Enter to skip): "
        read -r FULLNAME
        
        # Check if we can create a ZFS dataset for the user
        POOL=$(zfs list -H -o name | head -1 | cut -d'/' -f1)
        
        if [ -n "$POOL" ]; then
            printf "Create ZFS dataset for user home? (y/N): "
            read -r response
            case "$response" in
                [yY])
                    echo "Creating ZFS dataset for user home..."
                    zfs create -o mountpoint=/export/home/$USERNAME $POOL/export/home/$USERNAME 2>/dev/null || \
                    zfs create -o mountpoint=/export/home/$USERNAME $POOL/home/$USERNAME 2>/dev/null || \
                    echo "WARNING: Could not create ZFS dataset, using regular directory"
                    ;;
                *)
                    echo "Using regular directory for user home"
                    ;;
            esac
        fi
        
        # Create the user
        if [ -n "$FULLNAME" ]; then
            useradd -m -d /export/home/$USERNAME -s /bin/bash -c "$FULLNAME" "$USERNAME"
        else
            useradd -m -d /export/home/$USERNAME -s /bin/bash "$USERNAME"
        fi
        
        # Set password for the new user
        echo "Please set password for user $USERNAME:"
        passwd "$USERNAME"
        
        # Add user to useful groups
        usermod -G staff,adm "$USERNAME" 2>/dev/null || true
        
        echo "User $USERNAME created successfully"
    fi
}

set_root_password() {
    echo ""
    echo "Task 2: Setting root password..."
    echo "---------------------------------"

    printf "Change root password? (y/N): "
    read -r response
    case "$response" in
        [yY])
            passwd root
            echo "Root password updated"
            ;;
        *)
            echo "Skipping root password change"
            ;;
    esac
}

install_kitchen_sink() {
    echo ""
    echo "Task 3: Installing kitchen-sink overlay..."
    echo "-------------------------------------------"

    # Update package catalog first
    echo "Updating package catalog..."
    /usr/bin/zap refresh

    # Install kitchen-sink overlay if not already installed
    if /usr/bin/zap list-overlays | grep -q kitchen-sink; then
        echo "kitchen-sink overlay already installed"
    else
        echo "Installing kitchen-sink overlay..."
        /usr/bin/zap install-overlay kitchen-sink
        echo "kitchen-sink overlay installed successfully"
    fi
}

install_xrdp() {
    echo ""
    echo "Task 4: Installing xrdp..."
    echo "---------------------------"

    # Check if xrdp is available and install it
    if pkg list -a | grep -q xrdp; then
        if pkg list | grep -q xrdp; then
            echo "xrdp already installed"
        else
            echo "Installing xrdp package..."
            /usr/bin/zap install TRIBxrdp || pkg install xrdp || {
                echo "WARNING: Could not install xrdp via package manager"
                echo "You may need to build from source"
            }
        fi
    else
        echo "WARNING: xrdp package not found in repositories"
        echo "You may need to build from source or add additional overlays"
    fi
}

setup_xrdp_services() {
    echo ""
    echo "Task 5: Setting up SMF services for xrdp..."
    echo "--------------------------------------------"

    # Create SMF manifest directory if it doesn't exist
    mkdir -p /lib/svc/manifest/network

    # Create xrdp SMF manifest
    cat > /lib/svc/manifest/network/xrdp.xml << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type="manifest" name="xrdp">
  <service name="network/xrdp" type="service" version="1">
    <create_default_instance enabled="false" />
    <single_instance />
    
    <dependency name="network" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/milestone/network:default" />
    </dependency>
    
    <dependency name="filesystem" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/system/filesystem/local:default" />
    </dependency>
    
    <exec_method type="method" name="start" exec="/usr/sbin/xrdp" timeout_seconds="60" />
    <exec_method type="method" name="stop" exec=":kill" timeout_seconds="60" />
    
    <property_group name="startd" type="framework">
      <propval name="duration" type="astring" value="contract" />
    </property_group>
    
    <stability value="Unstable" />
  </service>
</service_bundle>
EOF

    # Create xrdp-sesman SMF manifest
    cat > /lib/svc/manifest/network/xrdp-sesman.xml << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type="manifest" name="xrdp-sesman">
  <service name="network/xrdp-sesman" type="service" version="1">
    <create_default_instance enabled="false" />
    <single_instance />
    
    <dependency name="network" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/milestone/network:default" />
    </dependency>
    
    <dependency name="filesystem" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/system/filesystem/local:default" />
    </dependency>
    
    <exec_method type="method" name="start" exec="/usr/sbin/xrdp-sesman" timeout_seconds="60" />
    <exec_method type="method" name="stop" exec=":kill" timeout_seconds="60" />
    
    <property_group name="startd" type="framework">
      <propval name="duration" type="astring" value="contract" />
    </property_group>
    
    <stability value="Unstable" />
  </service>
</service_bundle>
EOF

    # Import the services
    echo "Importing SMF services..."
    svccfg import /lib/svc/manifest/network/xrdp.xml
    svccfg import /lib/svc/manifest/network/xrdp-sesman.xml

    # Enable the services
    printf "Enable xrdp services now? (y/N): "
    read -r response
    case "$response" in
        [yY])
            svcadm enable network/xrdp-sesman
            svcadm enable network/xrdp
            echo "xrdp services enabled"
            echo "Checking service status:"
            svcs -xv network/xrdp network/xrdp-sesman
            ;;
        *)
            echo "Services imported but not enabled"
            echo "To enable later, run:"
            echo "  svcadm enable network/xrdp-sesman"
            echo "  svcadm enable network/xrdp"
            ;;
    esac
}

install_tailscale() {
    echo ""
    echo "Task 6: Installing Tailscale..."
    echo "--------------------------------"

    printf "Install Tailscale? (y/N): "
    read -r response
    case "$response" in
        [yY])
            # Check for required build tools
            if ! command -v go >/dev/null 2>&1; then
                echo "Installing Go compiler..."
                /usr/bin/zap install TRIBv-go-121 || /usr/bin/zap install TRIBv-go-120 || {
                    echo "ERROR: Could not install Go compiler"
                    echo "Please install Go manually and re-run this section"
                    exit 1
                }
            fi
            
            if ! command -v git >/dev/null 2>&1; then
                echo "Installing git..."
                /usr/bin/zap install TRIBdev-versioning-git || {
                    echo "ERROR: Could not install git"
                    exit 1
                }
            fi
            
            # Create build directory
            BUILD_DIR="/tmp/tailscale-build-$$"
            mkdir -p "$BUILD_DIR"
            cd "$BUILD_DIR"
            
            # Clone the repository
            echo "Cloning Tailscale repository..."
            git clone https://github.com/nshalman/tailscale.git
            cd tailscale
            
            # Checkout the illumos branch if it exists
            git checkout illumos 2>/dev/null || echo "Using default branch"
            
            # Build Tailscale
            echo "Building Tailscale (this may take a while)..."
            go build ./cmd/tailscale
            go build ./cmd/tailscaled
            
            # Install binaries
            echo "Installing Tailscale binaries..."
            cp tailscale /usr/bin/
            cp tailscaled /usr/sbin/
            chmod 755 /usr/bin/tailscale /usr/sbin/tailscaled
            
            # Create SMF manifest for tailscaled
            cat > /lib/svc/manifest/network/tailscaled.xml << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type="manifest" name="tailscaled">
  <service name="network/tailscaled" type="service" version="1">
    <create_default_instance enabled="false" />
    <single_instance />
    
    <dependency name="network" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/milestone/network:default" />
    </dependency>
    
    <dependency name="filesystem" grouping="require_all" restart_on="none" type="service">
      <service_fmri value="svc:/system/filesystem/local:default" />
    </dependency>
    
    <exec_method type="method" name="start" exec="/usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state" timeout_seconds="60" />
    <exec_method type="method" name="stop" exec=":kill" timeout_seconds="60" />
    
    <property_group name="startd" type="framework">
      <propval name="duration" type="astring" value="contract" />
    </property_group>
    
    <stability value="Unstable" />
  </service>
</service_bundle>
EOF
            
            # Create state directory
            mkdir -p /var/lib/tailscale
            
            # Import the service
            svccfg import /lib/svc/manifest/network/tailscaled.xml
            
            # Clean up build directory
            cd /
            rm -rf "$BUILD_DIR"
            
            echo "Tailscale installed successfully"
            echo "To start Tailscale:"
            echo "  svcadm enable network/tailscaled"
            echo "  tailscale up"
            ;;
        *)
            echo "Skipping Tailscale installation"
            ;;
    esac
}

print_summary() {
    echo ""
    echo "================================================"
    echo "FINISHED"
    echo ""
    echo "Summary:"
    echo "--------"
    echo "1. User account configured"
    echo "2. Root password set (if requested)"
    echo "3. kitchen-sink overlay installed"
    echo "4. xrdp installation attempted"
    echo "5. SMF services for xrdp configured"
    echo "6. Tailscale installed (if requested)"
    echo ""
    echo "Next steps:"
    echo "-----------"
    echo "1. Verify services are running: svcs -xv"
    echo "2. Configure xrdp if needed: /etc/xrdp/xrdp.ini"
    echo "3. Start Tailscale if installed: tailscale up"
    echo "4. Reboot if needed: init 6"
    echo ""
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

echo "WELCOME TO MERIDIAN SETUP FOR OMNITRIBBLIX 0m37"
echo "==============================================="

# Execute all tasks in sequence
check_environment
create_user
set_root_password
install_kitchen_sink
install_xrdp
setup_xrdp_services
install_tailscale
print_summary
