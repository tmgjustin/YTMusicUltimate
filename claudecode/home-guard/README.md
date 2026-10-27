# Home Guard

在 Mac mini 上定期收集家中網路設備(路由器 / NAS / 交換器)與 Mac mini 本機的 log,
自動分析不正常行為,並透過 **Email** 與 **Telegram** 通知。

純 Python 標準函式庫,不需要安裝額外套件(Python 3.11+;3.9/3.10 需 `pip install tomli`)。

## 運作方式

```
路由器 / NAS / 交換器 ──syslog (UDP/TCP 514)──▶ receiver (常駐)
                                                   │ 依設備分檔寫入
                                                   ▼
                                     data_dir/logs/<設備>/<日期>.log
                                                   │
Mac mini unified log (log show) ──┐                │
kernel panic / LaunchDaemons ─────┼──▶ analyze (每 15 分鐘, launchd)
                                  │        │ 規則 + 統計基準線
                                  │        ▼
                                  │   data_dir/reports/*.txt
                                  └──▶ Email / Telegram 通知
```

兩個 launchd 系統服務:

| 服務 | 作用 |
| --- | --- |
| `com.homeguard.receiver` | 常駐的 syslog 接收器,依來源 IP 存到各設備的資料夾 |
| `com.homeguard.analyze` | 每 15 分鐘讀取新增的 log(只讀增量),跑偵測、寫報告、發通知 |

## 偵測項目

**規則比對**(在每次分析區間內計數,可在設定檔覆寫或停用)

| id | 偵測內容 | 等級 |
| --- | --- | --- |
| `brute_force` | 同一來源 IP 登入失敗 ≥ 5 次(SSH、NAS、路由器管理介面、VPN…) | 嚴重 |
| `disk_error` | I/O error、SMART 異常、RAID degraded、檔案系統錯誤 | 嚴重 |
| `overheat` | 溫度過高、風扇故障 | 嚴重 |
| `power` | 停電、UPS 切換電池 | 嚴重 |
| `intrusion` | port scan、SYN flood、攻擊偵測、XProtect 偵測到惡意程式 | 嚴重 |
| `reboot` | 設備重新開機 | 警告 |
| `link_flap` | 連線反覆斷線(≥ 6 次) | 警告 |
| `config_change` | 設定 / 韌體變更、恢復原廠、管理員帳號變動 | 警告 |
| `crash` | OOM、segfault、watchdog | 警告 |
| `sudo_fail` | Mac mini 上 sudo/su 密碼錯誤 | 警告 |
| `firewall_flood` | 同一 IP 被防火牆擋 ≥ 100 次 | 警告 |

**行為 / 統計偵測**

| id | 偵測內容 |
| --- | --- |
| `new_login_ip` | 從沒見過的 IP 登入成功(外部 IP 為警告,內網為資訊) |
| `new_device` | DHCP / Wi-Fi log 中出現沒見過的 MAC(新裝置連上網路) |
| `volume_spike` | 某設備 log 量遠高於「該時段」的歷史平均(附上最多的訊息類型) |
| `device_silent` | 設備超過 N 分鐘沒送 log(可能當機、斷線或 syslog 設定被改) |
| `unknown_sender` | 收到未登記 IP 送來的 log |
| `kernel_panic` | Mac mini 新的 kernel panic 報告 |
| `new_launch_item` | 新增 LaunchAgents / LaunchDaemons(惡意程式常見的常駐手法) |
| `disk_space` | Mac mini 存 log 的磁碟快滿了 |

- **學習期**(預設 3 天):新 IP / 新裝置只記錄成「已知」,不發警報,避免一開始就被洗版。
- **冷卻時間**(預設 120 分鐘):同一則警報(同規則 + 設備 + IP/MAC)不會重複通知。
- 通知失敗時不會進入冷卻,下次分析會重送。

## 安裝

### 1. 準備

```bash
brew install python            # 建議用 Homebrew 的 Python 3.11+
cd ~/claudecode/home-guard     # 不要放在 桌面 / 文件 / 下載,背景服務會被 macOS 隱私保護擋住
cp config.example.toml config.toml
chmod 600 config.toml
```

編輯 `config.toml`:
- `[[devices]]`:每台設備的名稱與 IP(建議在路由器上給它們固定 IP)
- `[notify.email]`、`[notify.telegram]`:見下方「通知設定」

### 2. 先手動測試

```bash
# 用規則掃一份既有的 log(從 NAS / 路由器匯出),看會抓到什麼
python3 -m homeguard replay ~/Downloads/nas-log.txt --device nas

# 測試通知
sudo python3 -m homeguard -c config.toml test-notify
```

### 3. 安裝成系統服務

```bash
sudo ./install.sh                  # 每 15 分鐘分析一次
sudo INTERVAL=600 ./install.sh     # 或自訂秒數
```

服務以 root 執行(收 514 port 和讀取完整的系統 log 都需要)。
如果有開 macOS 防火牆,第一次會詢問是否允許 python3 接受連入連線,請選允許。

常用指令:

```bash
sudo launchctl kickstart system/com.homeguard.analyze   # 立即分析一次
tail -f /var/log/home-guard/*.log                        # 服務本身的 log
ls /usr/local/var/home-guard/reports/                    # 每次分析的報告
sudo ./uninstall.sh                                      # 移除服務(保留資料)
```

