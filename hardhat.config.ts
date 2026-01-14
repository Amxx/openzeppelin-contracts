import { defineConfig, overrideTask } from "hardhat/config";

// Plugins
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatEthersChaiMatchers from "@nomicfoundation/hardhat-ethers-chai-matchers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatNetworkHelpers from "@nomicfoundation/hardhat-network-helpers";
import hardhatPredeploy from "hardhat-predeploy";

import hardhatExposed from "./hardhat/exposed/plugin";
import hardhatOZ from "./hardhat/oz/index";

// Parameters
import yargs from "yargs/yargs";
const argv = await yargs()
  .env('')
  .options({
    // Compilation settings
    compiler: {
      type: 'string',
      default: '0.8.31',
    },
    src: {
      type: 'string',
      default: 'contracts',
    },
    runs: {
      type: 'number',
      default: 200,
    },
    ir: {
      type: 'boolean',
      default: false,
    },
    evm: {
      type: 'string',
      default: 'osaka',
    },
  })
  .parse();

// Configuration
export default defineConfig({
  plugins: [
    hardhatEthers,
    hardhatEthersChaiMatchers,
    hardhatNetworkHelpers,
    hardhatMocha,
    hardhatPredeploy,

    hardhatExposed,
    hardhatOZ,
  ],
  paths: {
    sources: argv.src,
  },
  solidity: {
    version: argv.compiler,
    settings: {
      optimizer: {
        enabled: true,
        runs: argv.runs,
      },
      evmVersion: argv.evm,
      viaIR: argv.ir,
      outputSelection: { '*': { '*': ['storageLayout'] } },
    },
  },
  networks: {
    default: {
      type: 'edr-simulated',
      hardfork: argv.evm,
      // Exposed contracts often exceed the maximum contract size. For normal contract,
      // we rely on the `code-size` compiler warning, that will cause a compilation error.
      // allowUnlimitedContractSize: true,
      // initialBaseFeePerGas: argv.coverage ? 0 : undefined,
    },
  },
  test: {
    solidity: {
      fuzz: {
        // runs: 5000,
        // maxTestRejects: 150000,
      },
      fsPermissions: {
        readDirectory: [
          'node_modules/hardhat-predeploy/bin',
        ],
      },
    }
  },
  exposed: {
    imports: true,
    initializers: true,
    exclude: ['contracts/vendor/**/*', '**/*WithInit.sol'],
  },
  // TODO: warnings
});
