// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Math} from "../../../utils/math/Math.sol";
import {ERC20} from "../ERC20.sol";

abstract contract ERC20Compliance is ERC20 {
    /// @inheritdoc ERC20
    function _update(address from, address to, uint256 value) internal virtual override {
        require(from == address(0) || _checkRestrictionFrom(msg.sender, from, value, true));
        require(to == address(0) || _checkRestrictionTo(msg.sender, to, value, true));
        super._update(from, to, value);
    }

    /**
     * @dev Are transfer from `from` authorized? By default this return true (all transfers are authorized) but this
     * can be overridden to selectively authorize of restrict transfers.
     *
     * When overriding this function, there are two possible approach:
     *
     * * To add a restriction (condition that needs to be met otherwise the transfer should fail), it is recommended
     *   to call super with a modified "allowed" boolean:
     * ```
     * function _checkRestrictionFrom(address operator, address user, uint256 amount, bool allowed) internal view virtual override returns (bool) {
     *     return super._checkRestrictionFrom(operator, user, amount, <condition> && allowed);
     * }
     * ```
     *
     * * To bypass restrictions (for example to allow an admin to do transfers even when the restriction would
     *   otherwise prevent it), it is recommended to pass `allowed` unmodified, and to apply the logic on the returns
     *   value of the super call:
     * ```
     * function _checkRestrictionFrom(address operator, address user, uint256 amount, bool allowed) internal view virtual override returns (bool) {
     *     return <condition> || super._checkRestrictionFrom(operator, user, amount, allowed);
     * }
     * ```
     *
     * Following this good practices will help mitigate issues where the bollean logic would be affected by the inheritance ordering.
     */
    function _checkRestrictionFrom(
        address /*operator*/,
        address /*user*/,
        uint256 /*amount*/,
        bool allowed
    ) internal view virtual returns (bool) {
        return allowed;
    }

    /**
     * @dev Are transfer from `to` authorized? By default this return true (all transfers are authorized) but this
     * can be overridden to selectively authorize of restrict transfers.
     *
     * When overriding this function, there are two possible approach:
     *
     * * To add a restriction (condition that needs to be met otherwise the transfer should fail), it is recommended
     *   to call super with a modified "allowed" boolean:
     * ```
     * function _checkRestrictionTo(address operator, address user, uint256 amount, bool allowed) internal view virtual override returns (bool) {
     *     return super._checkRestrictionTo(operator, user, amount, <condition> && allowed);
     * }
     * ```
     *
     * * To bypass restrictions (for example to allow an admin to do transfers even when the restriction would
     *   otherwise prevent it), it is recommended to pass `allowed` unmodified, and to apply the logic on the returns
     *   value of the super call:
     * ```
     * function _checkRestrictionTo(address operator, address user, uint256 amount, bool allowed) internal view virtual override returns (bool) {
     *     return <condition> || super._checkRestrictionTo(operator, user, amount, allowed);
     * }
     * ```
     *
     * Following this good practices will help mitigate issues where the bollean logic would be affected by the inheritance ordering.
     */
    function _checkRestrictionTo(
        address /*operator*/,
        address /*user*/,
        uint256 /*amount*/,
        bool allowed
    ) internal view virtual returns (bool) {
        return allowed;
    }
}

abstract contract ERC20ComplianceFreezable is ERC20Compliance {
    mapping(address user => uint256) private _frozen;

    event FundsFrozen(address indexed operator, address indexed user, uint256 amount);

    function frozenOf(address user) public view virtual returns (uint256) {
        return _frozen[user];
    }

    function _freeze(address user, uint256 amount) internal virtual {
        _frozen[user] = amount;
        emit FundsFrozen(msg.sender, user, amount);
    }

    /// @inheritdoc ERC20Compliance
    function _checkRestrictionFrom(
        address operator,
        address user,
        uint256 amount,
        bool allowed
    ) internal view virtual override returns (bool) {
        return
            super._checkRestrictionFrom(
                operator,
                user,
                amount,
                Math.saturatingSub(balanceOf(user), frozenOf(user)) >= amount && allowed
            );
    }
}

abstract contract ERC20ComplianceRestricted is ERC20Compliance {
    /// @inheritdoc ERC20Compliance
    function _checkRestrictionFrom(
        address operator,
        address user,
        uint256 amount,
        bool allowed
    ) internal view virtual override returns (bool) {
        return super._checkRestrictionFrom(operator, user, amount, _isAuthorized(user) && allowed);
    }

    /// @inheritdoc ERC20Compliance
    function _checkRestrictionTo(
        address operator,
        address user,
        uint256 amount,
        bool allowed
    ) internal view virtual override returns (bool) {
        return super._checkRestrictionFrom(operator, user, amount, _isAuthorized(user) && allowed);
    }

    /**
     * @dev Returns whether `user` is authorized authorized to send or receive tokens.
     *
     * This can be used to implement both whitelist and blacklist. For example, if using AccessControl, this could be
     * implemented as
     * * `return hasRole(WHITELIST_ROLE, user)` to implement a whitelist.
     * * `return !hasRole(BLACKLIST_ROLE, user)` to implement a blacklist (this would require overriding `renounceRole`
     *   to prevent blacklisted users from renouncing that role).
     *
     * This could also be implemented using AccessManager with a "virtual selector" used to represent the right to
     * perform transfers: `return authority.canCall(user, address(this), IERC20.transfer.selector)
     */
    function _isAuthorized(address /*user*/) internal view virtual returns (bool);
}

abstract contract ERC20ComplianceSeizable is ERC20Compliance {
    function seize(address from, address to, uint256 amount) public virtual {
        require(_canSeize(msg.sender)); // check caller
        require(from != address(0)); // cannot mint as part of the seize process
        _update(from, to, amount);
    }

    /// @inheritdoc ERC20Compliance
    function _checkRestrictionFrom(
        address operator,
        address user,
        uint256 amount,
        bool allowed
    ) internal view virtual override returns (bool) {
        return _canSeize(operator) || super._checkRestrictionFrom(operator, user, amount, allowed);
    }

    /// @inheritdoc ERC20Compliance
    function _checkRestrictionTo(
        address operator,
        address user,
        uint256 amount,
        bool allowed
    ) internal view virtual override returns (bool) {
        return _canSeize(operator) || super._checkRestrictionFrom(operator, user, amount, allowed);
    }

    /**
     * @dev Returns whether `operator` is authorized to seize tokens.
     */
    function _canSeize(address /*operator*/) internal view virtual returns (bool);
}
