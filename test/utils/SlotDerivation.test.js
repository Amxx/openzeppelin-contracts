import { network } from 'hardhat';
import { expect } from 'chai';
import { erc7201Slot } from '../helpers/storage';
import * as types from '../helpers/types';

const {
  ethers,
  networkHelpers: { loadFixture },
} = await network.create();

async function fixture() {
  const [account] = await ethers.getSigners();
  const mock = await ethers.deployContract('$SlotDerivation');
  return { mock, account };
}

describe('SlotDerivation', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('namespaces', function () {
    const namespace = 'example.main';

    it('erc-7201', async function () {
      expect(await this.mock.$erc7201Slot(namespace)).to.equal(erc7201Slot(namespace));
    });
  });

  describe('derivation', function () {
    it('offset', async function () {
      const base = types.bytes32.random();
      const offset = types.uint256.random();
      expect(await this.mock.$offset(base, offset)).to.equal((ethers.toBigInt(base) + offset) & ethers.MaxUint256);
    });

    it('array', async function () {
      const base = types.bytes32.random();
      expect(await this.mock.$deriveArray(base)).to.equal(ethers.keccak256(base));
    });

    describe('mapping', function () {
      for (const { type, key, isValueType } of [
        { type: 'bool', key: true, isValueType: true },
        { type: 'address', key: types.address.random(), isValueType: true },
        { type: 'bytes32', key: types.bytes32.random(), isValueType: true },
        { type: 'uint256', key: types.uint256.random(), isValueType: true },
        { type: 'int256', key: types.int256.random(), isValueType: true },
        { type: 'bytes', key: types.bytes.random(128), isValueType: false },
        { type: 'string', key: 'lorem ipsum', isValueType: false },
      ]) {
        it(type, async function () {
          const base = types.bytes32.random();
          const expected = isValueType
            ? ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode([type, 'bytes32'], [key, base]))
            : ethers.solidityPackedKeccak256([type, 'bytes32'], [key, base]);
          expect(await this.mock[`$deriveMapping(bytes32,${type})`](base, key)).to.equal(expected);
        });
      }
    });
  });
});
