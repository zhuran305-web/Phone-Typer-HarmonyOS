import { webSocket } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { PtConstants } from '../common/PtConstants'

const LOG_DOMAIN: number = 0x0000
const LOG_TAG: string = 'PtWsClient'

export interface PtWsCallbacks {
  onOpen: () => void
  onClose: () => void
  onError: (err: BusinessError) => void
  onMessage: (data: string) => void
}

export interface PtWsFrame {
  pin: string
  type: string
  text: string
}

export class PtWsClient {
  private ws: webSocket.WebSocket | null = null
  private url: string = ''
  private callbacks: PtWsCallbacks | null = null
  private manualClosed: boolean = false
  private opened: boolean = false
  private reconnectTimer: number = -1

  connect(url: string, callbacks: PtWsCallbacks): void {
    this.url = url
    this.callbacks = callbacks
    this.manualClosed = false
    this.opened = false
    this.cleanupSocket()
    const ws = webSocket.createWebSocket()
    this.ws = ws
    ws.on('open', () => {
      this.opened = true
      hilog.info(LOG_DOMAIN, LOG_TAG, 'ws open: %{public}s', url)
      callbacks.onOpen()
    })
    ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (typeof value === 'string') {
        callbacks.onMessage(value)
      }
    })
    ws.on('error', (err: BusinessError) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'ws error: %{public}s', err.message)
      callbacks.onError(err)
    })
    ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      this.opened = false
      hilog.info(LOG_DOMAIN, LOG_TAG, 'ws close: %{public}d %{public}s', value.code, value.reason)
      callbacks.onClose()
      this.scheduleReconnect()
    })
    ws.connect(url).catch((err: BusinessError) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'ws connect fail: %{public}s', err.message)
      this.opened = false
      callbacks.onError(err)
      this.scheduleReconnect()
    })
  }

  isOpen(): boolean {
    return this.opened
  }

  sendFrame(pin: string, type: string, text: string): boolean {
    if (!this.opened || this.ws === null) {
      return false
    }
    const frame: PtWsFrame = { pin: pin, type: type, text: text }
    this.ws.send(JSON.stringify(frame)).catch((err: BusinessError) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'ws send fail: %{public}s', err.message)
    })
    return true
  }

  close(): void {
    this.manualClosed = true
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
    this.opened = false
    this.cleanupSocket()
  }

  private scheduleReconnect(): void {
    if (this.manualClosed) {
      return
    }
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer)
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      if (!this.manualClosed && this.callbacks !== null) {
        this.connect(this.url, this.callbacks)
      }
    }, PtConstants.RECONNECT_DELAY_MS)
  }

  private cleanupSocket(): void {
    if (this.ws !== null) {
      const old = this.ws
      old.off('open')
      old.off('message')
      old.off('error')
      old.off('close')
      old.close().catch((err: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'old ws close fail: %{public}s', err.message)
      })
      this.ws = null
    }
  }
}
