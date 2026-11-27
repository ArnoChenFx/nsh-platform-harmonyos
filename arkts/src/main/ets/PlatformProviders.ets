import { common } from "@kit.AbilityKit";
import { emitter } from "@kit.BasicServicesKit";
import { image } from "@kit.ImageKit";

export interface NshShareRequest {
  paths?: string[];
  text?: string;
  uri?: string;
  title?: string;
}

export interface NshShareResult {
  phase?: string;
  text?: string;
  error?: string;
}

export interface NshShareProvider {
  isAvailable(): boolean;
  show(
    context: common.UIAbilityContext,
    request: NshShareRequest,
    live: () => boolean,
    onCancel?: (cancel: () => void) => void,
  ): Promise<NshShareResult>;
}

export interface NshTrashProvider {
  moveToTrash(context: common.UIAbilityContext, uri: string, path: string): Promise<string>;
}

export interface NshSpeechRecognitionResult {
  result?: string;
  isFinal?: boolean;
}

export interface NshSpeechListener {
  onStart: (sessionId: string, message: string) => void;
  onEvent: (sessionId: string, eventType: number, message: string) => void;
  onResult: (sessionId: string, result: NshSpeechRecognitionResult) => void;
  onComplete: (sessionId: string, message: string) => void;
  onError: (sessionId: string, errorCode: number, errorMessage: string) => void;
}

export interface NshSpeechAudioInfo {
  audioType: string;
  sampleRate: number;
  soundChannel: number;
  sampleBit: number;
}

export interface NshSpeechStartParams {
  sessionId: string;
  audioInfo: NshSpeechAudioInfo;
}

export interface NshSpeechLanguageQuery {
  sessionId: string;
}

export interface NshSpeechCreateParams {
  language: string;
  online: number;
}

export interface NshSpeechEngine {
  listLanguages(params: NshSpeechLanguageQuery): Promise<string[]>;
  setListener(listener: NshSpeechListener): void;
  startListening(params: NshSpeechStartParams): void;
  writeAudio(sessionId: string, audio: Uint8Array): void;
  finish(sessionId: string): void;
  cancel(sessionId: string): void;
  shutdown(): void;
}

export class NshSpeechProviderError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export interface NshSpeechProvider {
  isAvailable(): boolean;
  createEngine(params: NshSpeechCreateParams): Promise<NshSpeechEngine>;
  mapErrorCode?(code?: number): string;
}

export interface NshTrayIcon {
  white: image.PixelMap;
  black: image.PixelMap;
}

export interface NshTrayQuickOperation {
  title: string;
  height: number;
  abilityName: string;
  moduleName: string;
}

export interface NshTrayMenuAction {
  abilityName: string;
  moduleName: string;
  notifyOnly?: boolean;
  menuCode: string;
}

export interface NshTrayMenuItemOptions {
  selected?: boolean;
}

export interface NshTraySubMenuItem {
  subTitle: string;
  menuAction: NshTrayMenuAction;
  menuCode?: string;
  options?: NshTrayMenuItemOptions;
}

export interface NshTrayMenuItem {
  title: string;
  menuAction?: NshTrayMenuAction;
  subMenu?: NshTraySubMenuItem[];
  menuCode?: string;
  options?: NshTrayMenuItemOptions;
}

export type NshTrayGroupMenu = NshTrayMenuItem[];

export interface NshTrayItem {
  icons: NshTrayIcon;
  quickOperation: NshTrayQuickOperation;
  statusBarGroupMenu?: NshTrayGroupMenu[];
  hoverTips?: string;
}

export interface NshTrayProvider {
  readonly unsupportedMessage?: string;
  isAvailable(context: common.UIAbilityContext): Promise<boolean>;
  addToStatusBar(context: common.UIAbilityContext, item: NshTrayItem): Promise<void>;
  removeFromStatusBar(context: common.UIAbilityContext): Promise<void>;
  removeFromStatusBarSync?(context: common.UIAbilityContext): void;
  updateStatusBarMenu(context: common.UIAbilityContext, menus: NshTrayGroupMenu[]): Promise<void>;
  updateStatusBarIcon(context: common.UIAbilityContext, icon: NshTrayIcon): Promise<void>;
  updateStatusBarHoverTips(context: common.UIAbilityContext, tips: string): Promise<void>;
  onIconClick(callback: (event: emitter.EventData) => void): void;
  offIconClick(callback: (event: emitter.EventData) => void): void;
  onRightMenuClick(callback: (event: emitter.EventData) => void): void;
  offRightMenuClick(callback: (event: emitter.EventData) => void): void;
}

export interface NshPlatformProviders {
  share?: NshShareProvider;
  trash?: NshTrashProvider;
  speech?: NshSpeechProvider;
  tray?: NshTrayProvider;
}

