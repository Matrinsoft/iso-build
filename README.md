# Lingmo OS ISO Builder

从自建 RPM 包 + Fedora 仓库组装 Lingmo OS 5 (Unstable) 的 live ISO，并在 GitHub Actions 里自动构建、发布。

工程结构仿照 Linux 内核：`Kconfig` 配置系统 + `make` 目标链 + 按职责拆分的目录。

## 产物

- **ISO 命名格式**：`lingmoOS_5_Unstable_<类型>_<YYMMDD>_amd64.iso`（例如
  `lingmoOS_5_Unstable_desktop_261010_amd64.iso`、`lingmoOS_5_Unstable_installable_261010_amd64.iso`）。
  类型取自配置文件名的 `<类型>.config`，同一天的不同类型镜像互不覆盖。
- **发布**：每次 push 到 `main`（默认构建 desktop）或手动触发，自动构建 ISO 并发布到 GitHub Release，
  tag 为 `iso-<YYYYMMDD>`；同一天重新构建时只清理**同类型**的旧资产。
  手动构建指定类型：`gh workflow run build-iso.yml -f iso_config=installable`（可选 `desktop`/`installable`）。
- **分片**：GitHub Release 单个文件上限 2 GiB。若 ISO 超过 2 GiB，会自动用 `split` 分片上传，每个分片 `~1.9 GiB`。合并方式：`cat lingmoOS_5_Unstable_*.iso.part* > lingmoOS_5_Unstable_<date>_amd64.iso`。

## 快速开始（本地）

```bash
# 前置：Fedora 环境，root 权限
sudo dnf install -y livecd-tools createrepo_c git python3

make sync         # 用 git-repo + default.xml 拉取全部源码到 ../gnome-source
make iso          # 渲染 kickstart → 下载自建 RPM → livecd-creator 出 ISO

# 指定 ISO 类型（不指定则用 configs/desktop.config）：
ISO_CONFIG=configs/installable.config bash build-iso.sh   # 安装器镜像（Anaconda WebUI）
make defconfig KCONFIG_CONFIG=.config.installable && \
  cp configs/installable.config .config.installable && make iso   # 等价的 make 用法
```

> `livecd-creator` 需要 root（挂载 loop、chroot），约 8–10 GB 磁盘。
> CI 不做 `make sync`；`bash build-iso.sh` 用 `$ISO_CONFIG` 指定配置，
> **push 默认构建 `configs/desktop.config`（GNOME 桌面 live 镜像）**，
> 安装器镜像用 `gh workflow run build-iso.yml -f iso_config=installable`。

## make 目标

| 目标 | 作用 |
|---|---|
| `make defconfig` | `configs/desktop.config` → `.config` |
| `ISO_CONFIG=<file> bash build-iso.sh` | 用指定配置渲染 kickstart（`configs/desktop.config` / `configs/installable.config`） |
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
| Desktop live | `10-packages-desktop` + `20-post-desktop` | GNOME 桌面、GDM 自动登录（`configs/desktop.config`，`make defconfig` 默认） |
| Server | `10-packages-server` + `20-post-server` + `20-post-common` | 无图形界面 |
| Minimal | `10-packages-minimal` + `20-post-minimal` + `20-post-common` | 最小集 |
| Installable | `10-packages-installable` + `20-post-installable` + `20-post-common` | Anaconda WebUI 安装器镜像（anaconda + anaconda-webui + sshd，multi-user 启动，**无桌面**）；`configs/installable.config` |

片段以一个空行拼接（`\n\n`），DESKTOP 渲染结果与拆分前的单体 kickstart 逐字节一致。
渲染 token 为 `@UPPER_CASE@`（`SYS_LANG`/`ROOT_SIZE_MB`/`LIVE_USER` 等）。

## 自建 RPM 来源（`scripts/fetch-rpms.sh`）

`repos.txt` 里每个仓库都会从 GitHub Release 取 RPM：

- 用 `GET /repos/<org>/<repo>/releases?per_page=50` 列出 release，**按 `published_at` 取最新**；
  因为组件仓库发布的是 `ci-<sha>` **预发布（pre-release）** release，而 `/releases/latest` 接口会跳过预发布
  （全为预发布时直接 404），用 latest 会一个包都下不到、ISO 里全是 Fedora 原版包。
- 从最新开始找**第一个带可用 RPM 资产**的 release（跳过 draft、跳过只有 tag 没产物的 release），
  只取 `*.fc45.*` / `*.noarch.rpm`，排除 `*.src.rpm`、`debuginfo`、`debugsource`。
- 结果缓存在 `$REPO_DIR/.api-cache/<repo>.json`，下载失败的包只告警不中断构建。

## 自建包优先级（`FORCE_SELF_BUILT`）

自建包是 Fedora 源码的快照，常常**比 Fedora 45 当前版本旧**（例如自建 `gnome-shell 51~rc` vs Fedora `51.0`），
而 kickstart 里 `repo --cost=1` 只在**版本相同**时打破平手，不会覆盖版本比较——所以默认情况下 Fedora 的新版本会胜出，
自建的 shell/控制中心改动不会进镜像。

`scripts/build-iso.sh` 会把指定自建包的 Fedora 同名包从两个 Fedora 仓库里 `--excludepkgs` 掉，从而强制使用自建包。
**默认只强制 `gnome-shell` + `gnome-control-center`**（其余全部用 Fedora 当前包——整份快照一起压回旧版本时，
systemd/glib2 等基础组件会退回 pre-release，实测无法启动）。相关开关：

- `FORCE_SELF_BUILT_PKGS=gnome-shell,gnome-control-center[,mutter,...]`：按**源码包名**指定要强制的组件
  （自动带上它的所有子包，例如 `gnome-shell-common`）。
- `FORCE_SELF_BUILT=0`：完全关闭强制（全部用 Fedora 包，用于对比）。
- `FORCE_SELF_BUILT_SKIP=<名字列表>`：对个别二进制包放行 Fedora 版本（依赖冲突时的逃生口）。

注意：强制旧版本可能让“按新版本编译的 Fedora 包”依赖无法满足，构建会**明确报错**（而不是静默混用）。

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
3. `fetch-rpms.sh` 并发下载自建二进制 RPM（跳过源码包和 debuginfo）→ `createrepo_c`；
4. `livecd-creator` 出 ISO → 改名 → `boot/verify-iso.py` 内容门禁；
5. 上传 release（>2 GiB 自动分片）。

## 常见问题

- **构建超时/磁盘不足**：live ISO 构建 30–60 分钟、约 8–10 GB 磁盘。
- **自建包缺失导致依赖失败**：dnf 回退到 Fedora 同名包；否则报依赖错误。
- **重复构建下载很慢**：本地构建默认将 RPM 缓存在 `/var/cache/lingmo-repo`，已下载且校验通过的文件会复用；可用 `REPO_DIR=/path/to/cache` 指定目录，或用 `RPM_DOWNLOAD_JOBS=8` 调整并发数。
- **ISO 大于 2 GiB**：自动分片，按分片文件名顺序 `cat` 合并。
- **`make sync` 报 `default.xml ... not committed`**：manifest 克隆只含已提交
  文件，先提交 `default.xml`。
- **ISO 内容门禁失败**：CI 日志搜 `Module '...' cannot be found`（dracut
  模块缺失会导致 initrd 静默缺失）。
