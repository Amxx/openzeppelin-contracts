// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "../Governor.sol";

/**
 * @dev Extension of {Governor} with a super quorum expressed. Proposals that meet the super quorum
 * can be executed earlier than the proposal deadline.
 */
abstract contract GovernorSuperQuorum is Governor {
    /// @dev Returns the super quorum for a timepoint
    function superQuorum(uint256 timepoint) public view virtual returns (uint256);

    /// @dev Get current distribution of votes for a given proposal.
    function proposalVotes(
        uint256 proposalId
    ) public view virtual returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);

    /// @inheritdoc Governor
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);
        if (currentState != ProposalState.Active) return currentState;

        (, uint256 forVotes, ) = proposalVotes(proposalId);
        return forVotes < superQuorum(proposalSnapshot(proposalId)) ? currentState : ProposalState.Succeeded;
    }
}
