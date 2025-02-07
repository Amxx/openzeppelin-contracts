// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Governor} from "../../governance/Governor.sol";
import {GovernorVotes} from "../../governance/extensions/GovernorVotes.sol";
import {GovernorCountingSimple} from "../../governance/extensions/GovernorCountingSimple.sol";
import {GovernorSuperQuorum} from "../../governance/extensions/GovernorSuperQuorum.sol";

abstract contract GovernorSuperQuorumMock is GovernorVotes, GovernorCountingSimple, GovernorSuperQuorum {
    uint256 private _superQuorum;

    constructor(uint256 superQuorum_) {
        _superQuorum = superQuorum_;
    }

    function proposalVotes(
        uint256 proposalId
    )
        public
        view
        virtual
        override(GovernorCountingSimple, GovernorSuperQuorum)
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        return super.proposalVotes(proposalId);
    }

    function state(
        uint256 proposalId
    ) public view virtual override(Governor, GovernorSuperQuorum) returns (ProposalState) {
        return super.state(proposalId);
    }

    function superQuorum(uint256) public view override returns (uint256) {
        return _superQuorum;
    }

    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    function votingDelay() public pure override returns (uint256) {
        return 4;
    }

    function votingPeriod() public pure override returns (uint256) {
        return 16;
    }
}