修改 `config.toml` 後重啟接收器:`sudo launchctl kickstart -k system/com.homeguard.receiver`
(分析器每次都會重新讀設定,不用重啟)。

## 設定各設備把 log 送到 Mac mini

以下 `192.168.1.100` 請換成 Mac mini 的 IP(建議設固定 IP)。

| 設備 | 設定位置 |
| --- | --- |
| **Synology NAS** | 記錄中心 (Log Center) → 記錄傳送 → 傳送到 syslog 伺服器:`192.168.1.100`、port 514、UDP、格式 BSD 或 IETF |
| **QNAP NAS** | QuLog Center → 記錄傳送端 → 新增目標 syslog 伺服器 |
| **ASUS 路由器** | 系統記錄 → 一般記錄 → 遠端記錄伺服器 |
| **OpenWrt** | `uci set system.@system[0].log_ip=192.168.1.100; uci set system.@system[0].log_proto=udp; uci commit; /etc/init.d/log restart` |
| **MikroTik** | `/system logging action set remote remote=192.168.1.100` 再 `/system logging add topics=info action=remote` |
| **UniFi** | 設定 → System → Remote Logging (Syslog) |
| **TP-Link / Netgear 交換器** | 系統工具 → System Log → Remote / Syslog Server |
| **Linux 主機** | rsyslog:`*.* @192.168.1.100:514` |

設好後可確認:`ls /usr/local/var/home-guard/logs/`,應該會看到各設備的資料夾。
若出現 `unknown-<ip>`,代表那個 IP 沒登記在 `[[devices]]`。

## 通知設定

### Email(以 Gmail 為例)

1. Google 帳戶 → 安全性 → 開啟兩步驟驗證 → 建立「應用程式密碼」
2. 填入 `config.toml`:

```toml
[notify.email]
enabled = true
username = "you@gmail.com"
password = "xxxx xxxx xxxx xxxx"   # 應用程式密碼
from = "you@gmail.com"
to = ["you@gmail.com"]
```

### Telegram

1. 在 Telegram 找 **@BotFather** → `/newbot` → 取得 bot token
2. 對你的新 bot 傳任何一則訊息
3. 開啟 `https://api.telegram.org/bot<TOKEN>/getUpdates`,找到 `"chat":{"id": 123456789 ...}`
4. 填入:

```toml
[notify.telegram]
enabled = true
bot_token = "123456:ABC..."
chat_id = "123456789"
```

不想把密碼寫在檔案裡,可以留空,改在 `/Library/LaunchDaemons/com.homeguard.analyze.plist`
的 `EnvironmentVariables` 加上 `HOMEGUARD_SMTP_PASSWORD` / `HOMEGUARD_TELEGRAM_TOKEN`。

Email 收到完整報告;Telegram 收到精簡版(不含「資訊」等級)。

## 通知範例

```
🛡 Home Guard 2026-10-27 14:00
期間 2026-10-27 13:45 – 14:00 | 事件 1834 筆 | 裝置 4 台

🔴 嚴重 (2)
• [nas] 登入失敗次數過多 (疑似暴力破解) ×37 — ip=203.0.113.7, user=admin
    sshd: Failed password for admin from 203.0.113.7 port 51022 ssh2
• [nas] 磁碟 / 檔案系統錯誤
    Disk: Disk 2 SMART test failed

🟠 警告 (1)
• [router] 偵測到新裝置連上網路 — mac=aa:bb:cc:dd:ee:02, ip=192.168.1.51
    dnsmasq-dhcp: DHCPACK(br0) 192.168.1.51 aa:bb:cc:dd:ee:02
```

## 調整與誤報處理

- 已知裝置不想再收到「新裝置」通知:加到 `[detect.known_macs]`
- 某條規則太吵:在 `[[rules]]` 用相同 `id` 調高 `threshold`,或 `enabled = false`
- 自家設備有特殊 log:新增 `[[rules]]`(`pattern` 是 Python regex,比對 `程式名: 訊息`)
- 某台設備平常 log 很少:該設備設 `silent_minutes = 0` 或調大
- 原始 log 都在 `data_dir/logs/` 底下,可以直接 `grep`

## 選用:AI 摘要

設定 `[ai] enabled = true` 後,有警報時會呼叫 Claude Code(`claude -p`)用白話說明
可能原因與建議動作,附在通知最上方。

- 需要 Mac mini 上已安裝並登入 Claude Code;因為服務以 root 執行,需以 root 登入一次
  (`sudo claude`),或在 analyze plist 的 `EnvironmentVariables` 設定 `ANTHROPIC_API_KEY`
- 會把警報內容與 log 樣本(可能包含 IP、帳號名稱)送到 Anthropic,請自行評估

## 開發

```bash
python3 -m unittest discover -s tests -v
```

| 檔案 | 說明 |
| --- | --- |
| `homeguard/receiver.py` | syslog 接收器(UDP、TCP、RFC 6587 octet counting) |
| `homeguard/collectors.py` | 增量讀取設備 log、`log show` |
| `homeguard/detectors.py` | 內建規則與行為 / 統計偵測 |
| `homeguard/local_checks.py` | kernel panic、LaunchDaemons、磁碟空間 |
| `homeguard/analyzer.py` | 一次分析的完整流程 |
| `homeguard/notify.py` | Email / Telegram |
| `homeguard/state.py` | SQLite 狀態(讀取位置、基準線、已知 IP/MAC、冷卻時間) |
