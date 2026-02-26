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

# Setup Fastlane (optional)
if command -v bundle &> /dev/null; then
    echo "Installing Fastlane dependencies..."
    bundle install
else
    echo "Note: Install Bundler (gem install bundler) to use Fastlane"
fi

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Available commands:"
echo ""
echo "  Build for simulator (Debug):"
echo "    xcodebuild build -project AgentOS.xcodeproj -scheme AgentOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -configuration Debug"
echo ""
echo "  Build for device (Release):"
echo "    xcodebuild build -project AgentOS.xcodeproj -scheme AgentOS -destination 'platform=iOS,id=DEVICE_UDID' -allowProvisioningUpdates"
echo ""
echo "  Fastlane - Build only:"
echo "    bundle exec fastlane ios build_only"
echo ""
echo "  Fastlane - Build and upload to TestFlight:"
echo "    bundle exec fastlane ios beta"
echo ""
