OTHER_MENU:=Other modules

define KernelPackage/switch-rtl8367c
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=Realtek RTL8367C/S switch support
  DEPENDS:=+kmod-switch-rtl8366-smi
  KCONFIG:=CONFIG_RTL8367C_PHY=y
  FILES:=$(LINUX_DIR)/drivers/net/phy/rtl8367c.ko
  AUTOLOAD:=$(call AutoLoad,43,rtl8367c,1)
endef

define KernelPackage/switch-rtl8367c/description
 Realtek RTL8367C/S switch support
endef

$(eval $(call KernelPackage,switch-rtl8367c))

define KernelPackage/tpm-tis-core
  SUBMENU:=$(OTHER_MENU)
  TITLE:=TPM TIS 1.2 Interface / TPM 2.0 FIFO Interface
	DEPENDS:= +kmod-tpm
  KCONFIG:= CONFIG_TCG_TIS
  FILES:= \
	$(LINUX_DIR)/drivers/char/tpm/tpm_tis.ko \
	$(LINUX_DIR)/drivers/char/tpm/tpm_tis_core.ko
  AUTOLOAD:=$(call AutoLoad,20,tpm_tis,1)
endef

define KernelPackage/tpm-tis-core/description
	If you have a TPM security chip that is compliant with the
	TCG TIS 1.2 TPM specification (TPM1.2) or the TCG PTP FIFO
	specification (TPM2.0) say Yes and it will be accessible from
	within Linux.
endef

$(eval $(call KernelPackage,tpm-tis-core))


define KernelPackage/tpm-tis-i2c
  SUBMENU:=$(OTHER_MENU)
  TITLE:=TPM I2C Interface Specification
        DEPENDS:= +kmod-tpm +kmod-i2c-core +kmod-tpm-tis-core +kmod-lib-crc-ccitt
  KCONFIG:= CONFIG_TCG_TIS_I2C
  FILES:= $(LINUX_DIR)/drivers/char/tpm/tpm_tis_i2c.ko
  AUTOLOAD:=$(call AutoLoad,40,tpm_tis_i2c,1)
endef
define KernelPackage/tpm-tis-i2c/description
        If you have a TPM security chip which is connected to a regular
  I2C master (i.e. most embedded platforms) that is compliant with the
  TCG TPM I2C Interface Specification say Yes and it will be accessible from
  within Linux.
endef
$(eval $(call KernelPackage,tpm-tis-i2c))

define KernelPackage/bootconfig
  SUBMENU:=Other modules
  TITLE:=Bootconfig partition for failsafe
  KCONFIG:=CONFIG_BOOTCONFIG_PARTITION
  FILES:=$(LINUX_DIR)/drivers/platform/ipq/bootconfig.ko@ge4.4
  AUTOLOAD:=$(call AutoLoad,56,bootconfig,1)
endef

define KernelPackage/bootconfig/description
  Bootconfig partition for failsafe
endef

$(eval $(call KernelPackage,bootconfig))
