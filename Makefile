# Lingmo OS ISO builder - kernel-style entry points.
#
#   make defconfig    load default configuration (configs/desktop.config)
#   make menuconfig   interactive configuration UI (needs a terminal)
#   make oldconfig    update .config with new symbols, prompting as needed
#   make sync         sync all source projects (git-repo + default.xml)
#   make ks           render lingmo-live.ks from core/ks fragments
#   make pkg-<name>   build one self-built RPM from its source checkout
#   make pkg          build every package enabled in .config (PKG_*=y)
#   make iso          build the ISO with the current configuration
#   make clean        remove generated files

KCONFIG_CONFIG ?= .config
export KCONFIG_CONFIG

PYTHON ?= python3

.PHONY: help defconfig menuconfig oldconfig sync ks pkg iso clean

help:
	@echo "Lingmo OS ISO builder targets:"
	@echo "  defconfig   - load default configuration into $(KCONFIG_CONFIG)"
	@echo "  menuconfig  - interactive configuration UI"
	@echo "  oldconfig   - refresh $(KCONFIG_CONFIG) after Kconfig changes"
	@echo "  sync        - sync all source projects (git-repo + default.xml)"
	@echo "  ks          - render lingmo-live.ks from core/ks fragments"
	@echo "  pkg-<name>  - build one RPM from its source checkout"
	@echo "  pkg         - build all PKG_*=y packages into \$$REPO_DIR"
	@echo "  iso         - build the live ISO"
	@echo "  clean       - remove generated files"
	@echo ""
	@echo "Per-package recipe overrides: drop a pkg/<name>.mk file defining"
	@echo "an explicit 'pkg-<name>:' rule; it wins over the generic rule."

# repos.txt -> pkg/Kconfig.pkg (regenerate when inputs change)
pkg/Kconfig.pkg: scripts/gen-pkg-config.py default.xml repos.txt
	$(PYTHON) scripts/gen-pkg-config.py

defconfig menuconfig oldconfig: pkg/Kconfig.pkg

defconfig:
	@cp configs/desktop.config $(KCONFIG_CONFIG)
	@echo "$(KCONFIG_CONFIG) <- configs/desktop.config"

menuconfig:
	$(PYTHON) scripts/menuconfig.py

oldconfig:
	$(PYTHON) scripts/menuconfig.py --oldconfig

sync:
	bash scripts/sync-repos.sh

ks:
	$(PYTHON) lib/render-ks.py

pkg: pkg/Kconfig.pkg
	$(PYTHON) lib/build_pkg.py --all $(KCONFIG_CONFIG)

pkg-%: pkg/Kconfig.pkg
	$(PYTHON) lib/build_pkg.py $*

# Optional per-package overrides (win over the pkg-% pattern rule)
-include $(wildcard pkg/*.mk)

iso:
	@$(PYTHON) lib/render-ks.py
	bash scripts/build-iso.sh

clean:
	rm -f $(KCONFIG_CONFIG) lingmo-live.ks.tmp
	rm -rf pkg/Kconfig.pkg out/pkg
