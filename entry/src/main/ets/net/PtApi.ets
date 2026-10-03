import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { PtConstants } from '../common/PtConstants'

const LOG_DOMAIN: number = 0x0000
const LOG_TAG: string = 'PtApi'

export class PtServerConfig {
  wsPort: number = PtConstants.DEFAULT_WS_PORT
  version: string = ''
}

class PtConfigReply {
  ws_port?: number
  version?: string
}

export class PtApi {
  static async fetchServerConfig(pcIp: string, httpPort: number): Promise<PtServerConfig> {
    const result = new PtServerConfig()
    const httpRequest = http.createHttp()
    try {
      const url = `http://${pcIp}:${httpPort}/api/config`
      const resp = await httpRequest.request(url, {
        connectTimeout: 3000,
        readTimeout: 3000,
        expectDataType: http.HttpDataType.STRING
      } as http.HttpRequestOptions)
      if (resp.responseCode === 200 && typeof resp.result === 'string') {
        const raw = JSON.parse(resp.result) as PtConfigReply
        if (raw.ws_port !== undefined && raw.ws_port > 0 && raw.ws_port <= 65535) {
          result.wsPort = raw.ws_port
        }
        if (raw.version !== undefined) {
          result.version = raw.version
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'fetch config failed, use default port')
    } finally {
      httpRequest.destroy()
    }
    return result
  }
}
