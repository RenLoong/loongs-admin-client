---
name: LOONGS Admin PC 客户端
description: >-
  在 loongs-admin-client（Flutter PC：web/windows/macos/linux）项目根下开发界面、
  OAuth PKCE、API_BASE_URL/{host}、以及 pack.sh / pack.ps1 / pack.command 打包。
  项目根即本仓库根。不要用本技能改后端或 uni-app 仓库。
---

# LOONGS Admin PC（Flutter）

作用范围：**当前仓库根**（`RenLoong/loongs-admin-client`：含 `lib/`、`pack.*`、`.fvmrc`）。

对接后端默认 HTTP **21000**；打包后的 web 产物交给后端仓 `apps/Admin/public/web`（`--base-href /admin/web/`）。

## 何时用

- 改 `lib/`（登录、Render、Shell、健康检查、窗口标题栏）
- 改打包脚本或 FVM / `.fvmrc`
- `{host}`、PKCE loopback、Geist 字体重命名钩子

## 技术约定

- Flutter + **FVM**；版本**只认** `.fvmrc`（勿在脚本硬编码版本号）
- UI：shadcn_ui；业务字体以项目为准（Geist `[wght]` 由 `tools/fix_geist_font_names.py` 在打包时改 ASCII 名）
- API：`--dart-define=API_BASE_URL=…`
  - Web：`http://{host}:21000`（运行时替换页面 hostname）
  - 源码默认 fallback：`http://127.0.0.1:21000`（见 `lib/core/config.dart`）
- OAuth：授权码 + PKCE；桌面 loopback；**close 前缓存 `redirectUri`**（否则 `HttpServer is not bound`）
- Web 令牌：`WEB_TOKEN_STORAGE=auto|secure|session|memory`

## 打包（按 OS，勿混用）

| 脚本 | 系统 | 产物 |
|------|------|------|
| `./pack.sh` | Linux / WSL | web（默认）+ linux（`--linux`） |
| `.\pack.ps1` | Windows | web + windows（可选 Inno） |
| `./pack.command` | macOS | web + macos |

规则：

1. **只用本机原生 fvm**。`pack.sh` 拒绝 Windows `fvm.exe` 包装；WSL 不打 Windows 包。
2. **禁止**自动 `fvm install`；SDK 缺失则中断并提示手动安装。
3. Web 输出：后端仓的 `apps/Admin/public/web`（若 monorepo 相对路径仍可用；独立克隆则按脚本/文档指定目标目录）。
4. bash 陷阱：不要写 `${VAR:-http://{host}:21000}`（会变成 `http://{host:21000}`）。正确：

```bash
_DEFAULT_API_BASE_URL='http://{host}:21000'
API_BASE_URL="${API_BASE_URL:-$_DEFAULT_API_BASE_URL}"
```

5. Windows 从 `\\wsl$\…` 跑需 NTFS 暂存（脚本已处理）。

## 常见故障（客户端）

| 现象 | 处理 |
|------|------|
| `FormatException: Invalid port` + `{host:21000}` | 修 pack 默认值 / 重建 web |
| WSL fvm 走 Windows 缓存 | 去掉 fvm.exe 包装，装 Linux fvm，或改用 `pack.ps1` |
| 桌面登录 unbound | loopback 保存 redirectUri |
| OAuth redirect 不匹配 | 后端 `ADMIN_WEB_ORIGINS` 含当前访问 origin |

## Agent 习惯

- 不提交 `build/`、`dist/`、`.dart_tool/`；保留 `.fvmrc`。
- 跨平台打包提示去对应脚本，不要在 WSL 硬编 Windows。
