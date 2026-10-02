# Lingmo OS ISO Builder

从自建 RPM 包 + Fedora 仓库组装 Lingmo OS 5 (Unstable) 的 live ISO，并在 GitHub Actions 里自动构建、发布。

工程结构仿照 Linux 内核：`Kconfig` 配置系统 + `make` 目标链 + 按职责拆分的目录。

## 产物

- **ISO 命名格式**：`lingmoOS_5_Unstable_<YYMMDD>_amd64.iso`（例如 `lingmoOS_5_Unstable_260905_amd64.iso`）
- **发布**：每次 push 到 `main` 或手动触发，自动构建 ISO 并发布到 GitHub Release，tag 为 `iso-<YYYYMMDD>`。
- **分片**：GitHub Release 单个文件上限 2 GiB。若 ISO 超过 2 GiB，会自动用 `split` 分片上传，每个分片 `~1.9 GiB`。合并方式：`cat lingmoOS_5_Unstable_*.iso.part* > lingmoOS_5_Unstable_<date>_amd64.iso`。

## 快速开始（本地）

```bash
# 前置：Fedora 环境，root 权限
sudo dnf install -y livecd-tools createrepo_c git python3

make defconfig    # 生成 .config（默认 = Desktop live 类型）
make sync         # 用 git-repo + default.xml 拉取全部源码到 ../gnome-source
make iso          # 渲染 kickstart → 下载自建 RPM → livecd-creator 出 ISO
```

> `livecd-creator` 需要 root（挂载 loop、chroot），约 8–10 GB 磁盘。
> CI 不做 `make sync`/`make defconfig`：裸检出直接 `bash build-iso.sh`，
> 渲染器回退到 Kconfig 默认值，产出与拆分前逐字节一致的 `lingmo-live.ks`。

## make 目标

| 目标 | 作用 |
|---|---|
| `make defconfig` | `configs/desktop.config` → `.config` |
| `make menuconfig` | 交互式配置 UI（vendored kconfiglib） |
| `make oldconfig` | Kconfig 变更后刷新 `.config`（自动补新符号） |
| `make sync` | `scripts/sync-repos.sh`：git-repo 同步 `default.xml` 全部项目 |
| `make ks` | `lib/render-ks.py`：core/ks 片段 + `.config` → `lingmo-live.ks` |
| `make pkg-<name>` | `lib/build_pkg.py`：从源码检出构建单个自建 RPM |
| `make pkg` | 构建 `.config` 中所有 `PKG_*=y` 的自建 RPM |
| `make iso` | 渲染 kickstart + `scripts/build-iso.sh` 出 ISO |
| `make clean` | 清理生成物 |

## 目录结构

| 路径 | 作用 |
|---|---|
| `Kconfig` / `configs/` | 内核式配置系统：ISO 类型、镜像标识、系统默认值 |
| `pkg/Kconfig.pkg` | **自动生成**（`scripts/gen-pkg-config.py` ← `repos.txt`），每包一个 `PKG_<NAME>` 符号 |
| `default.xml` | git-repo manifest：92 个项目（79 组件 + lingmo-release + 12 installer），remote = `https://github.com/Matrinsoft/` |
| `scripts/` | `sync-repos.sh`（源码同步）、`fetch-rpms.sh`（下载自建 RPM）、`build-iso.sh`（ISO 主流程）、`kconfiglib.py`/`menuconfig.py`（menuconfig 实现） |
| `core/ks/` | kickstart 片段：`00-header` + `10-packages-<type>` + `20-post-<type>` + `20-post-common` |
| `lib/` | `render-ks.py`（片段渲染）、`build_pkg.py`（RPM 构建）、`patch-imgcreate.py` |
| `boot/verify-iso.py` | ISO 内容门禁：initrd/kernel/squashfs/EFI 缺失或过小即失败 |
| `pkg/*.mk` | （可选）单包构建规则覆盖，自动被 Makefile include |
| `lingmo-live.ks` | 渲染产物（提交在库里；`make ks` / `make iso` 会重新生成） |
| `repos.txt` | 自建包的 GitHub 短名清单（68 个），驱动 `fetch-rpms` 与 `pkg/Kconfig.pkg` |

## ISO 类型（`make menuconfig` → "ISO type"）

| 类型 | 片段集 | 说明 |
|---|---|---|
| Desktop live | `10-packages-desktop` + `20-post-desktop` | GNOME 桌面、GDM 自动登录（默认） |
| Server | `10-packages-server` + `20-post-server` + `20-post-common` | 无图形界面 |
| Minimal | `10-packages-minimal` + `20-post-minimal` + `20-post-common` | 最小集 |
| Installable | `10-packages-installable` + `20-post-installable` + `20-post-common` | Anaconda WebUI 安装器镜像（anaconda + anaconda-webui + sshd，multi-user 启动） |

