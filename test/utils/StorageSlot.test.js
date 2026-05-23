import { network } from 'hardhat';
import { expect } from 'chai';
import * as types from '../helpers/types';

const {
  ethers,
  networkHelpers: { loadFixture },
} = await network.create();

const slot = ethers.id('some.storage.slot');
const otherSlot = ethers.id('some.other.storage.slot');

const TYPES = [
  { name: 'Boolean', type: 'bool', value: true, isValueType: true, zero: false },
  { name: 'Address', type: 'address', value: types.address.random(), isValueType: true, zero: types.address.zero },
  { name: 'Bytes32', type: 'bytes32', value: types.bytes32.random(), isValueType: true, zero: types.bytes32.zero },
  { name: 'Uint256', type: 'uint256', value: types.uint256.random(), isValueType: true, zero: types.uint256.zero },
  { name: 'Int256', type: 'int256', value: types.int256.random(), isValueType: true, zero: types.int256.zero },
  { name: 'Bytes', type: 'bytes', value: types.hexBytes.random(128), isValueType: false, zero: types.hexBytes.zero },
  { name: 'String', type: 'string', value: 'lorem ipsum', isValueType: false, zero: '' },
];

async function fixture() {
  return { mock: await ethers.deployContract('StorageSlotMock') };
}

describe('StorageSlot', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  for (const { name, type, value, zero } of TYPES) {
    describe(`${type} storage slot`, function () {
      it('set', async function () {
        await this.mock.getFunction(`set${name}Slot`)(slot, value);
      });

      describe('get', function () {
        beforeEach(async function () {
          await this.mock.getFunction(`set${name}Slot`)(slot, value);
        });

        it('from right slot', async function () {
          expect(await this.mock.getFunction(`get${name}Slot`)(slot)).to.equal(value);
        });

        it('from other slot', async function () {
          expect(await this.mock.getFunction(`get${name}Slot`)(otherSlot)).to.equal(zero);
        });
      });
    });
  }

  for (const { name, type, value, zero } of TYPES.filter(type => !type.isValueType)) {
    describe(`${type} storage pointer`, function () {
      it('set', async function () {
        await this.mock.getFunction(`set${name}Storage`)(slot, value);
      });

      describe('get', function () {
        beforeEach(async function () {
          await this.mock.getFunction(`set${name}Storage`)(slot, value);
        });

        it('from right slot', async function () {
          expect(await this.mock.getFunction(`${type}Map`)(slot)).to.equal(value);
          expect(await this.mock.getFunction(`get${name}Storage`)(slot)).to.equal(value);
        });

        it('from other slot', async function () {
          expect(await this.mock.getFunction(`${type}Map`)(otherSlot)).to.equal(zero);
          expect(await this.mock.getFunction(`get${name}Storage`)(otherSlot)).to.equal(zero);
        });
      });
    });
  }
});
