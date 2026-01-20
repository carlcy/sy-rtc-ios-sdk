#!/bin/bash
# 构建 XCFramework 脚本
# 注意：这需要先在 Xcode 中创建 Framework 项目

set -e

PROJECT_NAME="SyRtcSDK"
FRAMEWORK_NAME="SyRtcSDK"
BUILD_DIR="build"
XCFRAMEWORK_PATH="${BUILD_DIR}/${FRAMEWORK_NAME}.xcframework"

echo "=========================================="
echo "构建 SyRtcSDK XCFramework"
echo "=========================================="

# 清理
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}

echo ""
echo "请按照以下步骤操作："
echo ""
echo "1. 在 Xcode 中创建 Framework 项目："
echo "   - File → New → Project"
echo "   - 选择 'Framework'"
echo "   - 项目名称：${FRAMEWORK_NAME}"
echo "   - Language: Swift"
echo ""
echo "2. 将 Sources/SyRtcSDK 中的 Swift 文件添加到项目"
echo ""
echo "3. 配置 Build Settings："
echo "   - Build Libraries for Distribution = YES"
echo "   - Skip Install = NO"
echo ""
echo "4. 运行以下命令构建："
echo ""
echo "# 构建 iOS 设备版本"
echo "xcodebuild archive \\"
echo "  -scheme ${FRAMEWORK_NAME} \\"
echo "  -archivePath ${BUILD_DIR}/ios.xcarchive \\"
echo "  -sdk iphoneos \\"
echo "  SKIP_INSTALL=NO"
echo ""
echo "# 构建模拟器版本"
echo "xcodebuild archive \\"
echo "  -scheme ${FRAMEWORK_NAME} \\"
echo "  -archivePath ${BUILD_DIR}/ios-sim.xcarchive \\"
echo "  -sdk iphonesimulator \\"
echo "  SKIP_INSTALL=NO"
echo ""
echo "# 创建 XCFramework"
echo "xcodebuild -create-xcframework \\"
echo "  -framework ${BUILD_DIR}/ios.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework \\"
echo "  -framework ${BUILD_DIR}/ios-sim.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework \\"
echo "  -output ${XCFRAMEWORK_PATH}"
echo ""
echo "生成的 XCFramework 位于：${XCFRAMEWORK_PATH}"

