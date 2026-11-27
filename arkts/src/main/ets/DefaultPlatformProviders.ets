import { common } from "@kit.AbilityKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { deviceInfo, emitter } from "@kit.BasicServicesKit";
import { fileUri } from "@kit.CoreFileKit";
import type speechRecognizer from "@hms.ai.speechRecognizer";
import type systemShare from "@hms.collaboration.systemShare";
import type statusBarManager from "@hms.pcService.statusBarManager";
import {
  defaultMapSpeechError,
  NshShareProvider,
  NshShareRequest,
  NshShareResult,
  NshSpeechCreateParams,
  NshSpeechEngine,
  NshSpeechLanguageQuery,
  NshSpeechListener,
  NshSpeechProvider,
  NshSpeechProviderError,
  NshSpeechStartParams,
  NshTrashProvider,
  NshTrayGroupMenu,
  NshTrayIcon,
  NshTrayItem,
  NshTrayProvider,
  registerDefaultPlatformProviders,
} from "./PlatformProviders";

export class HmsShareProvider implements NshShareProvider {
  isAvailable(): boolean {
    return deviceInfo.sdkApiVersion >= 18 && canIUse("SystemCapability.Collaboration.SystemShare");
  }

  async show(
    context: common.UIAbilityContext,
    request: NshShareRequest,
    live: () => boolean,
    onCancel?: (cancel: () => void) => void,
  ): Promise<NshShareResult> {
    const kit = await import("@hms.collaboration.systemShare");
    if (!live()) {
      return { phase: "dismissed" };
    }
    const paths = request.paths ?? [];
    const text = [request.text, request.uri].filter((part?: string): boolean => !!part).join("\n");
    const records: systemShare.SharedRecord[] = [];
    for (const path of paths) {
      records.push({
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(path),
        title: request.title,
        description: text || undefined,
      });
    }
    if (records.length === 0) {
      records.push({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: text,
        title: request.title,
      });
    }
    const data = new kit.default.SharedData(records[0]);
    for (let i = 1; i < records.length; i++) {
      data.addRecord(records[i]);
    }
    const controller = new kit.default.ShareController(data);
    return new Promise<NshShareResult>((resolve, reject) => {
      let done = false;
      const complete = (result: NshShareResult, error?: Error): void => {
        if (done) {
          return;
        }
        done = true;
        controller.off("shareCompleted", shared);
        controller.off("dismiss", dismissed);
        if (error) {
          reject(error);
        } else {
          resolve(result);
        }
      };
      const shared = (event: systemShare.ShareOperationResult): void =>
        complete({ phase: "shared", text: event.targetAbilityInfo.name });
      const dismissed = (): void => complete({ phase: "dismissed" });
      onCancel?.(dismissed);
      controller.on("shareCompleted", shared);
      controller.on("dismiss", dismissed);
      controller
        .show(context, {
          selectionMode:
            paths.length > 1 ? kit.default.SelectionMode.BATCH : kit.default.SelectionMode.SINGLE,
        })
        .catch((error: Error) => complete({}, error));
    });
  }
}

export class HmsTrashProvider implements NshTrashProvider {
  async moveToTrash(
    _context: common.UIAbilityContext,
    uri: string,
    path: string,
  ): Promise<string> {
    if (!canIUse("SystemCapability.FileManagement.FileManagerService.Core")) {
      throw new Error("moving files to trash is not supported on this device");
    }
    const kit = await import("@hms.filemanagement.fileManagerService");
    try {
      return await kit.default.deleteToTrash(uri);
    } catch (err) {
      if (path.startsWith("/data/storage/")) {
        throw new Error(
          `moving app sandbox files to trash is not supported on HarmonyOS (${String(err)})`,
        );
      }
      throw err instanceof Error ? err : new Error(String(err));
    }
  }
}

class HmsSpeechEngineAdapter implements NshSpeechEngine {
  private readonly inner: speechRecognizer.SpeechRecognitionEngine;

  constructor(inner: speechRecognizer.SpeechRecognitionEngine) {
    this.inner = inner;
  }

  async listLanguages(params: NshSpeechLanguageQuery): Promise<string[]> {
    return await this.inner.listLanguages({ sessionId: params.sessionId });
  }

  setListener(listener: NshSpeechListener): void {
    this.inner.setListener({
      onStart: (sessionId: string, message: string): void => {
        listener.onStart(sessionId, message);
      },
      onEvent: (sessionId: string, eventType: number, message: string): void => {
        listener.onEvent(sessionId, eventType, message);
      },
      onResult: (
        sessionId: string,
        result: speechRecognizer.SpeechRecognitionResult,
      ): void => {
        listener.onResult(sessionId, {
          result: result.result,
          isFinal: result.isFinal,
        });
      },
      onComplete: (sessionId: string, message: string): void => {
        listener.onComplete(sessionId, message);
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
        listener.onError(sessionId, errorCode, errorMessage);
      },
    });
  }

