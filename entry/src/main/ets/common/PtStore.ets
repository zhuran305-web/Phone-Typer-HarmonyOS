import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { PtConstants } from './PtConstants'

const LOG_DOMAIN: number = 0x0000
const LOG_TAG: string = 'PtStore'

export class PtSettings {
  pcIp: string = ''
  httpPort: number = PtConstants.DEFAULT_HTTP_PORT
  wsPort: number = PtConstants.DEFAULT_WS_PORT
  pin: string = PtConstants.DEFAULT_PIN
}

export class PtStore {
  private store: preferences.Preferences | null = null
  private flushTimer: number = -1

  static async create(context: common.Context): Promise<PtStore> {
    const ptStore = new PtStore()
    ptStore.store = await preferences.getPreferences(context, PtConstants.PREF_NAME)
    return ptStore
  }

  async loadSettings(): Promise<PtSettings> {
    const settings = new PtSettings()
    if (this.store === null) {
      return settings
    }
    settings.pcIp = this.store.getSync(PtConstants.KEY_PC_IP, '') as string
    settings.httpPort = this.store.getSync(PtConstants.KEY_HTTP_PORT, PtConstants.DEFAULT_HTTP_PORT) as number
    settings.wsPort = this.store.getSync(PtConstants.KEY_WS_PORT, PtConstants.DEFAULT_WS_PORT) as number
    settings.pin = this.store.getSync(PtConstants.KEY_PIN, PtConstants.DEFAULT_PIN) as string
    return settings
  }

  private put(key: string, value: preferences.ValueType): void {
    if (this.store === null) {
      return
    }
    this.store.putSync(key, value)
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer)
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1
      if (this.store !== null) {
        this.store.flush().catch((err: BusinessError) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush fail: %{public}s', err.message)
        })
      }
    }, PtConstants.SETTINGS_FLUSH_DEBOUNCE_MS)
  }

  savePcIp(value: string): void {
    this.put(PtConstants.KEY_PC_IP, value)
  }

  saveHttpPort(value: number): void {
    this.put(PtConstants.KEY_HTTP_PORT, value)
  }

  saveWsPort(value: number): void {
    this.put(PtConstants.KEY_WS_PORT, value)
  }

  savePin(value: string): void {
    this.put(PtConstants.KEY_PIN, value)
  }

  isPcPromptShown(): boolean {
    if (this.store === null) {
      return false
    }
    return this.store.getSync(PtConstants.KEY_PC_PROMPT_SHOWN, false) as boolean
  }

  markPcPromptShown(): void {
    this.put(PtConstants.KEY_PC_PROMPT_SHOWN, true)
  }
}
