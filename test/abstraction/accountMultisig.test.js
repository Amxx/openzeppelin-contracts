const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { ERC4337Helper } = require('../helpers/erc4337');

async function fixture() {
  const accounts = await ethers.getSigners();
  accounts.user = accounts.shift();
  accounts.beneficiary = accounts.shift();
  accounts.signers = Array(3)
    .fill()
    .map(() => accounts.shift());

  const target = await ethers.deployContract('CallReceiverMock');
  const helper = new ERC4337Helper('AdvancedAccountECDSA');
  await helper.wait();
  const sender = await helper.newAccount(accounts.user, [accounts.signers, 2]); // 2-of-3

  return {
    accounts,
    target,
    helper,
    entrypoint: helper.entrypoint,
    factory: helper.factory,
    sender,
  };
}

describe('AccountMultisig', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('execute operation', function () {
    beforeEach('fund account', async function () {
      await this.accounts.user.sendTransaction({ to: this.sender, value: ethers.parseEther('1') });
    });

    describe('account not deployed yet', function () {
      it('success: deploy and call', async function () {
        const operation = await this.sender
          .createOp({
            callData: this.sender.interface.encodeFunctionData('execute', [
              this.target.target,
              17,
              this.target.interface.encodeFunctionData('mockFunctionExtra'),
            ]),
          })
          .then(op => op.addInitCode())
          .then(op => op.sign(this.accounts.signers));

        await expect(this.entrypoint.handleOps([operation.packed], this.accounts.beneficiary))
          .to.emit(this.entrypoint, 'AccountDeployed')
          .withArgs(operation.hash, this.sender, this.factory, ethers.ZeroAddress)
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.sender, 17);
      });
    });

    describe('account already deployed', function () {
      beforeEach(async function () {
        await this.sender.deploy();
      });

      it('success: 3 signers', async function () {
        const operation = await this.sender
          .createOp({
            callData: this.sender.interface.encodeFunctionData('execute', [
              this.target.target,
              42,
              this.target.interface.encodeFunctionData('mockFunctionExtra'),
            ]),
          })
          .then(op => op.sign(this.accounts.signers));

        await expect(this.entrypoint.handleOps([operation.packed], this.accounts.beneficiary))
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.sender, 42);
      });

      it('success: 2 signers', async function () {
        const operation = await this.sender
          .createOp({
            callData: this.sender.interface.encodeFunctionData('execute', [
              this.target.target,
              42,
              this.target.interface.encodeFunctionData('mockFunctionExtra'),
            ]),
          })
          .then(op => op.sign([this.accounts.signers[0], this.accounts.signers[2]]));

        await expect(this.entrypoint.handleOps([operation.packed], this.accounts.beneficiary))
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.sender, 42);
      });

      it('revert: not enough signers', async function () {
        const operation = await this.sender
          .createOp({
            callData: this.sender.interface.encodeFunctionData('execute', [
              this.target.target,
              42,
              this.target.interface.encodeFunctionData('mockFunctionExtra'),
            ]),
          })
          .then(op => op.sign([this.accounts.signers[2]]));

        await expect(this.entrypoint.handleOps([operation.packed], this.accounts.beneficiary))
          .to.be.revertedWithCustomError(this.entrypoint, 'FailedOp')
          .withArgs(0, 'AA24 signature error');
      });

      it('revert: unauthorized signer', async function () {
        const operation = await this.sender
          .createOp({
            callData: this.sender.interface.encodeFunctionData('execute', [
              this.target.target,
              42,
              this.target.interface.encodeFunctionData('mockFunctionExtra'),
            ]),
          })
          .then(op => op.sign([this.accounts.user, this.accounts.signers[2]]));

        await expect(this.entrypoint.handleOps([operation.packed], this.accounts.beneficiary))
          .to.be.revertedWithCustomError(this.entrypoint, 'FailedOp')
          .withArgs(0, 'AA24 signature error');
      });
    });
  });
});