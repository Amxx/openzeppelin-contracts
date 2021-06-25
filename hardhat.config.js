/// ENVVAR
// - ENABLE_GAS_REPORT
// - CI
// - COMPILE_MODE

const fs = require('fs');
const path = require('path');
const argv = require('yargs/yargs')()
  .env('')
  .option('target', { type: 'choice', default: 'evm', choices: ['evm', 'ovm'] })
  .boolean('enableGasReport')
  .boolean('ci')
  .string('compileMode')
  .argv;

require('@nomiclabs/hardhat-truffle5');
require('solidity-coverage');

if (argv.target === 'ovm') {
  require('@eth-optimism/plugins/hardhat/compiler');
}

if (argv.enableGasReport) {
  require('hardhat-gas-reporter');
}

for (const f of fs.readdirSync(path.join(__dirname, 'hardhat'))) {
  require(path.join(__dirname, 'hardhat', f));
}

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: '0.8.3',
    settings: {
      optimizer: {
        enabled: argv.enableGasReport || argv.compileMode === 'production',
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 10000000,
      ovm: argv.target === 'ovm',
    },
  },
  gasReporter: {
    currency: 'USD',
    outputFile: argv.ci ? 'gas-report.txt' : undefined,
  },
};
