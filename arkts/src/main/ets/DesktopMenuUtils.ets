export interface WireMenuItem {
  kind: string;
  id?: number;
  label?: string;
  enabled?: boolean;
  checked?: boolean;
  shortcut?: string;
  role?: string;
  destructive?: boolean;
  items?: WireMenuItem[];
}

export function splitMenuGroups(items: WireMenuItem[]): WireMenuItem[][] {
  const groups: WireMenuItem[][] = [];
  let current: WireMenuItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item.kind === "separator") {
      if (current.length > 0) {
        groups.push(current);
        current = [];
      }
    } else {
      current.push(item);
    }
  }
  if (current.length > 0) {
    groups.push(current);
  }
  return groups;
}

const FNV_OFFSET_64: bigint = BigInt("0xcbf29ce484222325");
const FNV_PRIME_64: bigint = BigInt("0x00000100000001b3");
const MASK_64: bigint = BigInt("0xffffffffffffffff");

// 64-bit FNV-1a hex digest; matches `nsh_core::desktop::DisplayId::from_name` for ASCII names.
export function fnv1a64Hex(input: string): string {
  let hash: bigint = FNV_OFFSET_64;
  for (let i = 0; i < input.length; i++) {
    hash = hash ^ BigInt(input.charCodeAt(i) & 0xff);
    hash = (hash * FNV_PRIME_64) & MASK_64;
  }
  return hash.toString(16).padStart(16, "0");
}
