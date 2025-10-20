#!/usr/bin/env sh

# SETUP OS
#
# Boot from OmniTribblix minimal ISO: https://iso.tribblix.org/iso/omnitribblix-0m37lx-minimal.iso
# Follow: http://www.tribblix.org/install.html
# (Install without any additional overlays)
# Reboot
# Get this script: curl -O https://raw.githubusercontent.com/russellallen/meridian/refs/heads/master/setup.sh
# Run the script: chmod +x setup.sh && ./setup.sh

echo WELCOME TO MERIDIAN SETUP FOR OMNITRIBBLIX 0m37

# Tasks:
#
#  0.  Check environment is as expected
#  1.  Create user
#      (would be nice for user home to be in own dataset)
#  2.  Set root password
#  3.  Install kitchen-sink
#  4.  Install xrdp
#  5.  Download and setup srv for xrdp and xrdp-sesman
#  6.  Download, build and install Tailscale
#      https://github.com/nshalman/tailscale

echo FINISHED
