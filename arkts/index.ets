import "./src/main/ets/NshHost";

export {
  NshCacheOptions,
  NshCapabilities,
  NshEnvironment,
  NshHostReply,
  NshNativeProperty,
  NshOptions,
  NshPackage,
  NshPackageInfo,
  NshScrollHandle,
  NshSurface,
  NshTrust,
  getCapabilities,
  initLogging,
  onBackPressIntercept,
} from "libnsh_platform_harmonyos.so";
export { onAbilityWant, WantKind } from "./src/main/ets/NativeExtensions";
export { bindLaunchSurface, onLaunchWant } from "./src/main/ets/NativeLaunch";
export { onNotificationWant } from "./src/main/ets/NativeNotifications";
export { prepareWebEngine } from "./src/main/ets/NativeWebViews";
export {
  NshPlatformProviders,
  NshShareProvider,
  NshShareRequest,
  NshShareResult,
  NshSpeechAudioInfo,
  NshSpeechCreateParams,
  NshSpeechEngine,
  NshSpeechLanguageQuery,
  NshSpeechListener,
  NshSpeechProvider,
  NshSpeechProviderError,
  NshSpeechRecognitionResult,
  NshSpeechStartParams,
  NshTrashProvider,
  NshTrayGroupMenu,
  NshTrayIcon,
  NshTrayItem,
  NshTrayMenuAction,
  NshTrayMenuItem,
  NshTrayMenuItemOptions,
  NshTrayProvider,
  NshTrayQuickOperation,
  NshTraySubMenuItem,
  ResolvedPlatformProviders,
  getPlatformProviders,
  registerPlatformProviders,
} from "./src/main/ets/PlatformProviders";
