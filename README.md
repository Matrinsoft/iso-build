# Lingmo OS ISO Builder

从自建 RPM 包 + Fedora 仓库组装 Lingmo OS 5 (Unstable) 的 live ISO，并在 GitHub Actions 里自动构建、发布。

## 产物

- **ISO 命名格式**：`lingmoOS_5_Unstable_<YYMMDD>_amd64.iso`（例如 `lingmoOS_5_Unstable_260905_amd64.iso`）
- **发布**：每次 push 到 `main` 或手动触发，自动构建 ISO 并发布到 GitHub Release，tag 为 `iso-<YYYYMMDD>`。
- **分片**：GitHub Release 单个文件上限 2 GiB。若 ISO 超过 2 GiB，会自动用 `split` 分片上传，每个分片 `~1.9 GiB`。合并方式：`cat lingmoOS_5_Unstable_*.iso.part* > lingmoOS_5_Unstable_<date>_amd64.iso`。

## 包来源策略

| 来源 | 包 | 说明 |
|---|---|---|
| **自建**（`repos.txt` 列出的 73 个仓库） | gnome-shell、mutter、nautilus、gjs、gtk4、glib2 等 72 个 GNOME 组件 + `lingmo-release` | 从各仓库的 GitHub Release 拉取 RPM，组成本地 repo，**优先级最高（cost=1）**，覆盖 Fedora 同名包 |
| **Fedora 45 仓库** | kernel、grub2、plymouth、systemd、NetworkManager、mesa 等系统包；以及 `gst-thumbnailers`、`gnome-user-share`、`loupe`、`snapshot`、`librsvg2` | 这几个 Rust 组件因 crate 版本问题未自建，直接采用 Fedora 45 官方包 |

> 包来源优先级通过 kickstart 里的 repo `--cost` 控制：`lingmo`(cost=1) > `fedora`(cost=200) > `fedora-updates`(cost=300)。

## 文件说明

| 文件 | 作用 |
|---|---|
| `lingmo-live.ks` | kickstart 定义：语言/时区、repo 配置、包列表、`%post` 开机配置 |
| `repos.txt` | 自建包的 GitHub 仓库名清单（73 个） |
| `build-iso.sh` | 构建脚本：下载自建 RPM → `createrepo_c` 建本地 repo → `livecd-creator` 生成 ISO |
| `.github/workflows/build-iso.yml` | GitHub Actions 工作流：Fedora 45 容器构建 + 分片上传 release |

## 构建流程（workflow 内部）

1. 在 `fedora:45` 容器里安装 `livecd-tools`、`createrepo_c`。
2. `build-iso.sh` 遍历 `repos.txt`，用 GitHub API 下载每个仓库最新 release 的 `.rpm`（跳过 `debuginfo`）。
3. `createrepo_c` 把下载的 RPM 打包成本地 yum 仓库。
4. `livecd-creator --config lingmo-live.ks` 拉取 Fedora 系统包 + 本地自建包，组装 squashfs 根文件系统 + 启动文件，产出 ISO。
5. 重命名为 `lingmoOS_5_Unstable_<YYMMDD>_amd64.iso`，上传到 release（>2 GiB 时分片）。

## 本地构建

```bash
# 前置：Fedora 45 环境，root 权限
sudo dnf install -y livecd-tools createrepo_c

# 下载自建包（需要 GitHub token）
export GITHUB_TOKEN=your_token
bash build-iso.sh
```

> 注意：`livecd-creator` 需要 root 权限（挂载 loop、chroot），且需要较大磁盘空间（约 8–10 GB）。

## 关键依赖包（回顾）

- **os-release 身份**：`lingmo-release`（自建，覆盖 `fedora-release`）
- **引导**：`grub2-efi-x64`、`grub2-tools`、`shim-x64`（UEFI）
- **开机动画**：`plymouth`、`plymouth-system-theme`、`plymouth-theme-spinner`
- **initramfs**：`dracut`
- **内核**：`kernel`、`kernel-modules`

## 常见问题

- **构建超时/磁盘不足**：live ISO 构建耗时长（30–60 分钟）、磁盘占用大。GitHub runner 默认 14 GB 磁盘，必要时在 workflow 里先 `df -h` 检查。
- **自建包缺失导致依赖失败**：某个自建包如果 release 里没有对应 rpm，`livecd-creator` 会回退到 Fedora 仓库的同名包（若存在），否则报依赖错误。
- **ISO 大于 2 GiB**：自动分片，下载后按分片文件名顺序 `cat` 合并。
