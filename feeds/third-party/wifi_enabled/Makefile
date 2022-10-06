include $(TOPDIR)/rules.mk

PKG_NAME:=wifi-enabled
PKG_RELEASE:=1

PKG_LICENSE:=BSD-2-Clause
PKG_MAINTAINER:=nobody

include $(INCLUDE_DIR)/package.mk


define Package/wifi-enabled/default
	SECTION:=Extra packages
	CATEGORY:=Extra packages
	TITLE:=wifi enabled by default
endef

define Package/wifi-enabled
	$(Package/wifi-enabled/default)
endef

define Package/wifi-enabled/description
  Wifi enabled by default.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile/Default

endef
Build/Compile = $(Build/Compile/Default)

define Package/wifi-enabled/install
	$(CP) ./files/* $(1)
endef

$(eval $(call BuildPackage,wifi-enabled))