export interface ResolvedPlatformProviders {
  share: NshShareProvider;
  trash: NshTrashProvider;
  speech: NshSpeechProvider;
  tray: NshTrayProvider;
}

export function defaultMapSpeechError(code?: number): string {
  switch (code) {
    case 201:
    case 202:
    case 1002200012:
      return "not-allowed";
    case 1002200006:
    case 1002200008:
      return "unavailable";
    default:
      return "failed";
  }
}

export class UnsupportedShareProvider implements NshShareProvider {
  isAvailable(): boolean {
    return false;
  }
  async show(
    _context: common.UIAbilityContext,
    _request: NshShareRequest,
    _live: () => boolean,
    _onCancel?: (cancel: () => void) => void,
  ): Promise<NshShareResult> {
    throw new Error("systemShare is not supported on OpenHarmony");
  }
}

export class UnsupportedTrashProvider implements NshTrashProvider {
  async moveToTrash(
    _context: common.UIAbilityContext,
    _uri: string,
    _path: string,
  ): Promise<string> {
    throw new Error("moving files to trash is not supported on OpenHarmony");
  }
}

export class UnsupportedSpeechProvider implements NshSpeechProvider {
  isAvailable(): boolean {
    return false;
  }
  async createEngine(_params: NshSpeechCreateParams): Promise<NshSpeechEngine> {
    throw new NshSpeechProviderError(
      1002200008,
      "speechRecognizer is not supported on OpenHarmony",
    );
  }
  mapErrorCode(code?: number): string {
    return defaultMapSpeechError(code);
  }
}

export class UnsupportedTrayProvider implements NshTrayProvider {
  readonly unsupportedMessage: string = "statusBarManager is not supported on OpenHarmony";
  async isAvailable(_context: common.UIAbilityContext): Promise<boolean> {
    return false;
  }
  async addToStatusBar(_context: common.UIAbilityContext, _item: NshTrayItem): Promise<void> {
    throw new Error("statusBarManager is not supported on OpenHarmony");
  }
  async removeFromStatusBar(_context: common.UIAbilityContext): Promise<void> {
    throw new Error("statusBarManager is not supported on OpenHarmony");
  }
  removeFromStatusBarSync(_context: common.UIAbilityContext): void {}
  async updateStatusBarMenu(
    _context: common.UIAbilityContext,
    _menus: NshTrayGroupMenu[],
  ): Promise<void> {
    throw new Error("statusBarManager is not supported on OpenHarmony");
  }
  async updateStatusBarIcon(_context: common.UIAbilityContext, _icon: NshTrayIcon): Promise<void> {
    throw new Error("statusBarManager is not supported on OpenHarmony");
  }
  async updateStatusBarHoverTips(_context: common.UIAbilityContext, _tips: string): Promise<void> {
    throw new Error("statusBarManager is not supported on OpenHarmony");
  }
  onIconClick(_callback: (event: emitter.EventData) => void): void {}
  offIconClick(_callback: (event: emitter.EventData) => void): void {}
  onRightMenuClick(_callback: (event: emitter.EventData) => void): void {}
  offRightMenuClick(_callback: (event: emitter.EventData) => void): void {}
}

const defaultProviders: ResolvedPlatformProviders = {
  share: new UnsupportedShareProvider(),
  trash: new UnsupportedTrashProvider(),
  speech: new UnsupportedSpeechProvider(),
  tray: new UnsupportedTrayProvider(),
};

const customProviders: NshPlatformProviders = {};

export function registerDefaultPlatformProviders(providers: NshPlatformProviders): void {
  if (providers.share !== undefined) {
    defaultProviders.share = providers.share;
  }
  if (providers.trash !== undefined) {
    defaultProviders.trash = providers.trash;
  }
  if (providers.speech !== undefined) {
    defaultProviders.speech = providers.speech;
  }
  if (providers.tray !== undefined) {
    defaultProviders.tray = providers.tray;
  }
}

export function registerPlatformProviders(providers: NshPlatformProviders): void {
  if (providers.share !== undefined) {
    customProviders.share = providers.share;
  }
  if (providers.trash !== undefined) {
    customProviders.trash = providers.trash;
  }
  if (providers.speech !== undefined) {
    customProviders.speech = providers.speech;
  }
  if (providers.tray !== undefined) {
    customProviders.tray = providers.tray;
  }
}

export function getPlatformProviders(): ResolvedPlatformProviders {
  return {
    share: customProviders.share ?? defaultProviders.share,
    trash: customProviders.trash ?? defaultProviders.trash,
    speech: customProviders.speech ?? defaultProviders.speech,
    tray: customProviders.tray ?? defaultProviders.tray,
  };
}
