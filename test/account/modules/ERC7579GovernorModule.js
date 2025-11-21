const { ethers, predeploy } = require('hardhat');
const { expect } = require('chai');
const { loadFixture, setNextBlockBaseFeePerGas } = require('@nomicfoundation/hardhat-network-helpers');

const { impersonate } = require('../../helpers/account');
const { ERC4337Helper, SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('../../helpers/erc4337');
const {
  encodeMode,
  encodeSingle,
  MODULE_TYPE_VALIDATOR,
  MODULE_TYPE_EXECUTOR,
  MODULE_TYPE_FALLBACK,
  CALL_TYPE_CALL,
} = require('../../helpers/erc7579');
const { Enum } = require('../../helpers/enums');
const time = require('../../helpers/time');

const ProposalState = Enum(
  'Unset',
  'Pending',
  'Active',
  'Defeated',
  'Queued',
  'Ready',
  'Executed',
  'Expired',
  'Canceled',
);

const payload = '0x00000000000000000000000000000000000000000000';

const getAddress = obj => obj.address ?? obj.target ?? obj;

const hashConfigId = (executor, payload) =>
  ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['address', 'bytes22'], [getAddress(executor), payload]));

const hashProposalId = (configId, mode, executionCalldata, description) =>
  ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'bytes32', 'bytes', 'bytes32'],
      [configId, mode, executionCalldata, ethers.id(description)],
    ),
  );

