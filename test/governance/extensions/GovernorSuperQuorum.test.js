const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { GovernorHelper } = require('../../helpers/governance');
const { ProposalState, VoteType } = require('../../helpers/enums');

const TOKENS = [
  { Token: '$ERC20Votes', mode: 'blocknumber' },
  { Token: '$ERC20VotesTimestampMock', mode: 'timestamp' },
];

const name = 'OZ-Governor';
const version = '1';
const tokenName = 'MockToken';
const tokenSymbol = 'MTKN';
const tokenSupply = ethers.parseEther('100');
const quorum = 0n;
const superQuorum = ethers.parseEther('30');
const votingDelay = 4n;
const votingPeriod = 16n;
const value = ethers.parseEther('1');

describe('GovernorSuperQuorum', function () {
  for (const { Token, mode } of TOKENS) {
    const fixture = async () => {
      const [owner, voter1, voter2, voter3, voter4] = await ethers.getSigners();
      const receiver = await ethers.deployContract('CallReceiverMock');

      const token = await ethers.deployContract(Token, [tokenName, tokenSymbol, tokenName, version]);
      const mock = await ethers.deployContract('$GovernorSuperQuorumMock', [name, token, superQuorum]);

      await owner.sendTransaction({ to: mock, value });
      await token.$_mint(owner, tokenSupply);

      const helper = new GovernorHelper(mock, mode);
      await helper.connect(owner).delegate({ token, to: voter1, value: ethers.parseEther('30') });
      await helper.connect(owner).delegate({ token, to: voter2, value: ethers.parseEther('20') });
      await helper.connect(owner).delegate({ token, to: voter3, value: ethers.parseEther('15') });
      await helper.connect(owner).delegate({ token, to: voter4, value: ethers.parseEther('5') });

      return { owner, voter1, voter2, voter3, voter4, receiver, token, mock, helper };
    };

    describe(`using ${Token}`, function () {
      beforeEach(async function () {
        Object.assign(this, await loadFixture(fixture));

        // default proposal
        this.proposal = this.helper.setProposal(
          [
            {
              target: this.receiver.target,
              value,
              data: this.receiver.interface.encodeFunctionData('mockFunction'),
            },
          ],
          '<proposal description>',
        );
      });

      it('deployment check', async function () {
        expect(await this.mock.name()).to.equal(name);
        expect(await this.mock.token()).to.equal(this.token);
        expect(await this.mock.votingDelay()).to.equal(votingDelay);
        expect(await this.mock.votingPeriod()).to.equal(votingPeriod);
        expect(await this.mock.quorum(0n)).to.equal(quorum);
        expect(await this.mock.superQuorum(0n)).to.equal(superQuorum);
      });

      it('proposal remains active until super quorum is reached', async function () {
        await this.helper.propose();
        await this.helper.waitForSnapshot();

        // 20 votes for (superQuorum is 30)
        await this.helper.connect(this.voter2).vote({ support: VoteType.For });

        // Check proposal is still active
        expect(await this.mock.state(this.proposal.id)).to.equal(ProposalState.Active);

        // 20+15 = 35 votes for (superQuorum is 30)
        await this.helper.connect(this.voter3).vote({ support: VoteType.For });

        // Proposal should no longer be active
        expect(await this.mock.state(this.proposal.id)).to.equal(ProposalState.Succeeded);

        // Proposal can be executed
        await expect(this.helper.execute()).to.not.be.reverted;
      });
    });
  }
});
