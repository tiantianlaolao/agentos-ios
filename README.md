# AgentOS iOS

AgentOS 的 iOS 原生客户端，使用 Swift 构建。AgentOS 是一个 AI Agent 通用客户端平台，定位为"Agent 时代的浏览器"。

## 技术栈

- **语言**: Swift 6.0
- **最低版本**: iOS 17.0
- **架构**: MVVM + Service Layer
- **并发**: @Observable + async/await
- **项目管理**: XcodeGen + SPM
- **CI/CD**: Fastlane (TestFlight 上传)

## 依赖

| 包 | 用途 |
|---|------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 本地 SQLite 数据库 |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown 渲染 |

## 项目结构

```
AgentOS/
├── AgentOSApp.swift          # App 入口
├── ContentView.swift          # 根视图 (TabView)
├── Models/                    # 数据模型
│   ├── APIModels.swift
│   ├── ChatMessage.swift
│   ├── Conversation.swift
│   ├── Protocol.swift
│   └── SkillModels.swift
├── ViewModels/                # 视图模型
│   ├── AuthViewModel.swift
│   ├── ChatViewModel.swift
│   ├── MemoryViewModel.swift
│   ├── SettingsViewModel.swift
│   └── SkillsViewModel.swift
├── Views/                     # UI 视图
│   ├── Chat/                  # 聊天界面 (Telegram 风格)
│   ├── Login/                 # 登录/注册
│   ├── Memory/                # 记忆管理
│   ├── Settings/              # 设置页面
│   └── Skills/                # Skill 管理面板
├── Services/                  # 服务层
│   ├── DatabaseService.swift       # GRDB 本地存储
│   ├── WebSocketService.swift      # WebSocket 通信
│   ├── HostedAPIService.swift      # 托管模式 API
│   ├── MemoryAPIService.swift      # 记忆 API
│   ├── DirectLLMService.swift      # 直连 LLM
│   ├── OpenClawDirectService.swift # OpenClaw 直连
│   └── DeviceIdentityService.swift # 设备身份
├── Extensions/                # Swift 扩展
├── Theme/                     # 主题配置
├── Localization/              # 国际化 (中/英)
└── Resources/                 # 资源文件
    ├── Info.plist
    └── Assets.xcassets
```

## 开发环境

- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Fastlane](https://fastlane.tools) (可选，用于 TestFlight 上传)

## 构建运行

```bash
# 1. 生成 Xcode 项目
xcodegen generate

# 2. 打开项目
open AgentOS.xcodeproj

# 3. 或者命令行构建 (真机)
xcodebuild -project AgentOS.xcodeproj \
  -scheme AgentOS \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build

# 4. 安装到设备
xcrun devicectl device install app --device <DEVICE_ID> build/Build/Products/Debug-iphoneos/AgentOS.app
```

## TestFlight 发布

```bash
# 需要先配置 App Store Connect API Key
# 将 .p8 文件放到 ~/.appstoreconnect/ 目录

fastlane ios beta
```

## 功能模块

- **多 Agent 聊天**: 支持多个 AI Agent 会话，Telegram 风格 UI
- **托管模式**: 通过邀请码激活，服务端托管 AI 模型
- **直连模式**: 用户自带 API Key，直接调用 LLM
- **OpenClaw 集成**: 支持 OpenClaw AI 助手
- **Skill 系统**: 查看、安装、生成 Skill，支持 MCP Server
- **记忆管理**: AI 对话记忆的查看与管理
- **设备身份**: 自动生成设备指纹，无需注册即可使用
- **国际化**: 中英文双语支持

## 关联项目

- [AgentOS](https://github.com/tiantianlaolao/agentos) - 服务端 + Android/桌面端

## License

Private
