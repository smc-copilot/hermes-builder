# SMC Copilot Hermes MSI 安装失败修复方案 PRD

## 1. 文档信息

  项目       内容
  ---------- ----------------------------------------------
  文档名称   SMC Copilot Hermes MSI CustomAction 修复方案
  产品       SMC Copilot Hermes
  版本       0.21.0
  文档类型   技术需求 PRD
  优先级     P0
  状态       修复实施
  日期       2026-09-22

------------------------------------------------------------------------

# 2. 背景与问题描述

## 2.1 背景

SMC Copilot Hermes 当前通过 `hermes-builder` 构建 Windows MSI 安装包：

    copilot-hermes-enterprise-0.21.0-win-x64.msi

安装过程中 Windows Installer 返回：

    安装成功或错误状态: 1603

1603 表示 MSI 执行阶段发生致命错误。

## 2.2 问题现象

安装日志显示：

-   MSI 文件加载正常；
-   InstallFiles 阶段正常完成；
-   Hermes 文件已经复制到：

```{=html}
<!-- -->
```
    C:\Users\Administrator\AppData\Local\hermes\

-   失败发生在执行 PreflightHermes CustomAction 阶段。

日志关键：

    CustomAction PreflightHermes returned actual error code 1603

------------------------------------------------------------------------

# 3. 问题分析

## 3.1 当前安装流程

    MSI Install

        |
        v

    InstallFiles

        |
        v

    SetPreflightHermes

        |
        v

    PreflightHermes CustomAction

        |
        v

    Initialize Hermes

当前失败节点：

    PreflightHermes

------------------------------------------------------------------------

## 3.2 根因定位

错误日志：

    WixQuietExec:
    Error 0x80070057:
    Failed to get command line data

    WixQuietExec:
    Error 0x80070057:
    Failed to get Command Line

    WixQuietExec:
    Error 0x80070057:
    Failed in ExecCommon method

判断：

不是 PowerShell 脚本错误。

不是：

-   文件缺失
-   权限不足
-   offline cache 不完整
-   Hermes runtime 初始化失败

而是：

WiX WixQuietExec CustomAction 没有正确获取执行命令参数。

------------------------------------------------------------------------

# 4. 修复目标

## 4.1 功能目标

修复 MSI 安装阶段：

    PreflightHermes CustomAction

确保：

-   正确调用 PowerShell；
-   正确传递 HermesHome；
-   正确执行安装前检查；
-   安装失败时输出明确日志。

------------------------------------------------------------------------

# 5. 技术方案

## 5.1 CustomAction 修复

当前问题：

    WixQuietExec
            |
            |
            +-- CommandLine 未正确绑定

调整：

增加显式 CommandLine Property。

目标：

    SetPreflightHermes

            |
            v

    PreflightHermes

            |
            v

    powershell.exe

------------------------------------------------------------------------

## 5.2 WiX 配置调整

修改 wix 文件：

目标文件：

    installer/*.wxs

调整内容：

### 增加执行参数 Property

示例：

``` xml
<CustomAction
    Id="SetPreflightHermes"
    Property="PreflightHermes"
    Value="powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[HermesRoot]bootstrap\Preflight-HermesInstall.ps1&quot; -HermesHome &quot;[HermesRoot]&quot;" />
```

------------------------------------------------------------------------

### 修正 CustomAction 调用

确保：

``` xml
<CustomAction
    Id="PreflightHermes"
    BinaryRef="Wix4UtilCA"
    DllEntry="WixQuietExec"
    Execute="deferred"
    Return="check"
    Impersonate="yes" />
```

能够读取：

    PreflightHermes Property

------------------------------------------------------------------------

## 5.3 执行顺序调整

InstallExecuteSequence：

    InstallFiles

        ↓

    SetPreflightHermes

        ↓

    PreflightHermes

        ↓

    InitializeHermes

确保：

-   文件已经复制；
-   PowerShell 脚本存在；
-   参数已经设置。

------------------------------------------------------------------------

# 6. 日志增强要求

## 6.1 当前问题

失败时只有：

    1603

无法快速定位。

------------------------------------------------------------------------

## 6.2 新增安装日志

要求：

增加：

    C:\Users\<user>\AppData\Local\hermes\logs\install.log

记录：

-   Preflight 执行结果；
-   PowerShell 输出；
-   Runtime 检测结果；
-   Python/Node 检测结果。

------------------------------------------------------------------------

# 7. 验收标准

## 7.1 安装验收

  项目               标准
  ------------------ ------
  MSI 启动           正常
  InstallFiles       成功
  PreflightHermes    成功
  InitializeHermes   成功
  MSI 返回码         0

------------------------------------------------------------------------

## 7.2 文件验收

安装完成后：

    %LOCALAPPDATA%\hermes

存在：

    bin
    bootstrap
    python
    node
    offline
    hermes-agent
    defaults

------------------------------------------------------------------------

## 7.3 回归测试

测试环境：

-   Windows 10
-   Windows 11
-   管理员安装
-   普通用户安装

测试：

1.  首次安装
2.  升级安装
3.  卸载
4.  重装

------------------------------------------------------------------------

# 8. 实施计划

## Phase 1: WiX 修复

负责人：

开发工程师

任务：

-   修改 CustomAction 定义；
-   修正 CommandLine 传递；
-   增加日志。

------------------------------------------------------------------------

## Phase 2: MSI重新构建

任务：

执行：

    hermes-builder build

生成：

    copilot-hermes-enterprise-0.21.0-win-x64.msi

------------------------------------------------------------------------

## Phase 3: 安装验证

执行：

    msiexec /i xxx.msi /L*v hermes-install.log

确认：

    PreflightHermes returned success

------------------------------------------------------------------------

# 9. 风险

  风险                     影响                   措施
  ------------------------ ---------------------- ------------------------
  WiX版本差异              CustomAction语法变化   固定WiX版本
  PowerShell策略限制       脚本执行失败           ExecutionPolicy Bypass
  用户权限不足             目录创建失败           增加权限检测
  企业软件分发SYSTEM模式   LocalAppData异常       增加安装模式检测

------------------------------------------------------------------------

# 10. 最终交付

交付内容：

1.  WiX CustomAction 修复代码
2.  新版 MSI
3.  MSI verbose 安装日志
4.  安装测试报告
5.  发布说明
