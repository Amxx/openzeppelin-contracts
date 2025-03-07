const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { PANIC_CODES } = require('@nomicfoundation/hardhat-chai-matchers/panic');

const BEGIN = 0n;
const END = 0n;

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

  describe('empty list', function () {
    afterEach(async function () {
      if (this.values) {
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values);
        await expect(this.mock.$length(0n)).to.eventually.equal(this.values.length);
      }
      if (this.values?.length) {
        await expect(this.mock.$front(0n)).to.eventually.equal(this.values.at(0));
        await expect(this.mock.$back(0n)).to.eventually.equal(this.values.at(-1));
      }
    });

    it('insertBefore', async function () {
      this.values = [17n];
      await this.mock.$insertBefore(0, END, 17n);
    });

    it('insertAfter', async function () {
      this.values = [17n];
      await this.mock.$insertAfter(0, BEGIN, 17n);
    });

    it('insertAt', async function () {
      this.values = [17n];
      await this.mock.$insertAt(0, 0n, 17n);
    });

    it('insertAt - out of bound', async function () {
      this.values = [];
      await expect(this.mock.$insertAt(0, 1n, 17n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('pushFront', async function () {
      this.values = [17n];
      await this.mock.$pushFront(0, 17n);
    });

    it('pushBack', async function () {
      this.values = [17n];
      await this.mock.$pushBack(0, 17n);
    });

    it('remove', async function () {
      this.values = [];
      await expect(this.mock.$remove(0n, BEGIN)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('removeAt', async function () {
      this.values = [];
      await expect(this.mock.$removeAt(0n, 0n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
      await expect(this.mock.$removeAt(0n, 1n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('popFront', async function () {
      this.values = [];
      await expect(this.mock.$popFront(0n)).to.be.revertedWithPanic(PANIC_CODES.POP_ON_EMPTY_ARRAY);
    });

    it('popBack', async function () {
      this.values = [];
      await expect(this.mock.$popBack(0n)).to.be.revertedWithPanic(PANIC_CODES.POP_ON_EMPTY_ARRAY);
    });

    it('clear', async function () {
      this.values = [];
      await this.mock.$clear(0n);
    });

    it('clear and push', async function () {
      this.values = [17];
      await this.mock.$clear(0n);
      await this.mock.$pushBack(0n, 17n);
    });
  });

  describe('non-empty list', function () {
    beforeEach(async function () {
      this.values = [1n, 2n, 3n, 4n, 5n];
      for (const value of this.values) await this.mock.$pushBack(0n, value);
    });

    afterEach(async function () {
      if (this.values) {
        await expect(fetchValues(this.mock)).to.eventually.deep.equal(this.values);
        await expect(this.mock.$length(0n)).to.eventually.equal(this.values.length);
      }
      if (this.values?.length) {
        await expect(this.mock.$front(0n)).to.eventually.equal(this.values.at(0));
        await expect(this.mock.$back(0n)).to.eventually.equal(this.values.at(-1));
      }
    });

    it('insertBefore - Middle', async function () {
      this.values.splice(2, 0, 17n);
      await this.mock.$forward(0n, BEGIN, ethers.Typed.uint16(3n)).then(it => this.mock.$insertBefore(0, it, 17n));
    });

    it('insertBefore - END', async function () {
      this.values.push(17n);
      await this.mock.$insertBefore(0, END, 17n);
    });

    it('insertAfter - Middle', async function () {
      this.values.splice(3, 0, 17n);
      await this.mock.$forward(0n, BEGIN, ethers.Typed.uint16(3n)).then(it => this.mock.$insertAfter(0, it, 17n));
    });

    it('insertAfter - BEGIN', async function () {
      this.values.unshift(17n);
      await this.mock.$insertAfter(0, END, 17n);
    });

    it('insertAt', async function () {
      this.values.splice(3, 0, 17n);
      await this.mock.$insertAt(0, 3n, 17n);
    });

    it('insertAt - out of bound', async function () {
      await expect(this.mock.$insertAt(0, 10n, 17n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('pushFront', async function () {
      this.values.unshift(17n);
      await this.mock.$pushFront(0, 17n);
    });

    it('pushBack', async function () {
      this.values.push(17n);
      await this.mock.$pushBack(0, 17n);
    });

    it('remove', async function () {
      this.values.splice(2, 1);
      await this.mock.$forward(0n, BEGIN, ethers.Typed.uint16(3n)).then(it => this.mock.$remove(0, it));
    });

    it('remove - invalid', async function () {
      await expect(this.mock.$remove(0n, BEGIN)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('removeAt', async function () {
      this.values.splice(3, 1);
      await this.mock.$removeAt(0n, 3n);
    });

    it('removeAt - out of bound', async function () {
      await expect(this.mock.$removeAt(0n, 10n)).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('popFront', async function () {
      const value = this.values.shift();
      await expect(this.mock.$popFront(0n)).to.emit(this.mock, 'return$popFront').withArgs(value);
    });

    it('popBack', async function () {
      const value = this.values.pop();
      await expect(this.mock.$popBack(0n)).to.emit(this.mock, 'return$popBack').withArgs(value);
    });

    it('clear', async function () {
      this.values = [];
      await this.mock.$clear(0n);
    });

    it('clear and push', async function () {
      this.values = [17];
      await this.mock.$clear(0n);
      await this.mock.$pushBack(0n, 17n);
    });
  });
});
