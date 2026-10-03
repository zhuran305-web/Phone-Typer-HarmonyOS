export class PtConstants {
  static readonly PREF_NAME: string = 'pt_settings'
  static readonly KEY_PC_IP: string = 'pc_ip'
  static readonly KEY_HTTP_PORT: string = 'http_port'
  static readonly KEY_WS_PORT: string = 'ws_port'
  static readonly KEY_PIN: string = 'pin'
  static readonly KEY_PC_PROMPT_SHOWN: string = 'pc_prompt_shown'
  static readonly PC_DOWNLOAD_URL: string = 'https://github.com/zhuran305-web/Phone-Typer/releases'
  static readonly DEFAULT_HTTP_PORT: number = 8766
  static readonly DEFAULT_WS_PORT: number = 8767
  static readonly DEFAULT_PIN: string = '1234'
  static readonly SYNC_DEBOUNCE_MS: number = 150
  static readonly SETTINGS_FLUSH_DEBOUNCE_MS: number = 500
  static readonly SCAN_RESULT_KEY: string = 'pt_scan_result'
  static readonly RECONNECT_DELAY_MS: number = 3000
  static readonly CLIP_FLASH_MS: number = 1200
  static readonly COPY_RESET_MS: number = 1500
}
