import { common } from "@kit.AbilityKit";
import { util } from "@kit.ArkTS";
import { deviceInfo, emitter } from "@kit.BasicServicesKit";
import { image } from "@kit.ImageKit";
import { fnv1a64Hex, splitMenuGroups, type WireMenuItem } from "./DesktopMenuUtils";
import {
  getPlatformProviders,
  NshTrayGroupMenu,
  NshTrayIcon,
  NshTrayItem,
  NshTrayMenuItem,
  NshTraySubMenuItem,
} from "./PlatformProviders";

export interface WireTrayIcon {
  format: string;
  width?: number;
  height?: number;
  whiteBase64?: string;
  blackBase64?: string;
  dataBase64?: string;
}

export interface TrayCommand {
  title?: string;
  tooltip?: string;
  click?: number;
  icon?: WireTrayIcon;
  items?: WireMenuItem[];
}

export interface NativeTrayHost {
  isClosed: () => boolean;
  isMainParked: () => boolean;
  showMainWindow: () => void;
  onRightMenuWillSelect: () => void;
  runForTrayRemoval: (
    remove: (retryOnBackground: boolean) => Promise<void>,
  ) => Promise<void>;
  emit: (kind: string, payload: string) => void;
}

interface TrayMenuTarget {
  id: number;
  role?: string;
}

// HarmonyOS `statusBarManager` API limits.
const STATUS_BAR_MAX_MENU_ITEMS: number = 20;
const STATUS_BAR_MAX_HOVER_TIPS_CHARS: number = 128;
// Distinct from menu bar (`0`) and popup menu generations (`1..TRAY_MENU_GENERATION`).
const TRAY_MENU_GENERATION: number = 0xffffffff;

function trayIconDigest(icon?: WireTrayIcon): string {
  if (!icon) {
    return "default";
  }
  return fnv1a64Hex(
    `${icon.format}|${icon.width ?? 0}x${icon.height ?? 0}|${icon.whiteBase64 ?? ""}|${icon.blackBase64 ?? ""}|${icon.dataBase64 ?? ""}`,
  );
}

export class NativeTray {
  private readonly abilityContext: common.UIAbilityContext;
  private readonly host: NativeTrayHost;
  private trayAdded: boolean = false;
  private traySubscribed: boolean = false;
  private trayGeneration: number = 0;
  private trayClickId: number = 0;
  private trayLastIconKey: string = "";
  private trayLastHoverTips: string = "";
  private trayMenuTargets: Map<string, TrayMenuTarget> = new Map();
  private trayQueue: Promise<void> = Promise.resolve();
  private trayUnsupportedWarned: boolean = false;
  private trayRemoveSyncFn?: () => void;
  private trayUnsubscribeFn?: () => void;

  private readonly onTrayIconClick = (_event: emitter.EventData): void => {
    if (this.host.isClosed()) {
      return;
    }
    if (this.trayClickId !== 0) {
      this.host.emit("tray-click", JSON.stringify({ id: this.trayClickId }));
    } else if (this.host.isMainParked()) {
      this.host.emit("reopen", "{}");
    } else {
      this.host.showMainWindow();
    }
  };

  private readonly onTrayRightMenuClick = (event: emitter.EventData): void => {
    if (this.host.isClosed()) {
      return;
    }
    const data = event.data as Record<string, Object> | undefined;
    const rawCode = data?.["menuCode"];
    const code = typeof rawCode === "string" ? rawCode : "";
    const target = this.trayMenuTargets.get(code);
    if (target === undefined) {
      return;
    }
    this.host.onRightMenuWillSelect();
    this.host.emit(
      "menu-select",
      JSON.stringify({ generation: TRAY_MENU_GENERATION, id: target.id, role: target.role }),
    );
  };

  constructor(abilityContext: common.UIAbilityContext, host: NativeTrayHost) {
    this.abilityContext = abilityContext;
    this.host = host;
  }

  isAdded(): boolean {
    return this.trayAdded;
  }

  settled(): Promise<void> {
    return this.trayQueue.catch((): void => {});
  }

  enqueueSet(cmd: TrayCommand): void {
    const generation = ++this.trayGeneration;
    this.trayQueue = this.trayQueue
      .then(async (): Promise<void> => {
        if (this.host.isClosed() || generation !== this.trayGeneration) {
          return;
        }
        await this.applySetTray(generation, cmd);
      })
      .catch((error: Object): void => {
        console.warn(`[NSH] setTray failed: ${String(error)}`);
      });
  }

  enqueueRemove(): void {
    const generation = ++this.trayGeneration;
    this.trayQueue = this.trayQueue
      .then(async (): Promise<void> => {
        if (generation !== this.trayGeneration) {
          return;
        }
        await this.applyRemoveTray();
      })
      .catch((): void => {});
  }

