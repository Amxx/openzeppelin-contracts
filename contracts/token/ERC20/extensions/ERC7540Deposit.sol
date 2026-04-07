// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IERC4626} from "../../../interfaces/IERC4626.sol";
import {IERC7540Deposit} from "../../../interfaces/IERC7540.sol";
import {ERC165} from "../../../utils/introspection/ERC165.sol";
import {Math} from "../../../utils/math/Math.sol";
import {ERC7540Operator} from "./ERC7540Operator.sol";

/**
 * @dev Extension of {ERC7540Operator} that implements the asynchronous deposit flow of ERC-7540.
 *
 * This contract provides the mechanisms for users to request deposits of assets into the vault.
 * Requests go through three states:
 *
 * 1. Pending: Assets are transferred to the vault and recorded in `pendingDepositRequest`
 * 2. Claimable: The vault processes the request and makes it claimable via `claimableDepositRequest`
 * 3. Claimed: Users call the standard `deposit` or `mint` functions to receive their shares
 *
 * The exchange rate between assets and shares is determined when the request becomes Claimable,
 * not when the request is initially made. This allows vaults to handle deposits that cannot be
 * processed immediately, such as those requiring off-chain processes or cross-chain operations.
 *
 * Vault implementations must call {_fulfillDeposit} to transition requests from Pending to Claimable.
 */