  startListening(params: NshSpeechStartParams): void {
    this.inner.startListening({
      sessionId: params.sessionId,
      audioInfo: {
        audioType: params.audioInfo.audioType,
        sampleRate: params.audioInfo.sampleRate,
        soundChannel: params.audioInfo.soundChannel,
        sampleBit: params.audioInfo.sampleBit,
      },
    });
  }

  writeAudio(sessionId: string, audio: Uint8Array): void {
    this.inner.writeAudio(sessionId, audio);
  }

  finish(sessionId: string): void {
    this.inner.finish(sessionId);
  }

  cancel(sessionId: string): void {
    this.inner.cancel(sessionId);
  }

  shutdown(): void {
    this.inner.shutdown();
  }
}

export class HmsSpeechProvider implements NshSpeechProvider {
  isAvailable(): boolean {
    return canIUse("SystemCapability.AI.SpeechRecognizer");
  }

  async createEngine(params: NshSpeechCreateParams): Promise<NshSpeechEngine> {
    if (!this.isAvailable()) {
      throw new NshSpeechProviderError(
        1002200008,
        "speechRecognizer is not supported on this device",
      );
    }
    const engine: speechRecognizer.SpeechRecognitionEngine = await import(
      "@hms.ai.speechRecognizer"
    ).then(
      (recognizer): Promise<speechRecognizer.SpeechRecognitionEngine> =>
        recognizer.default.createEngine({
          language: params.language,
          online: params.online,
        }),
      (error: Error): Promise<speechRecognizer.SpeechRecognitionEngine> => {
        throw new NshSpeechProviderError(1002200008, String(error));
      },
    );
    return new HmsSpeechEngineAdapter(engine);
  }

  mapErrorCode(code?: number): string {
    return defaultMapSpeechError(code);
  }
}

function toHmsStatusBarMenus(
  menus: NshTrayGroupMenu[],
): statusBarManager.StatusBarGroupMenu[] {
  const groups: statusBarManager.StatusBarGroupMenu[] = [];
  for (let g = 0; g < menus.length; g++) {
    const srcGroup = menus[g];
    const dstGroup: statusBarManager.StatusBarMenuItem[] = [];
    for (let i = 0; i < srcGroup.length; i++) {
      const item = srcGroup[i];
      let subMenu: statusBarManager.StatusBarSubMenuItem[] | undefined = undefined;
      if (item.subMenu !== undefined) {
        subMenu = [];
        for (let s = 0; s < item.subMenu.length; s++) {
          const sub = item.subMenu[s];
          const hmsSub: statusBarManager.StatusBarSubMenuItem = {
            subTitle: sub.subTitle,
            menuAction: {
              abilityName: sub.menuAction.abilityName,
              moduleName: sub.menuAction.moduleName,
              notifyOnly: sub.menuAction.notifyOnly,
              menuCode: sub.menuAction.menuCode,
            },
            menuCode: sub.menuCode,
            options:
              sub.options !== undefined ? { selected: sub.options.selected } : undefined,
          };
          subMenu.push(hmsSub);
        }
      }
      const hmsItem: statusBarManager.StatusBarMenuItem = {
        title: item.title,
        menuAction:
          item.menuAction !== undefined
            ? {
                abilityName: item.menuAction.abilityName,
                moduleName: item.menuAction.moduleName,
                notifyOnly: item.menuAction.notifyOnly,
                menuCode: item.menuAction.menuCode,
              }
            : undefined,
        subMenu,
        menuCode: item.menuCode,
        options:
          item.options !== undefined ? { selected: item.options.selected } : undefined,
      };
      dstGroup.push(hmsItem);
    }
    groups.push(dstGroup);
  }
  return groups;
}

export class HmsTrayProvider implements NshTrayProvider {
  private removeSyncFn?: (context: common.UIAbilityContext) => void;
  private onIconClickFn?: (callback: (event: emitter.EventData) => void) => void;
  private offIconClickFn?: (callback: (event: emitter.EventData) => void) => void;
  private onRightMenuClickFn?: (callback: (event: emitter.EventData) => void) => void;
  private offRightMenuClickFn?: (callback: (event: emitter.EventData) => void) => void;
  private readonly pendingIconCallbacks: Set<(event: emitter.EventData) => void> = new Set();
  private readonly pendingMenuCallbacks: Set<(event: emitter.EventData) => void> = new Set();

  private async bindKit(): Promise<void> {
    if (this.removeSyncFn !== undefined) {
      return;
    }
    const kit = await import("@hms.pcService.statusBarManager");
    this.removeSyncFn = (context: common.UIAbilityContext): void => {
      kit.default.removeFromStatusBar(context);
    };
    this.onIconClickFn = (callback: (event: emitter.EventData) => void): void => {
      kit.default.on("statusBarIconClick", callback);
    };
    this.offIconClickFn = (callback: (event: emitter.EventData) => void): void => {
      kit.default.off("statusBarIconClick", callback);
    };
    this.onRightMenuClickFn = (callback: (event: emitter.EventData) => void): void => {
      kit.default.on("rightMenuClick", callback);
    };
    this.offRightMenuClickFn = (callback: (event: emitter.EventData) => void): void => {
      kit.default.off("rightMenuClick", callback);
    };
    this.pendingIconCallbacks.forEach((cb: (event: emitter.EventData) => void) => {
      this.onIconClickFn?.(cb);
    });
    this.pendingIconCallbacks.clear();
    this.pendingMenuCallbacks.forEach((cb: (event: emitter.EventData) => void) => {
      this.onRightMenuClickFn?.(cb);
    });
    this.pendingMenuCallbacks.clear();
  }

