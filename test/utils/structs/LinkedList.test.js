const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { PANIC_CODES } = require('@nomicfoundation/hardhat-chai-matchers/panic');

async function fixture() {
  const mock = await ethers.deployContract('$LinkedLists');
  return { mock };
}

async function fetchValues(mock, i = 0n) {
  const values = [];

  for (let it = 0n; ; ) {
    if ((it = await mock.$forward(i, it)) == 0) break;
    await mock.$at(i, it).then(value => values.push(value));
  }

  return values;
}

describe('LinkedList', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('insert', function () {
    it('into an empty linked list', async function () {
      const vals = [1n, 2n, 3n, 4n, 5n];
      for (const val of vals) {
        await this.mock.$pushBack(0n, val);
      }

      await expect(fetchValues(this.mock)).to.eventually.deep.equal(vals);
    });

    describe('into a non-empty linked list', function () {
      beforeEach(async function () {
        this.values = [1n, 3n];
        for (const val of this.values) {
          await this.mock.$pushBack(0n, val);
        }
      });

      it('at the center', async function () {
        await this.mock.$insertAt(0n, 1n, 2n);
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values.toSpliced(1, 0, 2n));
      });

      it('at the beginning', async function () {
        await this.mock.$insertAt(0n, 0n, 0n);
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values.toSpliced(0, 0, 0n));
      });

      it('at the end', async function () {
        await this.mock.$insertAt(0n, 2n, 4n);
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values.toSpliced(2, 0, 4n));
      });
    });
  });

  describe('remove', function () {
    it('from an empty linked list', async function () {
      await expect(this.mock.$removeAt(0n, 0n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    describe('from a non-empty linked list', function () {
      beforeEach(async function () {
        this.values = [1n, 2n, 3n, 4n, 5n];
        for (const val of this.values) {
          await this.mock.$pushBack(0n, val);
        }
      });

      afterEach(async function () {
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values);
        await expect(this.mock.$front(0n)).to.eventually.equal(this.values.at(0));
        await expect(this.mock.$back(0n)).to.eventually.equal(this.values.at(-1));
      });

      it('at the center', async function () {
        await this.mock.$removeAt(0n, 2n);
        this.values.splice(2, 1);
      });

      it('at the beginning', async function () {
        await this.mock.$removeAt(0n, 0n);
        this.values.splice(0, 1);
      });

      it('at the end via `removeAt`', async function () {
        await this.mock.$removeAt(0n, 4n);
        this.values.splice(4, 1);
      });

      it('at the end via `popBack`', async function () {
        await this.mock.$popBack(0n);
        this.values.pop();
      });
    });
  });
});