abstract contract ERC7540Deposit is ERC165, ERC7540Operator, IERC7540Deposit {
    /// @dev Emitted when a deposit request transitions from Pending to Claimable.
    event DepositClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);

    /// @dev The preview is not available for deposit.
    error ERC7540DepositPreviewNotAvailable();

    /// @dev The amount of assets requested is greater than the amount of assets pending.
    error ERC7540DepositInsufficientPendingAssets(uint256 assets, uint256 pendingAssets);

    /**
     * @dev Struct containing the assets and corresponding shares for a claimable deposit request.
     * When a request becomes claimable via {_fulfillDeposit}, the exchange rate is locked in this struct.
     */
    struct PendingDeposit {
        uint256 pendingAssets;
        uint256 claimableAssets;
        uint256 claimableShares;
    }

    mapping(address controller => PendingDeposit) private _deposits;
    uint256 private _totalPendingDepositAssets;

    /****************************************************************************************************************
     *                          Generic ERC-7540 behavior, applies to all implementations                           *
     ****************************************************************************************************************/
    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, ERC7540Operator) returns (bool) {
        return interfaceId == type(IERC7540Deposit).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 /* assets */) public view virtual override returns (uint256) {
        revert ERC7540DepositPreviewNotAvailable();
    }

    /// @dev See {IERC4626-previewMint}.
    function previewMint(uint256 /* shares */) public view virtual override returns (uint256) {
        revert ERC7540DepositPreviewNotAvailable();
    }

    /**
     * @dev See {IERC7540Deposit-requestDeposit}.
     *
     * NOTE: Pending accounting is updated before {_transferIn} to follow Checks-Effects-Interactions.
     * Assets with transfer hooks (e.g. ERC-777) may observe {totalAssets} temporarily understated
     * during the transfer, since `_totalPendingDepositAssets` is already incremented while the
     * token balance has not yet increased.
     */
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public virtual onlyOperatorOrController(owner, _msgSender()) returns (uint256) {
        uint256 requestId = _requestDeposit(assets, controller, owner);

        // Must revert with ERC20InsufficientBalance or equivalent error if there's not enough balance.
        _transferIn(owner, assets);

        return requestId;
    }

    /**
     * @dev Allows claiming shares from a Claimable deposit request.
     * Calls the three-argument version with `receiver` as the `controller`. Complies with ERC-4626.
     *
     * See {IERC7540Deposit-deposit}.
     *
     * NOTE: this function should be overridden. To modify the behavior, override {IERC7540Deposit-deposit} instead.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        return deposit(assets, receiver, _msgSender());
    }

    /// @inheritdoc IERC7540Deposit
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual onlyOperatorOrController(controller, _msgSender()) returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        // *preview* and execute
        uint256 shares = Math.mulDiv(assets, maxMint(controller), maxDeposit(controller), Math.Rounding.Floor);
        _deposit(controller, receiver, assets, shares);

        return shares;
    }

    /**
     * @dev Allows claiming shares from a Claimable deposit request by specifying the exact amount of shares.
     * Calls the three-argument version with `receiver` as the `controller`. Complies with ERC-4626.
     *
     * See {IERC7540Deposit-mint}.
     *
     * NOTE: this function should be overridden. To modify the behavior, override {IERC7540Deposit-deposit} instead.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        return mint(shares, receiver, _msgSender());
    }

    /// @inheritdoc IERC7540Deposit
    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual onlyOperatorOrController(controller, _msgSender()) returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        // *preview* and execute
        uint256 assets = Math.mulDiv(shares, maxDeposit(controller), maxMint(controller), Math.Rounding.Ceil);
        _deposit(controller, receiver, assets, shares);

        return assets;
    }

    /****************************************************************************************************************
     *                              Behavior specific to this ERC-7540 implementation                               *
     *                                                                                                              *
     * There should be overridden to modify the behavior of the vault, for example to introduce different requestId *
     * to enforce delays on the asynchronous operations or to use a different storage for tracking.                 *
     ****************************************************************************************************************/

    /**
     * @dev See {ERC4626-totalAssets}.
     *
     * Total assets pending redemption must be removed from the reported total assets
     * otherwise pending assets would be treated as yield for outstanding shares.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() - totalPendingDepositAssets();
    }

    /// @dev Returns the total amount of assets currently pending in deposit requests.
    function totalPendingDepositAssets() public view virtual returns (uint256) {
        return _totalPendingDepositAssets;
    }

    /// @inheritdoc IERC7540Deposit
    function pendingDepositRequest(uint256 /* requestId */, address controller) public view virtual returns (uint256) {
        return _deposits[controller].pendingAssets;
    }

    /// @inheritdoc IERC7540Deposit
    function claimableDepositRequest(
        uint256 /* requestId */,
        address controller
    ) public view virtual returns (uint256) {
        return _deposits[controller].claimableAssets;
    }

    /// TODO: non standard.
    function claimableDepositRequestShares(
        uint256 /* requestId */,
        address controller
    ) public view virtual returns (uint256) {
        return _deposits[controller].claimableShares;
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address controller) public view virtual override returns (uint256) {
        return _deposits[controller].claimableAssets;
    }

    /// @inheritdoc IERC4626
    function maxMint(address controller) public view virtual override returns (uint256) {
        return _deposits[controller].claimableShares;
    }

    /**
     * @dev Registers a new deposit request in Pending state by recording the requested assets and updating the pending accounting.
     *
     * Note: `assets` have already been transferred to the vault before calling this function.
     */
    function _requestDeposit(uint256 assets, address controller, address owner) internal virtual returns (uint256) {
        // track pending deposits
        _deposits[controller].pendingAssets += assets;
        _totalPendingDepositAssets += assets;

        emit DepositRequest(controller, owner, 0, _msgSender(), assets);
        return 0;
    }

    /**
     * @dev Fulfills a pending deposit request by transitioning it from Pending to Claimable state.
     *
     * This internal function should be called by the vault implementation when it's ready to process a deposit
     * request. Arguments provide the exchange rate at which the operation is fulfilled, which may be different from
     * the overall vault exchange rate. As documented in ERC-7540, it may also be different from the exchange rate at
     * the time of the request.
     *
     * Requirements:
     *
     * * `assets` must not exceed the pending deposit amount for the controller
     */
    function _fulfillDeposit(uint256 assets, uint256 shares, address controller) internal virtual {
        uint256 pendingAssets = pendingDepositRequest(0, controller);
        require(assets <= pendingAssets, ERC7540DepositInsufficientPendingAssets(assets, pendingAssets));

        _deposits[controller].pendingAssets -= assets;
        _deposits[controller].claimableAssets += assets;
        _deposits[controller].claimableShares += shares;

        emit DepositClaimable(controller, 0, assets, shares);
    }

    function _deposit(address controller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _totalPendingDepositAssets = Math.saturatingSub(_totalPendingDepositAssets, assets);
        _deposits[controller].claimableAssets = Math.saturatingSub(_deposits[controller].claimableAssets, assets);
        _deposits[controller].claimableShares = Math.saturatingSub(_deposits[controller].claimableShares, shares);

        // Do not transferIn assets during deposit --- they were already transferred in at request time
        _mint(receiver, shares);

        emit Deposit(controller, receiver, assets, shares);
    }
}
