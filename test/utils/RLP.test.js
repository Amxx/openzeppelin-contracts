const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { generators } = require('../helpers/random');

async function fixture() {
  return { mock: await ethers.deployContract('$RLP') };
}

describe('RLP', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Encode', function () {
    it('encode(true)', async function () {
      await expect(this.mock.getFunction('$encode(bool)')(true)).to.eventually.equal('0x01');
    });

    it('encode(false)', async function () {
      await expect(this.mock.getFunction('$encode(bool)')(false)).to.eventually.equal('0x80');
    });

    it('encode(address)', async function () {
      for (const address of [ethers.ZeroAddress, this.mock.target]) {
        // 0x94 is 0x80 + 0x14 (length of an address)
        await expect(this.mock.getFunction('$encode(address)')(address)).to.eventually.equal(
          ethers.concat(['0x94', address]),
        );
      }
    });

    it('encode(bytes)', async function () {
      for (const buffer of [
        '0x',
        '0x10',
        '0x7f',
        generators.bytes(32),
        generators.bytes(55),
        generators.bytes(56),
        generators.bytes(256),
        generators.bytes(1024),
      ]) {
        await expect(this.mock.getFunction('$encode(bytes)')(buffer)).to.eventually.equal(ethers.encodeRlp(buffer));
      }
    });

    it('encode(bytes[])', async function () {
      for (const list of [
        [],
        ['0x'],
        ['0x10'],
        ['0x', '0x'],
        ['0x', '0x7f', '0x', '0x80'],
        Array.from({ length: 32 }, () => generators.bytes(32)), // 32 objects of size 32 each
        Array.from({ length: 128 }, () => generators.bytes(8)), // 128 objects of size 8 each
      ]) {
        await expect(this.mock.getFunction('$encode(bytes[])')(list.map(ethers.encodeRlp))).to.eventually.equal(
          ethers.encodeRlp(list),
          JSON.stringify(list),
        );
      }
    });

    it('createAddress', async function () {
      const from = generators.address();

      for (const nonce of [0n, 1n, 127n, 128n, 65535n]) {
        // keccak256(encode([ encode(from), encode(nonce) ])).slice(-20);
        const encoded = await this.mock.getFunction('$encode(bytes[])')([
          await this.mock.getFunction('$encode(address)')(from),
          await this.mock.getFunction('$encode(uint256)')(nonce),
        ]);
        const hash = ethers.keccak256(encoded);
        const addr = ethers.hexlify(ethers.getBytes(hash).slice(-20));

        expect(ethers.getAddress(addr)).to.equal(ethers.getCreateAddress({ from, nonce }));
      }
    });
  });
});
