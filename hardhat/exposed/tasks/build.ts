import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";
import type {} from "../type-extensions";

import { getExposedPath } from "../core";

// See: hardhat/src/internal/builtin-plugins/solidity/tasks/build.ts
interface BuildActionArguments {
  force: boolean;
  files: string[];
  quiet: boolean;
  defaultBuildProfile: string | undefined;
  noTests: boolean;
  noContracts: boolean;
}

export default async function (
  taskArguments: BuildActionArguments,
  hre: HardhatRuntimeEnvironment,
  superCall: (taskArguments: BuildActionArguments) => Promise<any>
) {
  if (taskArguments.force) {
    const fs = await import('fs/promises');
    await fs.rm(getExposedPath(hre.config), { recursive: true, force: true });
  }
  return superCall(taskArguments);
}