  removeSync(): void {
    this.trayGeneration++;
    this.trayClickId = 0;
    this.trayMenuTargets.clear();
    if (this.trayAdded) {
      this.trayAdded = false;
      this.trayLastIconKey = "";
      this.trayLastHoverTips = "";
      this.trayRemoveSyncFn?.();
    }
    this.unsubscribeTray();
  }

  private async applySetTray(generation: number, cmd: TrayCommand): Promise<void> {
    const tray = getPlatformProviders().tray;
    let supported = false;
    try {
      supported = await tray.isAvailable(this.abilityContext);
    } catch (error) {
      console.warn(`[NSH] statusBarManager unavailable: ${String(error)}`);
      return;
    }
    if (!supported) {
      if (!this.trayUnsupportedWarned && tray.unsupportedMessage !== undefined) {
        this.trayUnsupportedWarned = true;
        console.warn(`[NSH] ${tray.unsupportedMessage}`);
      }
      return;
    }
    if (this.host.isClosed() || generation !== this.trayGeneration) {
      return;
    }
    this.trayRemoveSyncFn = (): void => {
      try {
        tray.removeFromStatusBarSync?.(this.abilityContext);
      } catch {}
    };
    this.trayUnsubscribeFn = (): void => {
      try {
        tray.offIconClick(this.onTrayIconClick);
      } catch {}
      try {
        tray.offRightMenuClick(this.onTrayRightMenuClick);
      } catch {}
    };
    if (!this.traySubscribed) {
      try {
        tray.onIconClick(this.onTrayIconClick);
        tray.onRightMenuClick(this.onTrayRightMenuClick);
        this.traySubscribed = true;
      } catch (error) {
        console.warn(`[NSH] statusBarManager event subscribe failed: ${String(error)}`);
      }
    }
    this.trayClickId = cmd.click ?? 0;

    const nextMenuTargets: Map<string, TrayMenuTarget> = new Map();
    const menuGroups = this.buildStatusBarMenu(generation, cmd.items ?? [], nextMenuTargets);
    const rawTips = (cmd.tooltip ?? "").trim() || (cmd.title ?? "").trim();
    const hoverTips =
      rawTips.length > STATUS_BAR_MAX_HOVER_TIPS_CHARS
        ? rawTips.substring(0, STATUS_BAR_MAX_HOVER_TIPS_CHARS)
        : rawTips;
    const iconKey = trayIconDigest(cmd.icon);

    if (!this.trayAdded) {
      const icons = await this.decodeTrayIcons(cmd.icon);
      if (this.host.isClosed() || generation !== this.trayGeneration) {
        icons.white.release().catch((): void => {});
        icons.black.release().catch((): void => {});
        return;
      }
      const label =
        hoverTips.length > 0
          ? hoverTips
          : this.abilityContext.abilityInfo?.name ?? "App";
      const item: NshTrayItem = {
        icons,
        quickOperation: {
          title: label,
          height: 1,
          abilityName: "",
          moduleName: this.abilityContext.abilityInfo?.moduleName ?? "",
        },
        statusBarGroupMenu: menuGroups.length > 0 ? menuGroups : undefined,
      };
      if (deviceInfo.sdkApiVersion >= 22 && hoverTips.length > 0) {
        item.hoverTips = hoverTips;
      }
      try {
        await tray.addToStatusBar(this.abilityContext, item);
        if (this.host.isClosed() || generation !== this.trayGeneration) {
          try {
            await tray.removeFromStatusBar(this.abilityContext);
          } catch {}
          return;
        }
        this.trayAdded = true;
        this.trayMenuTargets = nextMenuTargets;
        this.trayLastIconKey = iconKey;
        this.trayLastHoverTips = hoverTips;
      } catch (error) {
        console.warn(`[NSH] addToStatusBar failed: ${String(error)}`);
      } finally {
        icons.white.release().catch((): void => {});
        icons.black.release().catch((): void => {});
      }
      return;
    }

    try {
      await tray.updateStatusBarMenu(this.abilityContext, menuGroups);
      if (!this.host.isClosed() && generation === this.trayGeneration) {
        this.trayMenuTargets = nextMenuTargets;
      }
    } catch (error) {
      console.warn(`[NSH] updateStatusBarMenu failed: ${String(error)}`);
    }

    if (iconKey !== this.trayLastIconKey) {
      const icons = await this.decodeTrayIcons(cmd.icon);
      if (this.host.isClosed() || generation !== this.trayGeneration) {
        icons.white.release().catch((): void => {});
        icons.black.release().catch((): void => {});
        return;
      }
      try {
        await tray.updateStatusBarIcon(this.abilityContext, icons);
        this.trayLastIconKey = iconKey;
      } catch (error) {
        console.warn(`[NSH] updateStatusBarIcon failed: ${String(error)}`);
      } finally {
        icons.white.release().catch((): void => {});
        icons.black.release().catch((): void => {});
      }
    }

    if (
      deviceInfo.sdkApiVersion >= 22 &&
      hoverTips.length > 0 &&
      hoverTips !== this.trayLastHoverTips
    ) {
      try {
        await tray.updateStatusBarHoverTips(this.abilityContext, hoverTips);
        this.trayLastHoverTips = hoverTips;
      } catch {}
    }
  }

