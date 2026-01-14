import path from 'path';
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";

export const getExposedPath = (config: HardhatRuntimeEnvironment["config"]) => path.join(config.paths.root, config.exposed.outDir);