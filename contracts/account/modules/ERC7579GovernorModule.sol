// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "../../interfaces/draft-IERC4337.sol";

import {
    IERC7579Module,
    IERC7579Validator,
    IERC7579Execution,
    IERC7579ModuleConfig,
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK
} from "../../interfaces/draft-IERC7579.sol";

import {IERC6372} from "../../interfaces/IERC6372.sol";
import {ERC4337Utils} from "../utils/draft-ERC4337Utils.sol";
import {ERC7579Utils, Mode, CallType, ModeSelector, ModePayload} from "../utils/draft-ERC7579Utils.sol";
import {Math} from "../../utils/math/Math.sol";
import {Calldata} from "../../utils/Calldata.sol";

abstract contract ERC7579GovernorModule is IERC7579Module, IERC7579Validator, IERC6372 {
    using Math for uint256;

    ModeSelector private constant MODE_SELECTOR_GOVERNOR = ModeSelector.wrap(0xAABBCCDD); // TODO value
    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP = bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);

    enum ProposalState {
        Unset,
        Pending,
        Active,
        Defeated,
        Queued,
        Ready,
        Executed,
        Expired,
        Canceled
    }

    struct ProposalCore {
        // slot 0
        bytes32 configId;
        // slot 1
        uint48 voteStart;
        uint48 voteEnd;
        uint48 execStart;
        uint48 execEnd;
        bool executed;
        bool canceled;
        // slot 2
        address proposer;
    }

    struct GovernorConfig {
        address token;
        // uint256 proposalThreshold;
        // uint256 quorumVotes;
        uint128 maxPriorityFeePerGas;
        uint128 maxGasPrice;
        uint32 votingDelay;
        uint32 votingPeriod;
        uint32 executeDelay;
        uint32 executePeriod;
        bool sponsorPropose;
        bool sponsorExecute;
    }

    mapping(bytes32 proposalId => ProposalCore) private _proposals;
    mapping(bytes32 configId => GovernorConfig) private _configs;

    event ProposalCreated(
        bytes32 indexed proposalId,
        address indexed executor,
        bytes32 mode,
        bytes executionCalldata,
        string description
    );
    event ProposalExecuted(bytes32 indexed proposalId);

    /// @inheritdoc IERC7579Module
    function onInstall(bytes calldata /*data*/) public virtual {
        require(
            IERC7579ModuleConfig(msg.sender).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(this), new bytes(0)),
            "Module must be installed as executor"
        );

        if (!IERC7579ModuleConfig(msg.sender).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(this), new bytes(0))) {
            IERC7579Execution(msg.sender).executeFromExecutor(
                bytes32(0),
                abi.encodePacked(
                    msg.sender,
                    uint256(0),
                    abi.encodeCall(
                        IERC7579ModuleConfig.installModule,
                        (MODULE_TYPE_VALIDATOR, address(this), new bytes(0))
                    )
                )
            );
        }

        bytes memory selector = abi.encodePacked(this.handleProposal.selector);
        if (!IERC7579ModuleConfig(msg.sender).isModuleInstalled(MODULE_TYPE_FALLBACK, address(this), selector)) {
            IERC7579Execution(msg.sender).executeFromExecutor(
                bytes32(0),
                abi.encodePacked(
                    msg.sender,
                    uint256(0),
                    abi.encodeCall(IERC7579ModuleConfig.installModule, (MODULE_TYPE_FALLBACK, address(this), selector))
                )
            );
        }
    }

    /// @inheritdoc IERC7579Module
    function onUninstall(bytes calldata /*data*/) public virtual {}

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public view virtual returns (bool) {
        return
            moduleTypeId == MODULE_TYPE_VALIDATOR ||
            moduleTypeId == MODULE_TYPE_EXECUTOR ||
            moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /// @inheritdoc IERC7579Validator
    function validateUserOp(PackedUserOperation calldata userOp, bytes32) public virtual returns (uint256) {
        // Check userOp is an governanceAction call
        if (bytes4(userOp.callData) != this.handleProposal.selector) {
            return ERC4337Utils.SIG_VALIDATION_FAILED;
        }

        // Parse and check the mode used by the inner selfPropose call. Must be governor mode.
        bytes32 proposalMode = bytes32(userOp.callData[0x04:0x24]);
        (, , ModeSelector proposalModeSelector, ModePayload proposalModePayload) = ERC7579Utils.decodeMode(
            Mode.wrap(proposalMode)
        );
        if (proposalModeSelector != MODE_SELECTOR_GOVERNOR) {
            return ERC4337Utils.SIG_VALIDATION_FAILED;
        }

        // Rebuild configId used by the proposal
        bytes32 configId = hashConfigId(userOp.sender, proposalModePayload);
        GovernorConfig storage config = _configs[configId];

        bool usePaymaster = ERC4337Utils.paymaster(userOp) != address(0);

        // Check gas limits are in bound of what the config sponsors
        if (
            !usePaymaster &&
            (ERC4337Utils.maxPriorityFeePerGas(userOp) > config.maxPriorityFeePerGas ||
                ERC4337Utils.gasPrice(userOp) > config.maxGasPrice)
        ) {
            return ERC4337Utils.SIG_VALIDATION_FAILED;
        }

        // Rebuild proposalId of the proposal
        bytes32 proposalId = hashProposalId(
            configId,
            proposalMode,
            Calldata.decodeBytesAt(userOp.callData[0x04:], 0x20), // proposalCalldata
            keccak256(Calldata.decodeBytesAt(userOp.callData[0x04:], 0x40)) // hash proposalDescription
        );

        // Check proposal state and sponsorship
        ProposalState currentState = state(proposalId);
        return
            Math.ternary(
                (currentState == ProposalState.Unset && (usePaymaster || config.sponsorPropose)) ||
                    (currentState == ProposalState.Ready && (usePaymaster || config.sponsorExecute)),
                ERC4337Utils.SIG_VALIDATION_SUCCESS,
                ERC4337Utils.SIG_VALIDATION_FAILED
            );
    }

    /// @inheritdoc IERC7579Validator
    function isValidSignatureWithSender(address, bytes32, bytes calldata) public view virtual returns (bytes4) {
        return 0x00000000;
    }

    /// @inheritdoc IERC6372
    function clock() public view virtual returns (uint48);

    /// @inheritdoc IERC6372
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory);

    function hashConfigId(address executor, ModePayload payload) public pure returns (bytes32) {
        return keccak256(abi.encode(executor, payload));
    }

    function hashProposalId(
        bytes32 configId,
        bytes32 mode,
        bytes calldata executionCalldata,
        bytes32 descriptionHash
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(configId, mode, executionCalldata, descriptionHash));
    }

    // solhint-disable-next-line func-name-mixedcase
    function UNSAFE_setGovernorConfig(address executor, ModePayload payload, GovernorConfig calldata config) public {
        bytes32 configId = hashConfigId(executor, payload);
        _configs[configId] = config;
    }

    function getConfigDetails(bytes32 configId) public view returns (GovernorConfig memory) {
        return _configs[configId];
    }

    function getProposalDetails(bytes32 proposalId) public view returns (ProposalCore memory) {
        return _proposals[proposalId];
    }

    function state(bytes32 proposalId) public view virtual returns (ProposalState) {
        uint48 timepoint = clock();

        // batch sload (all values in the same slot)
        ProposalCore storage proposal = _proposals[proposalId];
        uint48 voteStart = proposal.voteStart;
        uint48 voteEnd = proposal.voteEnd;
        uint48 execStart = proposal.execStart;
        uint48 execEnd = proposal.execEnd;
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (voteStart == 0) {
            return ProposalState.Unset;
        } else if (proposalExecuted) {
            return ProposalState.Executed;
        } else if (proposalCanceled) {
            return ProposalState.Canceled;
        } else if (timepoint < voteStart) {
            return ProposalState.Pending;
        } else if (timepoint < voteEnd) {
            return ProposalState.Active;
        } else if (timepoint < execStart) {
            return ProposalState.Queued;
        } else if (timepoint < execEnd) {
            // TODO implement vote counting logic
            // return (_quorumReached(proposalId) && _voteSucceeded(proposalId))
            //     ? ProposalState.Ready
            //     : ProposalState.Defeated;
            return ProposalState.Ready;
        } else {
            return ProposalState.Expired;
        }
    }

    // NOTE: This is called through ERC7579 fallback
    function handleProposal(bytes32 mode, bytes calldata executionCalldata, string memory description) public virtual {
        address executor = msg.sender;

        (, , ModeSelector selector, ModePayload payload) = ERC7579Utils.decodeMode(Mode.wrap(mode));
        require(selector == MODE_SELECTOR_GOVERNOR, "Invalid selector"); // TODO error

        bytes32 configId = hashConfigId(executor, payload);
        bytes32 proposalId = hashProposalId(configId, mode, executionCalldata, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];

        ProposalState status = state(proposalId);
        if (status == ProposalState.Unset) {
            // block to avoid stack too deep
            {
                GovernorConfig storage config = _configs[configId];

                require(config.token != address(0)); // TODO: sanity check

                uint256 voteStart = uint256(clock()).saturatingAdd(config.votingDelay);
                uint256 voteEnd = voteStart.saturatingAdd(config.votingPeriod);
                uint256 execStart = voteEnd.saturatingAdd(config.executeDelay);
                uint256 execEnd = execStart.saturatingAdd(config.executePeriod);

                proposal.configId = configId;
                proposal.voteStart = uint48(voteStart.min(type(uint48).max));
                proposal.voteEnd = uint48(voteEnd.min(type(uint48).max));
                proposal.execStart = uint48(execStart.min(type(uint48).max));
                proposal.execEnd = uint48(execEnd.min(type(uint48).max));
                proposal.proposer = address(bytes20(msg.data[msg.data.length - 20:]));
            }

            emit ProposalCreated(proposalId, executor, mode, executionCalldata, description);
        } else if (status == ProposalState.Ready) {
            proposal.executed = true;
            IERC7579Execution(executor).executeFromExecutor(mode, executionCalldata);

            emit ProposalExecuted(proposalId);
        } else {
            revert(); // TODO error
        }
    }

    // TODO VOTING LOGIC
    // function vote(bytes32 proposalId, bool support) public {
    //     _validateStateBitmap(
    //         proposalId,
    //         _encodeStateBitmap(ProposalState.Active)
    //     );
    //     // Do stuff
    // }

    function cancel(bytes32 proposalId) public virtual {
        // TODO accesscontrol
        // ProposalCore storage proposal = _proposals[proposalId];
        // GovernorConfig storage config = _configs[proposal.configId];

        _cancel(proposalId);
    }

    function _cancel(bytes32 proposalId) internal virtual {
        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^
                _encodeStateBitmap(ProposalState.Canceled) ^
                _encodeStateBitmap(ProposalState.Expired) ^
                _encodeStateBitmap(ProposalState.Executed)
        );
        _proposals[proposalId].canceled = true;
        // TODO emit event
    }

    error GovernorUnexpectedProposalState(bytes32 proposalId, ProposalState current, bytes32 expectedStates);

    function _encodeStateBitmap(ProposalState proposalState) private pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    function _validateStateBitmap(bytes32 proposalId, bytes32 allowedStates) private view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        require(
            _encodeStateBitmap(currentState) & allowedStates != bytes32(0),
            GovernorUnexpectedProposalState(proposalId, currentState, allowedStates)
        );
        return currentState;
    }
}

import {Time} from "../../utils/types/Time.sol";

contract ERC7579GovernorModuleMock is ERC7579GovernorModule {
    /**
     * @dev The clock was incorrectly modified.
     */
    error ERC6372InconsistentClock();

    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based
     * checkpoints (and voting), in which case {CLOCK_MODE} should be overridden as well to match.
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @dev Machine-readable description of the clock as specified in ERC-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.timestamp()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=timestamp";
    }
}