片段以一个空行拼接（`\n\n`），DESKTOP 渲染结果与拆分前的单体 kickstart 逐字节一致。
渲染 token 为 `@UPPER_CASE@`（`SYS_LANG`/`ROOT_SIZE_MB`/`LIVE_USER` 等）。

## 源码同步（make sync）

`scripts/sync-repos.sh` 使用官方 Android [repo 工具](https://github.com/GerritCodeReview/git-repo)（完整克隆到 `../gnome-source/.repo-tools/`）：

1. **采纳既有检出**：manifest 中已存在的手工克隆被移为 `<path>.legacy`，
   并通过 `url.*.insteadOf` 让 repo 从本地克隆取历史（保留未推送提交）。
   **每个项目都注册规则**（git 取最长前缀匹配，防止 `anaconda` 劫持 `anaconda-l10n`）。
   detached 的 legacy 缺 `refs/heads/<rev>` 时自动从 `origin/<rev>` 补建。
2. `repo init --partial-clone -b main -u <manifest>` + `repo sync`。
3. remote URL 规范化回 `https://github.com/Matrinsoft/<name>`。
4. 有 `.gitmodules` 的项目（anaconda 系）初始化子模块；vte291 的杂散
   gitlink 无 `.gitmodules`，跳过。
5. 对 vendored git-repo 打了「允许路径含 `~`」补丁（Fedora NEVRA 目录名
   如 `51~beta-1`，上游为 Windows 8.3 文件名而拒绝）——补丁提交在工具
   克隆里，`sync-repos.sh` 幂等应用。

前置：`default.xml` 必须已提交（`repo init` 克隆的只是已提交状态）。

## 自建 RPM（make pkg-\<name\>）

组件树是 Fedora SRPM 布局（`<name>.spec` + 解包后的 `<name>-<ver>/`，无 tarball）：

1. `rpmspec -P` 解析出宏全展开的 `Name/Version/Source/Patch`；
2. 缺失的源码 tarball 从解包目录重新打包（如 `baobab-50.0` → `baobab-50.0.tar.xz`）；
3. `rpmbuild -ba` 构建，RPM 复制到 `$REPO_DIR`（默认 `/tmp/lingmo-repo`，
   与 `fetch-rpms.sh` 同一目录）；
4. 有 `createrepo_c` 则顺带更新仓库元数据。

构建依赖用 `dnf builddep <spec>` 安装。`.config` 里 `PKG_<NAME>=y`（menuconfig
"Self-built packages"）的包会被 `make pkg` 批量构建。

## 包来源策略

| 来源 | 包 | 说明 |
|---|---|---|
| **自建**（`repos.txt` 68 个仓库） | gnome-shell、mutter、nautilus、gtk4、glib2 等 + `lingmo-release` | CI 从 GitHub Release 拉 RPM；本地可用 `make pkg-*` 从源码构建，组成本地 repo，**cost=1 最高优先**，覆盖 Fedora 同名包 |
| **Fedora 45 仓库** | kernel、grub2、plymouth、systemd、mesa 等；以及 `gst-thumbnailers`、`gnome-user-share`、`loupe`、`snapshot`、`librsvg2`、`papers` | crate 版本等原因未自建，直接采用 Fedora 官方包 |

> 优先级由 kickstart repo `--cost` 控制：`lingmo`(1) > `fedora`(200) > `fedora-updates`(300)。

## CI（.github/workflows/build-iso.yml，未改动）

1. `fedora:45` 容器安装 `livecd-tools`、`createrepo_c`；
2. 根目录 `bash build-iso.sh`（薄壳：渲染 kickstart → `scripts/build-iso.sh`）；
3. `fetch-rpms.sh` 下载自建 RPM（跳过 debuginfo）→ `createrepo_c`；
4. `livecd-creator` 出 ISO → 改名 → `boot/verify-iso.py` 内容门禁；
5. 上传 release（>2 GiB 自动分片）。

## 常见问题

- **构建超时/磁盘不足**：live ISO 构建 30–60 分钟、约 8–10 GB 磁盘。
- **自建包缺失导致依赖失败**：dnf 回退到 Fedora 同名包；否则报依赖错误。
- **ISO 大于 2 GiB**：自动分片，按分片文件名顺序 `cat` 合并。
- **`make sync` 报 `default.xml ... not committed`**：manifest 克隆只含已提交
  文件，先提交 `default.xml`。
- **ISO 内容门禁失败**：CI 日志搜 `Module '...' cannot be found`（dracut
  模块缺失会导致 initrd 静默缺失）。