  async isAvailable(context: common.UIAbilityContext): Promise<boolean> {
    if (!canIUse("SystemCapability.PCService.StatusBarManager")) {
      return false;
    }
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    if (deviceInfo.sdkApiVersion >= 26) {
      try {
        const supported = await kit.default.isStatusBarCapabilitySupported(context);
        if (!supported) {
          return false;
        }
      } catch {}
    }
    return true;
  }

  async addToStatusBar(context: common.UIAbilityContext, item: NshTrayItem): Promise<void> {
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    const hmsItem: statusBarManager.StatusBarItem = {
      icons: {
        white: item.icons.white,
        black: item.icons.black,
      },
      quickOperation: {
        title: item.quickOperation.title,
        height: item.quickOperation.height,
        abilityName: item.quickOperation.abilityName,
        moduleName: item.quickOperation.moduleName,
      },
      statusBarGroupMenu:
        item.statusBarGroupMenu !== undefined
          ? toHmsStatusBarMenus(item.statusBarGroupMenu)
          : undefined,
      hoverTips: item.hoverTips,
    };
    await new Promise<void>((resolve, reject) => {
      try {
        if (deviceInfo.sdkApiVersion >= 14) {
          kit.default.addToStatusBar(context, hmsItem, (err): void => {
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        } else {
          kit.default.addToStatusBar(context, hmsItem);
          resolve();
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  async removeFromStatusBar(context: common.UIAbilityContext): Promise<void> {
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    await new Promise<void>((resolve, reject) => {
      try {
        if (deviceInfo.sdkApiVersion >= 14) {
          kit.default.removeFromStatusBar(context, (err): void => {
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        } else {
          kit.default.removeFromStatusBar(context);
          resolve();
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  removeFromStatusBarSync(context: common.UIAbilityContext): void {
    try {
      this.removeSyncFn?.(context);
    } catch {}
  }

  async updateStatusBarMenu(
    context: common.UIAbilityContext,
    menus: NshTrayGroupMenu[],
  ): Promise<void> {
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    const hmsMenus = toHmsStatusBarMenus(menus);
    await new Promise<void>((resolve, reject) => {
      try {
        if (deviceInfo.sdkApiVersion >= 14) {
          kit.default.updateStatusBarMenu(context, hmsMenus, (err): void => {
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        } else {
          kit.default.updateStatusBarMenu(context, hmsMenus);
          resolve();
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  async updateStatusBarIcon(context: common.UIAbilityContext, icon: NshTrayIcon): Promise<void> {
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    const hmsIcon: statusBarManager.StatusBarIcon = {
      white: icon.white,
      black: icon.black,
    };
    await new Promise<void>((resolve, reject) => {
      try {
        if (deviceInfo.sdkApiVersion >= 14) {
          kit.default.updateStatusBarIcon(context, hmsIcon, (err): void => {
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        } else {
          kit.default.updateStatusBarIcon(context, hmsIcon);
          resolve();
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  async updateStatusBarHoverTips(context: common.UIAbilityContext, tips: string): Promise<void> {
    await this.bindKit();
    const kit = await import("@hms.pcService.statusBarManager");
    await kit.default.updateStatusBarHoverTips(context, tips);
  }

  onIconClick(callback: (event: emitter.EventData) => void): void {
    if (this.onIconClickFn !== undefined) {
      this.onIconClickFn(callback);
    } else {
      this.pendingIconCallbacks.add(callback);
    }
  }

  offIconClick(callback: (event: emitter.EventData) => void): void {
    this.pendingIconCallbacks.delete(callback);
    this.offIconClickFn?.(callback);
  }

  onRightMenuClick(callback: (event: emitter.EventData) => void): void {
    if (this.onRightMenuClickFn !== undefined) {
      this.onRightMenuClickFn(callback);
    } else {
      this.pendingMenuCallbacks.add(callback);
    }
  }

  offRightMenuClick(callback: (event: emitter.EventData) => void): void {
    this.pendingMenuCallbacks.delete(callback);
    this.offRightMenuClickFn?.(callback);
  }
}

let initialized = false;

export function initDefaultPlatformProviders(): void {
  if (initialized) {
    return;
  }
  initialized = true;
  registerDefaultPlatformProviders({
    share: new HmsShareProvider(),
    trash: new HmsTrashProvider(),
    speech: new HmsSpeechProvider(),
    tray: new HmsTrayProvider(),
  });
}
