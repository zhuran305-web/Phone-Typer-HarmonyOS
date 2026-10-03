import { PtConstants } from './PtConstants'

export class PtQrConfig {
  ip: string = ''
  httpPort: number = PtConstants.DEFAULT_HTTP_PORT
  wsPort: number = PtConstants.DEFAULT_WS_PORT
  pin: string = PtConstants.DEFAULT_PIN
}

class PtQrJson {
  ip?: string
  http?: number
  ws?: number
  pin?: string
}

export class PtQrParser {
  static parse(text: string): PtQrConfig | null {
    const trimmed = text.trim()
    if (trimmed.length === 0) {
      return null
    }
    if (trimmed.startsWith('ptyper://')) {
      return PtQrParser.parseUri(trimmed)
    }
    return PtQrParser.parseJson(trimmed)
  }

  private static parseJson(text: string): PtQrConfig | null {
    try {
      const raw = JSON.parse(text) as PtQrJson
      if (typeof raw.ip !== 'string' || raw.ip.length === 0) {
        return null
      }
      const config = new PtQrConfig()
      config.ip = raw.ip
      if (typeof raw.http === 'number' && raw.http > 0 && raw.http <= 65535) {
        config.httpPort = Math.floor(raw.http)
      }
      if (typeof raw.ws === 'number' && raw.ws > 0 && raw.ws <= 65535) {
        config.wsPort = Math.floor(raw.ws)
      }
      if (typeof raw.pin === 'string' && raw.pin.length > 0) {
        config.pin = raw.pin
      }
      return config
    } catch (err) {
      return null
    }
  }

  private static parseUri(text: string): PtQrConfig | null {
    const queryIndex = text.indexOf('?')
    if (queryIndex < 0) {
      return null
    }
    const pairs: string[] = text.substring(queryIndex + 1).split('&')
    const config = new PtQrConfig()
    let hasIp = false
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i]
      const eqIndex = pair.indexOf('=')
      if (eqIndex <= 0) {
        continue
      }
      const key = pair.substring(0, eqIndex)
      const val = pair.substring(eqIndex + 1)
      if (key === 'ip' && val.length > 0) {
        config.ip = val
        hasIp = true
      } else if (key === 'http') {
        const port = PtQrParser.toPort(val)
        if (port > 0) {
          config.httpPort = port
        }
      } else if (key === 'ws') {
        const port = PtQrParser.toPort(val)
        if (port > 0) {
          config.wsPort = port
        }
      } else if (key === 'pin' && val.length > 0) {
        config.pin = val
      }
    }
    if (!hasIp) {
      return null
    }
    return config
  }

  private static toPort(text: string): number {
    const num = Number(text)
    if (Number.isNaN(num) || num <= 0 || num > 65535) {
      return -1
    }
    return Math.floor(num)
  }
}
