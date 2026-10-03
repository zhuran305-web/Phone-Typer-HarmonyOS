import { customScan, scanBarcode, scanCore } from '@kit.ScanKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { display } from '@kit.ArkUI'
import { PtConstants } from '../common/PtConstants'

const LOG_DOMAIN: number = 0x0000
const LOG_TAG: string = 'PtScanPage'

@Entry
@Component
struct ScanPage {
  @State torchOn: boolean = false
  @State scanError: string = ''
  private xComponentController: XComponentController = new XComponentController()
  private started: boolean = false
  private finishing: boolean = false

  private buildViewControl(surfaceId: string): customScan.ViewControl {
    let wVp: number = 360
    let hVp: number = 720
    try {
      const disp = display.getDefaultDisplaySync()
      if (disp.densityPixels > 0) {
        wVp = Math.round(disp.width / disp.densityPixels)
        hVp = Math.round(disp.height / disp.densityPixels)
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'get display failed')
    }
    const control: customScan.ViewControl = {
      width: wVp,
      height: hVp,
      surfaceId: surfaceId
    }
    return control
  }

  private startScan(): void {
    if (this.started) {
      return
    }
    const surfaceId: string | undefined = this.xComponentController.getXComponentSurfaceId()
    if (surfaceId === undefined || surfaceId.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'no surface id')
      this.scanError = '无法启动相机'
      return
    }
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      }
      customScan.init(options)
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'init fail: %{public}s', e.message)
      this.scanError = '无法启动相机'
      return
    }
    this.started = true
    const viewControl: customScan.ViewControl = this.buildViewControl(surfaceId)
    try {
      customScan.start(viewControl, (err: BusinessError, data: Array<scanBarcode.ScanResult>) => {
        if (err !== undefined && err !== null) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'scan fail: %{public}s', err.message)
          this.scanError = '扫码失败，请重试'
          return
        }
        if (data.length === 0) {
          return
        }
        this.finishWithResult(data[0].originalValue)
      })
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'start fail: %{public}s', e.message)
      this.scanError = '无法启动相机'
    }
  }

  private finishWithResult(value: string): void {
    if (this.finishing) {
      return
    }
    this.finishing = true
    AppStorage.setOrCreate<string>(PtConstants.SCAN_RESULT_KEY, value)
    this.getUIContext().getRouter().back()
  }

  private toggleTorch(): void {
    try {
      if (this.torchOn) {
        customScan.closeFlashLight()
        this.torchOn = false
      } else {
        customScan.openFlashLight()
        this.torchOn = true
      }
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'torch fail: %{public}s', e.message)
    }
  }

  async aboutToDisappear(): Promise<void> {
    try {
      await customScan.stop()
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'stop fail: %{public}s', e.message)
    }
    try {
      await customScan.release()
    } catch (err) {
      const e = err as BusinessError
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'release fail: %{public}s', e.message)
    }
  }

  build() {
    Stack() {
      XComponent({
        id: 'pt_scan_surface',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .onLoad(() => {
          this.startScan()
        })
        .width('100%')
        .height('100%')

      Column() {
        Row() {
          Button('返回')
            .fontSize(14)
            .fontColor('#EDEDEF')
            .backgroundColor('#33000000')
            .height(36)
            .padding({ left: 16, right: 16 })
            .borderRadius(18)
            .onClick(() => {
              this.getUIContext().getRouter().back()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        Column({ space: 16 }) {
          Column()
            .width(240)
            .height(240)
            .borderRadius(20)
            .border({ width: 2, color: '#B3FFFFFF' })
          Text(this.scanError.length > 0 ? this.scanError : '对准电脑端二维码')
            .fontSize(14)
            .fontColor(this.scanError.length > 0 ? '#F87171' : '#EDEDEF')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Button(this.torchOn ? '关闭手电筒' : '打开手电筒')
          .fontSize(14)
          .fontColor('#EDEDEF')
          .backgroundColor('#33000000')
          .height(38)
          .padding({ left: 18, right: 18 })
          .borderRadius(19)
          .margin({ bottom: 40 })
          .onClick(() => {
            this.toggleTorch()
          })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
