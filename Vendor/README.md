# Vendor

| 目錄 | 來源 | 版本 | 授權 |
|---|---|---|---|
| `mediaremote-adapter/` | https://github.com/ungive/mediaremote-adapter | commit `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd`（2026-10-17） | BSD-3-Clause，見 `mediaremote-adapter/LICENSE` |

`scripts/build-adapter.sh` 直接用 clang 把它編成 `MediaRemoteAdapter.framework` 與 `MediaRemoteAdapterTestClient`，不需要 CMake。

更新方式：

```bash
rm -rf Vendor/mediaremote-adapter
git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git Vendor/mediaremote-adapter
rm -rf Vendor/mediaremote-adapter/.git
```

更新後記得改上表的 commit，並跑一次 `make run` 確認「設定 › 音樂 › 資料來源」仍是「全系統」。
