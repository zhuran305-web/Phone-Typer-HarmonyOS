import { common, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit'
import { BusinessError, pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PtConstants } from '../common/PtConstants'
import { PtStore, PtSettings } from '../common/PtStore'
import { PtQrParser } from '../common/PtQrParser'
import { PtWsClient, PtWsCallbacks } from '../net/PtWsClient'
import { PtApi, PtServerConfig } from '../net/PtApi'

const LOG_DOMAIN: number = 0x0000
const LOG_TAG: string = 'PtIndex'

class PtReply {
  type: string = ''
  text: string = ''
  ok: boolean = false
  err: string = ''
}

class PtUi {
  static readonly BG: string = '#050506'
  static readonly SURFACE: string = '#0A0A0C'
  static readonly BORDER: string = '#14FFFFFF'
  static readonly BORDER_STRONG: string = '#24FFFFFF'
  static readonly TEXT: string = '#EDEDEF'
  static readonly MUTED: string = '#8A8F98'
  static readonly FAINT: string = '#565B64'
  static readonly INDIGO: string = '#6366F1'
  static readonly PURPLE: string = '#A855F7'
  static readonly OK: string = '#4ADE80'
  static readonly BAD: string = '#F87171'
  static readonly WAIT: string = '#8A8F98'
  static readonly DISABLED_BG: string = '#1C1C22'
  static readonly WIDE_CONTENT_MAX: number = 600
}

@Extend(TextInput)
function ptInput(bgColor: ResourceColor, borderColor: ResourceColor) {
  .fontSize(15)
  .fontColor(PtUi.TEXT)
  .placeholderColor(PtUi.FAINT)
  .placeholderFont({ size: 14 })
  .backgroundColor(bgColor)
  .borderRadius(12)
  .border({ width: 1, color: borderColor })
  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
}

@Entry
@Component
struct Index {
  @State inputText: string = ''
  @State statusText: string = '未配置'
  @State statusColor: string = PtUi.WAIT
  @State connected: boolean = false
  @State liveMode: boolean = true
  @State pinCode: string = PtConstants.DEFAULT_PIN
  @State pcIpText: string = ''
  @State httpPortText: string = PtConstants.DEFAULT_HTTP_PORT.toString()
  @State wsPortText: string = PtConstants.DEFAULT_WS_PORT.toString()
  @State showSettings: boolean = false
  @State serverVersion: string = ''
  @State clipText: string = ''
  @State clipFlash: boolean = false
  @State copyBtnText: string = '复制'
  @State topSafe: number = 0
  @State bottomSafe: number = 0

  private store: PtStore | null = null
  private client: PtWsClient = new PtWsClient()
  private syncTimer: number = -1
  private connecting: boolean = false
  private clipFlashTimer: number = -1
  private copyResetTimer: number = -1

  async aboutToAppear(): Promise<void> {
    const context: common.Context | undefined = this.getUIContext().getHostContext()
    if (context === undefined) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'no context')
      return
    }
    try {
      this.store = await PtStore.create(context)
      const settings: PtSettings = await this.store.loadSettings()
      this.pcIpText = settings.pcIp
      this.httpPortText = settings.httpPort.toString()
      this.wsPortText = settings.wsPort.toString()
      this.pinCode = settings.pin
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'load settings failed')
    }
    if (this.pcIpText.trim().length > 0) {
      this.startConnection()
    } else {
      this.setStatus('未配置', PtUi.WAIT)
      this.showSettings = true
    }
    this.applySafeArea()
    setTimeout(() => {
      this.maybeShowPcPrompt()
    }, 600)
  }

  private maybeShowPcPrompt(): void {
    if (this.store === null) {
      return
    }
    if (this.store.isPcPromptShown()) {
      return
    }
    this.store.markPcPromptShown()
    this.getUIContext().showAlertDialog({
      title: '需要电脑端配合使用',
      message: '本应用需在电脑上安装 Phone-Typer 电脑端软件才能打字。是否前往 GitHub 下载？',
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '前往下载',
        fontColor: PtUi.INDIGO,
        action: () => {
          this.openPcDownloadPage()
        }
      },
      secondaryButton: {
        value: '暂不需要',
        fontColor: PtUi.MUTED,
        action: () => {
        }
      },
      cancel: () => {
      }
    })
  }

  private openPcDownloadPage(): void {
    const abilityContext: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('abilityContext')
    if (abilityContext === undefined) {
      this.copyDownloadLink()
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: PtConstants.PC_DOWNLOAD_URL
    }
    abilityContext.startAbility(want).then(() => {
    }).catch((err: BusinessError) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'open download page fail: %{public}s', err.message)
      this.copyDownloadLink()
    })
  }

  private copyDownloadLink(): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, PtConstants.PC_DOWNLOAD_URL)
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.setStatus('打开失败，链接已复制', PtUi.BAD)
    }).catch(() => {
      this.setStatus('打开下载页失败', PtUi.BAD)
    })
  }

  private async applySafeArea(): Promise<void> {
    const context: common.Context | undefined = this.getUIContext().getHostContext()
    if (context === undefined) {
      return
    }
    try {
      const win = await window.getLastWindow(context)
      const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      this.topSafe = this.getUIContext().px2vp(sys.topRect.height)
      this.bottomSafe = this.getUIContext().px2vp(nav.bottomRect.height)
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'get avoid area failed')
    }
  }

  aboutToDisappear(): void {
    this.cancelSyncTimer()
    this.clearClipTimers()
    this.client.close()
  }

  private setStatus(text: string, color: string): void {
    this.statusText = text
    this.statusColor = color
  }

  private parsePort(text: string, fallback: number): number {
    const num = Number(text.trim())
    if (Number.isNaN(num) || num <= 0 || num > 65535) {
      return fallback
    }
    return Math.floor(num)
  }

  private saveSettings(): void {
    if (this.store === null) {
      return
    }
    this.store.savePcIp(this.pcIpText.trim())
    this.store.saveHttpPort(this.parsePort(this.httpPortText, PtConstants.DEFAULT_HTTP_PORT))
    this.store.saveWsPort(this.parsePort(this.wsPortText, PtConstants.DEFAULT_WS_PORT))
  }

  private startConnection(): void {
    if (this.pcIpText.trim().length === 0) {
      this.setStatus('未配置', PtUi.WAIT)
      this.showSettings = true
      return
    }
    if (this.connecting) {
      return
    }
    this.connecting = true
    this.cancelSyncTimer()
    this.client.close()
    this.connected = false
    this.setStatus('连接中', PtUi.WAIT)
    this.saveSettings()
    this.tryConnect()
  }

  private async tryConnect(): Promise<void> {
    const ip = this.pcIpText.trim()
    const httpPort = this.parsePort(this.httpPortText, PtConstants.DEFAULT_HTTP_PORT)
    let wsPort = this.parsePort(this.wsPortText, PtConstants.DEFAULT_WS_PORT)
    const config: PtServerConfig = await PtApi.fetchServerConfig(ip, httpPort)
    if (config.wsPort !== wsPort) {
      wsPort = config.wsPort
      this.wsPortText = wsPort.toString()
      if (this.store !== null) {
        this.store.saveWsPort(wsPort)
      }
    }
    this.serverVersion = config.version
    this.connecting = false
    this.client.connect(`ws://${ip}:${wsPort}`, this.makeCallbacks())
  }

  private makeCallbacks(): PtWsCallbacks {
    const callbacks: PtWsCallbacks = {
      onOpen: () => {
        this.connected = true
        this.setStatus('已连接', PtUi.OK)
        this.inputText = ''
      },
      onClose: () => {
        this.connected = false
        this.setStatus('已断开，重连中', PtUi.BAD)
      },
      onError: (err: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'ws error: %{public}s', err.message)
      },
      onMessage: (data: string) => {
        this.handleReply(data)
      }
    }
    return callbacks
  }

  private handleReply(data: string): void {
    let reply: PtReply
    try {
      reply = JSON.parse(data) as PtReply
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'bad reply json')
      return
    }
    if (reply.type === 'clip') {
      this.onClipReceived(reply.text)
      return
    }
    if (reply.ok) {
      this.setStatus('已连接', PtUi.OK)
    } else if (reply.err === 'bad-pin') {
      this.setStatus('PIN 错误', PtUi.BAD)
    } else {
      this.setStatus('发送失败', PtUi.BAD)
    }
  }

  private clearClipTimers(): void {
    if (this.clipFlashTimer !== -1) {
      clearTimeout(this.clipFlashTimer)
      this.clipFlashTimer = -1
    }
    if (this.copyResetTimer !== -1) {
      clearTimeout(this.copyResetTimer)
      this.copyResetTimer = -1
    }
  }

  private onClipReceived(text: string): void {
    this.clipText = text
    this.clipFlash = true
    if (this.clipFlashTimer !== -1) {
      clearTimeout(this.clipFlashTimer)
    }
    this.clipFlashTimer = setTimeout(() => {
      this.clipFlashTimer = -1
      this.clipFlash = false
    }, PtConstants.CLIP_FLASH_MS)
    this.setStatus('已连接', PtUi.OK)
  }

  private doCopyClip(): void {
    if (this.clipText.length === 0) {
      return
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.clipText)
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.copyBtnText = '已复制'
      if (this.copyResetTimer !== -1) {
        clearTimeout(this.copyResetTimer)
      }
      this.copyResetTimer = setTimeout(() => {
        this.copyResetTimer = -1
        this.copyBtnText = '复制'
      }, PtConstants.COPY_RESET_MS)
    }).catch((err: BusinessError) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'copy clip fail: %{public}s', err.message)
      this.setStatus('复制失败', PtUi.BAD)
    })
  }

  private cancelSyncTimer(): void {
    if (this.syncTimer !== -1) {
      clearTimeout(this.syncTimer)
      this.syncTimer = -1
    }
  }

  private scheduleSync(): void {
    this.cancelSyncTimer()
    this.syncTimer = setTimeout(() => {
      this.syncTimer = -1
      this.sendSyncNow()
    }, PtConstants.SYNC_DEBOUNCE_MS)
  }

  private sendSyncNow(): void {
    if (!this.liveMode || !this.connected || !this.client.isOpen()) {
      return
    }
    this.client.sendFrame(this.pinCode, 'sync', this.inputText)
  }

  private doSend(): void {
    if (this.liveMode || !this.connected || this.inputText.length === 0) {
      return
    }
    const sent = this.client.sendFrame(this.pinCode, 'send', this.inputText)
    if (sent) {
      this.inputText = ''
    }
  }

  private doClear(): void {
    this.cancelSyncTimer()
    this.inputText = ''
    if (this.liveMode) {
      this.sendSyncNow()
    }
  }

  private async doScan(): Promise<void> {
    const granted = await this.ensureCameraPermission()
    if (!granted) {
      this.setStatus('需要相机权限', PtUi.BAD)
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ScanPage' })
  }

  private async ensureCameraPermission(): Promise<boolean> {
    const context: common.Context | undefined = this.getUIContext().getHostContext()
    if (context === undefined) {
      return false
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const perms: Array<Permissions> = ['ohos.permission.CAMERA']
      const result = await atManager.requestPermissionsFromUser(context, perms)
      if (result.authResults.length === 0) {
        return false
      }
      return result.authResults[0] === 0
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'request camera perm fail: %{public}s', e.message)
      return false
    }
  }

  private handleScanResult(value: string): void {
    const config = PtQrParser.parse(value)
    if (config === null) {
      this.showSettings = true
      this.setStatus('二维码格式无效', PtUi.BAD)
      return
    }
    this.pcIpText = config.ip
    this.httpPortText = config.httpPort.toString()
    this.wsPortText = config.wsPort.toString()
    this.pinCode = config.pin
    if (this.store !== null) {
      this.store.savePin(config.pin)
    }
    this.showSettings = true
    this.startConnection()
  }

  onPageShow(): void {
    const result: string | undefined = AppStorage.get<string>(PtConstants.SCAN_RESULT_KEY)
    if (result === undefined || result.length === 0) {
      return
    }
    AppStorage.setOrCreate<string>(PtConstants.SCAN_RESULT_KEY, '')
    this.handleScanResult(result)
  }

  @Builder
  PillBtn(text: string, onTap: () => void) {
    Text(text)
      .fontSize(13)
      .fontColor(PtUi.MUTED)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(14)
      .backgroundColor('#0DFFFFFF')
      .onClick(() => {
        onTap()
      })
  }

  @Builder
  SettingsCard() {
    Column({ space: 12 }) {
      Text('电脑连接设置')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(PtUi.TEXT)
      Button('扫一扫电脑端二维码，自动配置')
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor(Color.Transparent)
        .fontColor(PtUi.INDIGO)
        .fontSize(15)
        .border({ width: 1, color: PtUi.INDIGO })
        .onClick(() => {
          this.doScan()
        })
      Text('或手动填写')
        .fontSize(11)
        .fontColor(PtUi.FAINT)
        .width('100%')
      TextInput({ text: this.pcIpText, placeholder: '电脑 IP（如 192.168.1.100）' })
        .onChange((value: string) => {
          this.pcIpText = value
          if (this.store !== null) {
            this.store.savePcIp(value.trim())
          }
        })
        .ptInput(PtUi.BG, Color.Transparent)
      Row({ space: 10 }) {
        TextInput({ text: this.httpPortText, placeholder: 'HTTP 端口' })
          .onChange((value: string) => {
            this.httpPortText = value
          })
          .type(InputType.Number)
          .ptInput(PtUi.BG, Color.Transparent)
          .layoutWeight(1)
        TextInput({ text: this.wsPortText, placeholder: 'WS 端口' })
          .onChange((value: string) => {
            this.wsPortText = value
          })
          .type(InputType.Number)
          .ptInput(PtUi.BG, Color.Transparent)
          .layoutWeight(1)
      }
      .width('100%')
      if (this.serverVersion.length > 0) {
        Text(`电脑端版本 v${this.serverVersion}`)
          .fontSize(11)
          .fontColor(PtUi.FAINT)
      }
      Button('保存并重连')
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor(PtUi.INDIGO)
        .fontColor(Color.White)
        .fontSize(15)
        .onClick(() => {
          this.startConnection()
        })
      Button('下载电脑端软件（GitHub）')
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor(Color.Transparent)
        .fontColor(PtUi.MUTED)
        .fontSize(15)
        .border({ width: 1, color: PtUi.BORDER_STRONG })
        .onClick(() => {
          this.openPcDownloadPage()
        })
    }
    .padding(16)
    .borderRadius(14)
    .backgroundColor(PtUi.SURFACE)
    .border({ width: 1, color: PtUi.BORDER })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('文台')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(PtUi.TEXT)
              Text('手机键盘 · 电脑键入')
                .fontSize(11)
                .fontColor(PtUi.FAINT)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            this.PillBtn('扫码', () => {
              this.doScan()
            })
            this.PillBtn('设置', () => {
              this.showSettings = !this.showSettings
            })
            Row({ space: 7 }) {
              Circle({ width: 7, height: 7 }).fill(this.statusColor)
              Text(this.statusText)
                .fontSize(12)
                .fontColor(this.statusColor)
            }
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .backgroundColor('#0DFFFFFF')
            .border({ width: 1, color: PtUi.BORDER })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.showSettings) {
            this.SettingsCard()
          }

          if (this.clipText.length > 0) {
            Column({ space: 10 }) {
              Row() {
                Text('电脑剪贴板')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(PtUi.TEXT)
                  .layoutWeight(1)
                Button(this.copyBtnText)
                  .height(32)
                  .borderRadius(10)
                  .backgroundColor(this.clipFlash ? PtUi.INDIGO : Color.Transparent)
                  .fontColor(this.clipFlash ? Color.White : PtUi.INDIGO)
                  .fontSize(13)
                  .border({ width: 1, color: PtUi.INDIGO })
                  .onClick(() => {
                    this.doCopyClip()
                  })
              }
              .width('100%')
              Text(this.clipText)
                .fontSize(13)
                .fontColor(PtUi.MUTED)
                .lineHeight(19)
                .maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .padding(16)
            .borderRadius(14)
            .backgroundColor(PtUi.SURFACE)
            .border({
              width: 1,
              color: this.clipFlash ? PtUi.INDIGO : PtUi.BORDER
            })
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          Column() {
            TextArea({ text: this.inputText, placeholder: '在这里打字…（实时同步模式下，内容随打随出现在电脑光标处）' })
              .onChange((value: string) => {
                this.inputText = value
                if (this.liveMode) {
                  this.scheduleSync()
                }
              })
              .height(200)
              .fontSize(17)
              .fontColor(PtUi.TEXT)
              .caretColor(PtUi.INDIGO)
              .placeholderColor(PtUi.FAINT)
              .placeholderFont({ size: 14 })
              .backgroundColor(Color.Transparent)
              .padding(16)
          }
          .borderRadius(16)
          .backgroundColor(PtUi.SURFACE)
          .border({ width: 1, color: PtUi.BORDER })
          .width('100%')

          Row() {
            Text('输入即同步 · 拼音上屏才发送')
              .fontSize(11)
              .fontColor(PtUi.FAINT)
              .layoutWeight(1)
            Text(`${this.inputText.length} 字`)
              .fontSize(11)
              .fontColor(PtUi.MUTED)
          }
          .width('100%')

          TextInput({ text: this.pinCode, placeholder: 'PIN（输入后本机记住）' })
            .onChange((value: string) => {
              this.pinCode = value
              if (this.store !== null) {
                this.store.savePin(value)
              }
            })
            .type(InputType.Number)
            .ptInput(PtUi.SURFACE, PtUi.BORDER)
            .width('100%')

          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text('实时同步')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(PtUi.TEXT)
              Text('随打随出，删格电脑端同步回删；切换或断线重连会清空输入框并重置基线')
                .fontSize(11)
                .fontColor(PtUi.MUTED)
                .lineHeight(17)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.liveMode })
              .onChange((isOn: boolean) => {
                this.liveMode = isOn
                this.cancelSyncTimer()
                this.inputText = ''
              })
              .selectedColor(PtUi.INDIGO)
          }
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .borderRadius(14)
          .backgroundColor(PtUi.SURFACE)
          .border({ width: 1, color: PtUi.BORDER })
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 10 }) {
            if (this.liveMode) {
              Button('实时同步中')
                .layoutWeight(1)
                .height(50)
                .borderRadius(13)
                .backgroundColor(PtUi.DISABLED_BG)
                .fontColor(PtUi.FAINT)
                .fontSize(16)
                .enabled(false)
            } else {
              Button('发送并键入')
                .layoutWeight(1)
                .height(50)
                .borderRadius(13)
                .linearGradient({
                  angle: 135,
                  colors: [[PtUi.INDIGO, 0], [PtUi.PURPLE, 1]]
                })
                .fontColor(Color.White)
                .fontSize(16)
                .enabled(this.connected && this.inputText.length > 0)
                .onClick(() => {
                  this.doSend()
                })
            }
            Button('清空')
              .width(92)
              .height(50)
              .borderRadius(13)
              .backgroundColor(Color.Transparent)
              .fontColor(PtUi.MUTED)
              .fontSize(16)
              .border({ width: 1, color: PtUi.BORDER_STRONG })
              .onClick(() => {
                this.doClear()
              })
          }
          .width('100%')

          Column({ space: 4 }) {
            Text('实时同步时电脑端光标请保持在你要输入的位置。')
              .fontSize(11)
              .fontColor(PtUi.FAINT)
              .lineHeight(18)
            Text('需与电脑同一 WiFi；连不上请检查防火墙放行、路由器未开「AP 隔离」。')
              .fontSize(11)
              .fontColor(PtUi.FAINT)
              .lineHeight(18)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 18, right: 18, top: 20, bottom: 30 })
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
      .width('100%')
      .constraintSize({ maxWidth: PtUi.WIDE_CONTENT_MAX })
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PtUi.BG)
    .padding({ top: this.topSafe, bottom: this.bottomSafe })
  }
}
