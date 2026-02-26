#!/bin/bash
set -e

echo "=== AgentOS iOS Setup ==="

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen..."
    brew install xcodegen
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Build for simulator:"
echo "  xcodebuild build -project AgentOS.xcodeproj -scheme AgentOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -configuration Debug"
echo ""
echo "Build for device:"
echo "  xcodebuild build -project AgentOS.xcodeproj -scheme AgentOS -destination 'platform=iOS,id=DEVICE_UDID' -allowProvisioningUpdates"
echo ""
