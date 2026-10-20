APP_NAME := Islet
APP := build/$(APP_NAME).app
CONFIG ?= release

.PHONY: all app run debug test adapter icon screenshots install dmg clean

all: app

# 編譯並組出 build/Islet.app
app:
	CONFIG=$(CONFIG) ./scripts/bundle.sh

# 重新建置並啟動（會先關掉正在執行的版本）
run: app
	-pkill -x $(APP_NAME); sleep 0.3
	open $(APP)

# Debug 建置，選單列多一個「模擬事件」子選單
debug:
	$(MAKE) run CONFIG=debug

# SwiftPM 的 swiftbuild 在只有 Command Line Tools 時不會載入 Swift Testing 的 macro plugin，這裡手動指定。
TESTING_PLUGIN := $(shell p="$$(dirname "$$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"; [ -f "$$p" ] && echo "$$p")

test:
	swift test --scratch-path .build/tests $(if $(TESTING_PLUGIN),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN))

adapter:
	./scripts/build-adapter.sh

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

# 重新產生 README 用的截圖（docs/images）
screenshots:
	./scripts/screenshots.sh

# 安裝到 ~/Applications（開機自動啟動建議用安裝後的版本）
install: app
	-pkill -x $(APP_NAME); sleep 0.3
	mkdir -p ~/Applications
	rm -rf ~/Applications/$(APP_NAME).app
	ditto $(APP) ~/Applications/$(APP_NAME).app
	open ~/Applications/$(APP_NAME).app

# 打包成 build/Islet-<版本>.dmg（發佈用，固定是 Release 建置）
dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf .build build
