#!/bin/sh

xcodebuild \
  -project ~/code/bhq/knowledged-mac/KnowledgedMac.xcodeproj \
  -scheme KnowledgedMac \
  -configuration Release \
  -derivedDataPath /tmp/knowledged-mac-build \
  build

cp -R /tmp/knowledged-mac-build/Build/Products/Release/KnowledgedMac.app \
      /Applications/

