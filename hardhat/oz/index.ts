import type { HardhatPlugin } from "hardhat/types/plugins";

const hardhatOpenZeppelinPlugin: HardhatPlugin = {
  id: "hardhat-openzeppelin",
  hookHandlers: {
    hre: () => import("./hook-handlers/hre.js"),
  },
  npmPackage: "hardhat-openzeppelin",
};

export default hardhatOpenZeppelinPlugin;