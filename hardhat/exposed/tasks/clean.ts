import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";
import type {} from "../type-extensions";

import { getExposedPath } from "../core";

// See: hardhat/src/internal/builtin-plugins/clean/task-action.ts
interface CleanActionArguments {
  global: boolean;
}

export default async function (
  taskArguments: CleanActionArguments,
  hre: HardhatRuntimeEnvironment,
  superCall: (taskArguments: CleanActionArguments) => Promise<any>
) {
  if (!taskArguments.global) {
      const fs = await import('fs/promises');
      await fs.rm(getExposedPath(hre.config), { recursive: true, force: true });
  }
  return superCall(taskArguments);
}
