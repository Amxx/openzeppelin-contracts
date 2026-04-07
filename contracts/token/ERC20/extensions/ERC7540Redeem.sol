// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IERC20} from "../../../interfaces/IERC20.sol";
import {IERC4626} from "../../../interfaces/IERC4626.sol";
import {IERC7540Redeem} from "../../../interfaces/IERC7540.sol";
import {ERC165} from "../../../utils/introspection/ERC165.sol";
import {Math} from "../../../utils/math/Math.sol";
import {ERC20} from "../ERC20.sol";
import {ERC7540Operator} from "./ERC7540Operator.sol";

/**
 * @dev Extension of {ERC7540Operator} that implements the asynchronous redemption flow of ERC-7540.
 *
 * This contract provides the mechanisms for users to request redemptions of shares from the vault.
 * Requests go through three states:
 *
 * 1. Pending: Shares are transferred to (or burned by) the vault and recorded in `pendingRedeemRequest`
 * 2. Claimable: The vault processes the request and makes it claimable via `claimableRedeemRequest`
 * 3. Claimed: Users call the standard `withdraw` or `redeem` functions to receive their assets
 *
 * The exchange rate between shares and assets is determined when the request becomes Claimable,
 * not when the request is initially made. This allows vaults to handle redemptions that cannot be
 * processed immediately, such as those requiring unstaking periods or asset liquidation.
 *
 * Vault implementations must call {_fulfillRedeem} to transition requests from Pending to Claimable.
 *
 * NOTE: By default, shares are held in the vault during Pending state and burned at fulfillment,
 * allowing them to continue earning yield. Vaults can override {_lockSharesIn} and {_completeSharesIn}
 * to burn shares immediately at request time and do nothing (respectively), but must also override
 * {_fulfillRedeem} to use a snapshotted exchange rate to ensure correct asset calculations.
 */