  private async removeFromStatusBarOnceAsync(): Promise<number> {
    try {
      await getPlatformProviders().tray.removeFromStatusBar(this.abilityContext);
      return 0;
    } catch (error) {
      const code = (error as Record<string, Object> | undefined)?.["code"];
      if (typeof code === "number") {
        return code;
      }
      if (String(error).includes("1010710004")) {
        return 1010710004;
      }
      console.warn(`[NSH] removeFromStatusBar failed: ${String(error)}`);
      return -1;
    }
  }

  private async removeFromStatusBarAsync(retryOnBackground: boolean): Promise<void> {
    try {
      let code = await this.removeFromStatusBarOnceAsync();
      if (code === 1010710004 && retryOnBackground && !this.host.isClosed()) {
        await new Promise<void>((resolve) => {
          setTimeout(resolve, 100);
        });
        code = await this.removeFromStatusBarOnceAsync();
      }
      if (code > 0) {
        console.warn(`[NSH] removeFromStatusBar failed: code=${code}`);
      }
    } catch (error) {
      console.warn(`[NSH] removeFromStatusBar failed: ${String(error)}`);
    }
  }

  private async applyRemoveTray(): Promise<void> {
    this.trayClickId = 0;
    this.trayMenuTargets.clear();
    if (!this.trayAdded) {
      this.unsubscribeTray();
      return;
    }
    this.trayAdded = false;
    this.trayLastIconKey = "";
    this.trayLastHoverTips = "";
    await this.host.runForTrayRemoval(async (retryOnBackground: boolean): Promise<void> => {
      await this.removeFromStatusBarAsync(retryOnBackground);
    });
    this.unsubscribeTray();
  }

  private unsubscribeTray(): void {
    if (!this.traySubscribed) {
      return;
    }
    this.traySubscribed = false;
    this.trayUnsubscribeFn?.();
  }

  private buildStatusBarMenu(
    generation: number,
    items: WireMenuItem[],
    targets: Map<string, TrayMenuTarget>,
  ): NshTrayGroupMenu[] {
    const abilityName = this.abilityContext.abilityInfo?.name ?? "EntryAbility";
    const moduleName = this.abilityContext.abilityInfo?.moduleName ?? "entry";
    const supportsItemOptions = deviceInfo.sdkApiVersion >= 24;
    let seq = 0;
    let topLevelCount = 0;

    const makeCode = (item: WireMenuItem): string => {
      const code = `nsh-${generation}-${++seq}`;
      targets.set(code, { id: item.id ?? 0, role: item.role });
      return code;
    };

    const collectSubItems = (
      children: WireMenuItem[],
      out: NshTraySubMenuItem[],
    ): void => {
      for (let i = 0; i < children.length && out.length < STATUS_BAR_MAX_MENU_ITEMS; i++) {
        const child = children[i];
        if (child.kind === "separator" || child.enabled === false) {
          continue;
        }
        if (child.kind === "submenu") {
          collectSubItems(child.items ?? [], out);
          continue;
        }
        const code = makeCode(child);
        const subTitle =
          child.checked === true && !supportsItemOptions
            ? `✓ ${child.label ?? ""}`
            : child.label ?? "";
        const subItem: NshTraySubMenuItem = {
          subTitle,
          menuAction: {
            abilityName,
            moduleName,
            notifyOnly: true,
            menuCode: code,
          },
        };
        if (supportsItemOptions) {
          subItem.menuCode = code;
          if (child.checked !== undefined) {
            subItem.options = { selected: child.checked === true };
          }
        }
        out.push(subItem);
      }
    };

    const wireGroups = splitMenuGroups(items);
    const result: NshTrayGroupMenu[] = [];
    for (let g = 0; g < wireGroups.length && topLevelCount < STATUS_BAR_MAX_MENU_ITEMS; g++) {
      const group = wireGroups[g];
      const outGroup: NshTrayMenuItem[] = [];
      for (let i = 0; i < group.length && topLevelCount < STATUS_BAR_MAX_MENU_ITEMS; i++) {
        const item = group[i];
        if (item.enabled === false) {
          continue;
        }
        if (item.kind === "submenu") {
          const subMenu: NshTraySubMenuItem[] = [];
          collectSubItems(item.items ?? [], subMenu);
          if (subMenu.length === 0) {
            continue;
          }
          const menuItem: NshTrayMenuItem = {
            title: item.label ?? "",
            subMenu,
          };
          if (supportsItemOptions) {
            menuItem.menuCode = `nsh-${generation}-${++seq}`;
          }
          outGroup.push(menuItem);
          topLevelCount++;
        } else {
          const code = makeCode(item);
          const title =
            item.checked === true && !supportsItemOptions
              ? `✓ ${item.label ?? ""}`
              : item.label ?? "";
          const menuItem: NshTrayMenuItem = {
            title,
            menuAction: {
              abilityName,
              moduleName,
              notifyOnly: true,
              menuCode: code,
            },
          };
          if (supportsItemOptions) {
            menuItem.menuCode = code;
            if (item.checked !== undefined) {
              menuItem.options = { selected: item.checked === true };
            }
          }
          outGroup.push(menuItem);
          topLevelCount++;
        }
      }
      if (outGroup.length > 0) {
        result.push(outGroup);
      }
    }
    return result;
  }

