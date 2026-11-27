import { common } from "@kit.AbilityKit";
import { getPlatformProviders } from "./PlatformProviders";

export async function deleteToTrash(
  context: common.UIAbilityContext,
  uri: string,
  path: string,
): Promise<string> {
  return await getPlatformProviders().trash.moveToTrash(context, uri, path);
}
