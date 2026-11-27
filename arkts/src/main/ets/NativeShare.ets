import { common } from "@kit.AbilityKit";
import type { SystemRequest, SystemReply } from "./NativeSystem";
import { getPlatformProviders } from "./PlatformProviders";

export class NativeShare {
  private readonly pending: Map<number, () => void> = new Map();

  async show(
    context: common.UIAbilityContext,
    key: number,
    request: SystemRequest,
    live: () => boolean,
  ): Promise<SystemReply> {
    try {
      const result = await getPlatformProviders().share.show(
        context,
        {
          paths: request.paths,
          text: request.text,
          uri: request.uri,
          title: request.title,
        },
        live,
        (cancel: () => void): void => {
          this.pending.set(key, cancel);
        },
      );
      return {
        phase: result.phase,
        text: result.text,
        error: result.error,
      };
    } finally {
      this.pending.delete(key);
    }
  }

  cancel(key: number): void {
    const fn = this.pending.get(key);
    this.pending.delete(key);
    fn?.();
  }

  close(): void {
    const active = Array.from(this.pending.values());
    this.pending.clear();
    for (const cancel of active) {
      cancel();
    }
  }
}