abstract contract ERC7540Redeem is ERC165, ERC7540Operator, IERC7540Redeem {
    /// @dev Emitted when a redeem request transitions from Pending to Claimable.
    event RedeemClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);

    /// @dev The preview is not available for redeem.
    error ERC7540RedeemPreviewNotAvailable();

    /// @dev The amount of shares requested is greater than the amount of shares pending.
    error ERC7540RedeemInsufficientPendingShares(uint256 shares, uint256 pendingShares);

    /**
     * @dev Struct containing the shares and corresponding assets for a claimable redeem request.
     * When a request becomes claimable via {_fulfillRedeem}, the exchange rate is locked in this struct.
     */
    struct PendingRedeem {
        uint256 pendingShares;
        uint256 claimableShares;
        uint256 claimableAssets;
    }

    mapping(address controller => PendingRedeem) private _redeems;
    uint256 private _totalPendingRedeemShares;

    /****************************************************************************************************************
     *                          Generic ERC-7540 behavior, applies to all implementations                           *
     ****************************************************************************************************************/
    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, ERC7540Operator) returns (bool) {
        return interfaceId == type(IERC7540Redeem).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 /* shares */) public view virtual override returns (uint256) {
        revert ERC7540RedeemPreviewNotAvailable();
    }

    /// @dev See {IERC4626-previewWithdraw}.
    function previewWithdraw(uint256 /* assets */) public view virtual override returns (uint256) {
        revert ERC7540RedeemPreviewNotAvailable();
    }

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 shares, address controller, address owner) public virtual returns (uint256) {
        address sender = _msgSender();
        if (owner != sender && !isOperator(owner, sender)) {
            _spendAllowance(owner, sender, shares);
        }
        _burn(owner, shares);

        return _requestRedeem(shares, controller, owner);
    }

    /**
     * @dev Allows claiming assets from a Claimable redeem request.
     *
     * See {IERC7540Redeem-withdraw}.
     *
     * NOTE: According to ERC-7540, the `controller` parameter replaces the traditional `owner` parameter
     * from ERC-4626, and the controller MUST be `msg.sender` or have approved `msg.sender` as an operator.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override onlyOperatorOrController(controller, _msgSender()) returns (uint256) {
        uint256 maxAssets = maxWithdraw(controller);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(controller, assets, maxAssets);
        }

        // *preview* and execute
        uint256 shares = Math.mulDiv(assets, maxRedeem(controller), maxWithdraw(controller), Math.Rounding.Ceil);
        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return shares;
    }

    /**
     * @dev Allows claiming assets from a Claimable redeem request by specifying the exact amount of shares.
     *
     * See {IERC7540Redeem-redeem}.
     *
     * NOTE: According to ERC-7540, the `controller` parameter replaces the traditional `owner` parameter
     * from ERC-4626, and the controller MUST be `msg.sender` or have approved `msg.sender` as an operator.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override onlyOperatorOrController(controller, _msgSender()) returns (uint256) {
        uint256 maxShares = maxRedeem(controller);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(controller, shares, maxShares);
        }

        // *preview* and execute
        uint256 assets = Math.mulDiv(shares, maxWithdraw(controller), maxRedeem(controller), Math.Rounding.Floor);
        _withdraw(_msgSender(), receiver, controller, assets, shares);

        return assets;
    }

    /****************************************************************************************************************
     *                              Behavior specific to this ERC-7540 implementation                               *
     *                                                                                                              *
     * There should be overridden to modify the behavior of the vault, for example to introduce different requestId *
     * to enforce delays on the asynchronous operations or to use a different storage for tracking.                 *
     ****************************************************************************************************************/

    /**
     * @dev See {ERC4626-totalSupply}.
     *
     * Total shares pending redemption must be added from the reported total supply
     * otherwise pending assets would be treated as yield for outstanding shares.
     */
    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return super.totalSupply() + totalPendingRedeemShares();
    }

    /// @dev Returns the total amount of shares currently pending in redeem requests.
    function totalPendingRedeemShares() public view virtual returns (uint256) {
        return _totalPendingRedeemShares;
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256 /* requestId */, address controller) public view virtual returns (uint256) {
        return _redeems[controller].pendingShares;
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256 /* requestId */, address controller) public view virtual returns (uint256) {
        return _redeems[controller].claimableShares;
    }

    /// TODO: non standard
    function claimableRedeemRequestAssets(
        uint256 /* requestId */,
        address controller
    ) public view virtual returns (uint256) {
        return _redeems[controller].claimableAssets;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address controller) public view virtual override returns (uint256) {
        return _redeems[controller].claimableAssets;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address controller) public view virtual override returns (uint256) {
        return _redeems[controller].claimableShares;
    }

    /**
     * @dev Registers a new redeem request in Pending state by recording the requested assets and updating the pending accounting.
     *
     * Note: `shares` have already been burned before calling this function.
     */
    function _requestRedeem(uint256 shares, address controller, address owner) internal virtual returns (uint256) {
        // track pending redeem
        _redeems[controller].pendingShares += shares;
        _totalPendingRedeemShares += shares;

        emit RedeemRequest(controller, owner, 0, _msgSender(), shares);
        return 0;
    }

    /**
     * @dev Fulfills a pending redeem request by transitioning it from Pending to Claimable state.
     *
     * This internal function should be called by the vault implementation when it's ready to process
     * a redemption request. It converts the specified amount of pending shares to assets at the current
     * exchange rate and updates the claimable balance for the controller.
     *
     * The corresponding assets are held by the vault and made available for the controller to claim
     * via {withdraw} or {redeem}.
     *
     * NOTE: Claimable redeem assets are NOT subtracted from {totalAssets}. Since fulfilled shares are
     * burned while assets remain in the vault, the assets-per-share rate naturally increases after each
     * fulfillment. Vault operators batch-fulfilling multiple requests should account for this shifting
     * rate, e.g. by overriding {_redeemPrice} to use a snapshotted exchange rate.
     *
     * Requirements:
     *
     * * `shares` must not exceed the pending redeem amount for the controller
     */
    function _fulfillRedeem(uint256 shares, uint256 assets, address controller) internal virtual {
        uint256 pendingShares = pendingRedeemRequest(0, controller);
        require(shares <= pendingShares, ERC7540RedeemInsufficientPendingShares(shares, pendingShares));

        _redeems[controller].pendingShares -= shares;
        _redeems[controller].claimableShares += shares;
        _redeems[controller].claimableAssets += assets;

        emit RedeemClaimable(controller, 0, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address controller,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        _totalPendingRedeemShares = Math.saturatingSub(_totalPendingRedeemShares, shares);
        _redeems[controller].claimableShares = Math.saturatingSub(_redeems[controller].claimableShares, shares);
        _redeems[controller].claimableAssets = Math.saturatingSub(_redeems[controller].claimableAssets, assets);

        // Do not burn shares during withdraw --- they were already burned at request time
        _transferOut(receiver, assets);

        emit Withdraw(caller, receiver, controller, assets, shares);
    }
}
