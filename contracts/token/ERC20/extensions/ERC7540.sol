// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IERC165} from "../../../interfaces/IERC165.sol";
import {IERC20, ERC20} from "../ERC20.sol";
import {IERC4626, ERC4626} from "./ERC4626.sol";
import {ERC7540Deposit} from "./ERC7540Deposit.sol";
import {ERC7540Redeem} from "./ERC7540Redeem.sol";
import {ERC7540Operator} from "./ERC7540Operator.sol";

/**
 * @dev Implementation of the ERC-7540 "Asynchronous ERC-4626 Tokenized Vaults" as defined in
 * https://eips.ethereum.org/EIPS/eip-7540[ERC-7540].
 *
 * This extension adds support for asynchronous deposit and redemption flows to ERC-4626 vaults.
 * Users can request deposits or redemptions which enter a Pending state, transition to a Claimable state
 * when processed by the vault, and are finally Claimed using the standard ERC-4626 deposit/mint/withdraw/redeem methods.
 *
 * This contract combines {ERC7540Deposit} and {ERC7540Redeem} to provide a fully asynchronous vault.
 * For vaults that only require asynchronous deposits or redemptions, use the individual extensions instead.
 *
 * CAUTION: ERC-7540 introduces operator permissions that allow operators to manage requests on behalf of controllers.
 * Users should be cautious when approving operators as they gain significant control over both assets and shares.
 *
 * NOTE: For all functions that override either {ERC7540Deposit} or {ERC7540Redeem} and {ERC4626}, the ERC-7540 version
 * of the function is the one that is called by super. This is guaranteed by the fact that {ERC7540Deposit} and {ERC7540Redeem}
 * both inherit from {ERC4626} through {ERC7540Operator}.
 */
abstract contract ERC7540 is ERC7540Redeem, ERC7540Deposit {
    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC7540Redeem, ERC7540Deposit) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc ERC7540Redeem
    function totalSupply() public view virtual override(ERC7540Redeem, IERC20, ERC20) returns (uint256) {
        return super.totalSupply();
    }

    /// @inheritdoc ERC7540Deposit
    function totalAssets() public view virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.totalAssets();
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.previewDeposit(assets); // Must revert
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) public view virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.previewMint(shares); // Must revert
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) public view virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.previewWithdraw(assets); // Must revert
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) public view virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.previewRedeem(shares); // Must revert
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address controller) public view virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.maxDeposit(controller);
    }

    /// @inheritdoc IERC4626
    function maxMint(address controller) public view virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.maxMint(controller);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address controller) public view virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.maxWithdraw(controller);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address controller) public view virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.maxRedeem(controller);
    }

    /// @inheritdoc IERC4626
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public virtual override(ERC7540Deposit, ERC4626) returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IERC4626
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override(ERC7540Redeem, ERC4626) returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    function _deposit(
        address controller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540Deposit, ERC4626) {
        super._deposit(controller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address controller,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540Redeem, ERC4626) {
        super._withdraw(caller, receiver, controller, assets, shares);
    }
}