  private async decodeTrayIcons(icon?: WireTrayIcon): Promise<NshTrayIcon> {
    const base64 = new util.Base64Helper();
    if (
      icon &&
      icon.format === "rgba" &&
      icon.width &&
      icon.height &&
      icon.whiteBase64 &&
      icon.blackBase64
    ) {
      try {
        const whiteBytes = base64.decodeSync(icon.whiteBase64);
        const blackBytes = base64.decodeSync(icon.blackBase64);
        const whiteBuf = whiteBytes.buffer.slice(
          whiteBytes.byteOffset,
          whiteBytes.byteOffset + whiteBytes.byteLength,
        );
        const blackBuf = blackBytes.buffer.slice(
          blackBytes.byteOffset,
          blackBytes.byteOffset + blackBytes.byteLength,
        );
        const opts: image.InitializationOptions = {
          size: { width: icon.width, height: icon.height },
          srcPixelFormat: image.PixelMapFormat.RGBA_8888,
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          alphaType: image.AlphaType.PREMUL,
        };
        const white = await image.createPixelMap(whiteBuf, opts);
        try {
          const black = await image.createPixelMap(blackBuf, opts);
          return { white, black };
        } catch (error) {
          white.release().catch((): void => {});
          throw error instanceof Error ? error : new Error(String(error));
        }
      } catch (error) {
        console.warn(`[NSH] tray RGBA icon decode failed: ${String(error)}`);
      }
    } else if (icon && icon.format === "encoded" && icon.dataBase64) {
      try {
        const raw = base64.decodeSync(icon.dataBase64);
        const rawBuf = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
        const source = image.createImageSource(rawBuf);
        try {
          const opts: image.DecodingOptions = {
            desiredSize: { width: 48, height: 48 },
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          };
          const white = await source.createPixelMap(opts);
          try {
            const black = await source.createPixelMap(opts);
            return { white, black };
          } catch (error) {
            white.release().catch((): void => {});
            throw error instanceof Error ? error : new Error(String(error));
          }
        } finally {
          source.release().catch((): void => {});
        }
      } catch (error) {
        console.warn(`[NSH] tray encoded icon decode failed: ${String(error)}`);
      }
    }
    return this.createFallbackTrayIcons();
  }

  private async createFallbackTrayIcons(): Promise<NshTrayIcon> {
    const side = 48;
    const whitePixels = new Uint8Array(side * side * 4);
    const blackPixels = new Uint8Array(side * side * 4);
    const cx = (side - 1) / 2;
    const cy = (side - 1) / 2;
    const r = side * 0.34;
    for (let y = 0; y < side; y++) {
      for (let x = 0; x < side; x++) {
        const dist = Math.hypot(x - cx, y - cy);
        const cov = Math.max(0, Math.min(1, r + 0.75 - dist));
        const alpha = Math.round(cov * 255);
        const idx = (y * side + x) * 4;
        whitePixels[idx] = alpha;
        whitePixels[idx + 1] = alpha;
        whitePixels[idx + 2] = alpha;
        whitePixels[idx + 3] = alpha;
        blackPixels[idx + 3] = alpha;
      }
    }
    const opts: image.InitializationOptions = {
      size: { width: side, height: side },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.PREMUL,
    };
    const white = await image.createPixelMap(whitePixels.buffer, opts);
    try {
      const black = await image.createPixelMap(blackPixels.buffer, opts);
      return { white, black };
    } catch (error) {
      white.release().catch((): void => {});
      throw error instanceof Error ? error : new Error(String(error));
    }
  }
}