async function fixture() {
  // EOAs and environment
  const [other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMock');
  const token = await ethers.deployContract('$ERC20VotesTimestampMock', ['name', 'symbol', 'name', '1']);

  // ERC-7579 modules
  const validator = await ethers.deployContract('$ERC7579ValidatorMock');
  const governor = await ethers.deployContract('$ERC7579GovernorModuleMock');

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const mock = await helper.newAccount('$AccountERC7579Mock', [
    validator,
    ethers.solidityPacked(['address'], [signer.address]),
  ]);

  // fund and deploy the account
  await other.sendTransaction({ to: mock, value: ethers.parseEther('1') });
  await mock.deploy();

  // Install governor module
  await mock.$_installModule(MODULE_TYPE_EXECUTOR, governor, '0x');

  // helper for entrypoint checks
  const mockFromEntrypoint = await impersonate(predeploy.entrypoint.v08.target).then(signer => mock.connect(signer));

  return { helper, token, validator, governor, mock, mockFromEntrypoint, target, other };
}

describe('AccountERC7579', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('check', async function () {
    const { selector } = this.governor.interface.getFunction('handleProposal');

    await expect(this.mock.isModuleInstalled(MODULE_TYPE_VALIDATOR, this.governor, '0x')).to.eventually.equal(true);
    await expect(this.mock.isModuleInstalled(MODULE_TYPE_EXECUTOR, this.governor, '0x')).to.eventually.equal(true);
    await expect(this.mock.isModuleInstalled(MODULE_TYPE_FALLBACK, this.governor, selector)).to.eventually.equal(true);
  });

  describe('nominal workflow', function () {
    beforeEach(async function () {
      // Register governor config for the given payload (identifier)
      await this.governor.UNSAFE_setGovernorConfig(this.mock, payload, {
        token: this.token,
        maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
        maxGasPrice: ethers.parseUnits('20', 'gwei'),
        votingDelay: 10n,
        votingPeriod: 10n,
        executeDelay: 10n,
        executePeriod: 10n,
        sponsorPropose: true,
        sponsorExecute: true,
      });

      // proposal
      this.proposal = [
        encodeMode({ callType: CALL_TYPE_CALL, selector: '0xAABBCCDD', payload }),
        encodeSingle(this.target, 0, this.target.interface.encodeFunctionData('mockFunction')),
        '<description>',
      ];

      this.configId = hashConfigId(this.mock, payload);
      this.proposalId = hashProposalId(this.configId, ...this.proposal);

      // packaging proposal as a self-sponsored userop
      this.userOp = (nonce = 0n) =>
        this.mock.createUserOp({
          callData: this.governor.interface.encodeFunctionData('handleProposal', this.proposal),
          nonce: ethers.toBeHex((ethers.toBigInt(this.governor.target) << 96n) + nonce),
        });
    });

    it('using direct calls', async function () {
      // Propose
      await expect(this.governor.attach(this.mock).handleProposal(...this.proposal))
        .to.emit(this.governor, 'ProposalCreated')
        .withArgs(this.proposalId, this.mock, ...this.proposal);

      // Wait and see the proposal state changes
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Pending);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Active);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Queued);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Ready);

      // Execute
      await expect(this.governor.attach(this.mock).handleProposal(...this.proposal))
        .to.emit(this.governor, 'ProposalExecuted')
        .withArgs(this.proposalId)
        .to.emit(this.target, 'MockFunctionCalled');
    });

    it('using sponsored user ops', async function () {
      const proposeUserOp = await this.userOp(0n);
      const executeUserOp = await this.userOp(1n);

      // Propose
      await expect(predeploy.entrypoint.v08.handleOps([proposeUserOp.packed], this.other))
        .to.emit(this.governor, 'ProposalCreated')
        .withArgs(this.proposalId, this.mock, ...this.proposal);

      // Wait and see the proposal state changes
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Pending);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Active);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Queued);
      await time.increaseBy.timestamp(10n);
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Ready);

      // Execute
      await expect(predeploy.entrypoint.v08.handleOps([executeUserOp.packed], this.other))
        .to.emit(this.governor, 'ProposalExecuted')
        .withArgs(this.proposalId)
        .to.emit(this.target, 'MockFunctionCalled');
    });
  });

  describe('userOp validity', function () {
    beforeEach(async function () {
      // Register governor config for the given payload (identifier)
      await this.governor.UNSAFE_setGovernorConfig(this.mock, payload, {
        token: this.token,
        maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
        maxGasPrice: ethers.parseUnits('20', 'gwei'),
        votingDelay: 10n,
        votingPeriod: 10n,
        executeDelay: 10n,
        executePeriod: 10n,
        sponsorPropose: true,
        sponsorExecute: true,
      });

      // proposal
      this.proposal = [
        encodeMode({ callType: CALL_TYPE_CALL, selector: '0xAABBCCDD', payload }),
        encodeSingle(this.target, 0, this.target.interface.encodeFunctionData('mockFunction')),
        '<description>',
      ];

      this.configId = hashConfigId(this.mock, payload);
      this.proposalId = hashProposalId(this.configId, ...this.proposal);

      // packaging proposal as a self-sponsored userop
      this.userOp = await this.mock.createUserOp({
        callData: this.governor.interface.encodeFunctionData('handleProposal', this.proposal),
        nonce: ethers.toBeHex(ethers.toBigInt(this.governor.target) << 96n),
      });
    });

    it('valid with state=Unset', async function () {
      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Unset);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_SUCCESS);
    });

    it('invalid with state=Pending', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Pending);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid with state=Active', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await time.increaseBy.timestamp(10n);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Active);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid with state=Queued', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await time.increaseBy.timestamp(20n);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Queued);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('valid with state=Ready', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await time.increaseBy.timestamp(30n);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Ready);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_SUCCESS);
    });

    it('invalid with state=Expired', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await time.increaseBy.timestamp(40n);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Expired);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid with state=Cancelled', async function () {
      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await this.governor.$_cancel(this.proposalId);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Canceled);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid with state=Unset and proposal sponsoring is disabled', async function () {
      await this.governor.UNSAFE_setGovernorConfig(this.mock, payload, {
        token: this.token,
        maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
        maxGasPrice: ethers.parseUnits('20', 'gwei'),
        votingDelay: 10n,
        votingPeriod: 10n,
        executeDelay: 10n,
        executePeriod: 10n,
        sponsorPropose: false, // DISABLED
        sponsorExecute: true,
      });

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Unset);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid with state=Ready and execution sponsoring is disabled', async function () {
      await this.governor.UNSAFE_setGovernorConfig(this.mock, payload, {
        token: this.token,
        maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
        maxGasPrice: ethers.parseUnits('20', 'gwei'),
        votingDelay: 10n,
        votingPeriod: 10n,
        executeDelay: 10n,
        executePeriod: 10n,
        sponsorPropose: true,
        sponsorExecute: false, // DISABLED
      });

      await this.governor.attach(this.mock).handleProposal(...this.proposal);
      await time.increaseBy.timestamp(30n);

      await expect(this.governor.state(this.proposalId)).to.eventually.equal(ProposalState.Ready);

      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it('invalid when priority fee is too high', async function () {
      // Users wants to give a very high tip for fast inclusion
      this.userOp.maxPriorityFee = ethers.parseUnits('20', 'gwei');

      // ... this rejected by the governor module
      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });

    it.skip('invalid when gas price is too high', async function () {
      // gas price is high
      await setNextBlockBaseFeePerGas(ethers.parseUnits('100', 'gwei'));

      // ... the user op tries to accepts that high price
      this.userOp.maxFeePerGas = ethers.parseUnits('100', 'gwei');

      // ... this rejected by the governor module
      await expect(
        this.mockFromEntrypoint.validateUserOp.staticCall(this.userOp.packed, this.userOp.hash(), 0),
      ).to.eventually.equal(SIG_VALIDATION_FAILURE);
    });
  });
});
