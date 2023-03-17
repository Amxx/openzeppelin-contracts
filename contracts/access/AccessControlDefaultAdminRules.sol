// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (access/AccessControlDefaultAdminRules.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IAccessControlDefaultAdminRules.sol";
import "../utils/math/SafeCast.sol";
import "../interfaces/IERC5313.sol";

/**
 * @dev Extension of {AccessControl} that allows specifying special rules to manage
 * the `DEFAULT_ADMIN_ROLE` holder, which is a sensitive role with special permissions
 * over other roles that may potentially have privileged rights in the system.
 *
 * If a specific role doesn't have an admin role assigned, the holder of the
 * `DEFAULT_ADMIN_ROLE` will have the ability to grant it and revoke it.
 *
 * This contract implements the following risk mitigations on top of {AccessControl}:
 *
 * * Only one account holds the `DEFAULT_ADMIN_ROLE` since deployment until it's potentially renounced.
 * * Enforces a 2-step process to transfer the `DEFAULT_ADMIN_ROLE` to another account.
 * * Enforces a configurable delay between the two steps, with the ability to cancel before the transfer is accepted.
 * * It is not possible to use another role to manage the `DEFAULT_ADMIN_ROLE`.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyToken is AccessControlDefaultAdminRules {
 *   constructor() AccessControlDefaultAdminRules(
 *     3 days,
 *     msg.sender // Explicit initial `DEFAULT_ADMIN_ROLE` holder
 *    ) {}
 * }
 * ```
 *
 * _Available since v4.9._
 */
abstract contract AccessControlDefaultAdminRules is IAccessControlDefaultAdminRules, IERC5313, AccessControl {
    // pending delay pair read/written together frequently
    uint48 private _pendingDelay;
    uint48 private _pendingDelaySchedule; // 0 == unset

    address private _currentDefaultAdmin;
    uint48 private _currentDelay;

    // pending admin pair read/written together frequently
    address private _pendingDefaultAdmin;
    uint48 private _pendingDefaultAdminSchedule; // 0 == unset

    /**
     * @dev Sets the initial values for {defaultAdminDelay} in seconds and {defaultAdmin} address.
     */
    constructor(uint48 initialDefaultAdminDelay, address initialDefaultAdmin) {
        _currentDelay = initialDefaultAdminDelay;
        _grantRole(DEFAULT_ADMIN_ROLE, initialDefaultAdmin);
    }

    /**
     * @dev See {IERC5313-owner}.
     */
    function owner() public view virtual returns (address) {
        return defaultAdmin();
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function defaultAdminDelay() public view virtual returns (uint48) {
        uint48 schedule = _pendingDelaySchedule;
        return (_isSet(schedule) && _hasPassed(schedule)) ? _pendingDelay : _currentDelay;
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function pendingDefaultAdminDelay() public view virtual returns (uint48 newDelay, uint48 schedule) {
        schedule = _pendingDelaySchedule;
        return (_isSet(schedule) && !_hasPassed(schedule)) ? (_pendingDelay, schedule) : (0, 0);
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function defaultAdmin() public view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function pendingDefaultAdmin() public view virtual returns (address newAdmin, uint48 schedule) {
        return (_pendingDefaultAdmin, _pendingDefaultAdminSchedule);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlDefaultAdminRules).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function defaultAdminDelayIncreaseWait() public view virtual returns (uint48) {
        return 5 days;
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function changeDefaultAdminDelay(uint48 newDefaultAdminDelay) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _changeDefaultAdminDelay(newDefaultAdminDelay);
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function rollbackDefaultAdminDelay() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _resetDefaultAdminDelayChange();
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function beginDefaultAdminTransfer(address newAdmin) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _beginDefaultAdminTransfer(newAdmin);
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function acceptDefaultAdminTransfer() public virtual {
        (address newDefaultAdmin, ) = pendingDefaultAdmin();
        require(_msgSender() == newDefaultAdmin, "AccessControl: pending admin must accept");
        _acceptDefaultAdminTransfer();
    }

    /**
     * @inheritdoc IAccessControlDefaultAdminRules
     */
    function cancelDefaultAdminTransfer() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _resetDefaultAdminTransfer();
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * For `DEFAULT_ADMIN_ROLE`, only allows renouncing in two steps, so it's required
     * that the {defaultAdminTransferSchedule} has passed and the pending default admin is the zero address.
     * After its execution, it will not be possible to call `onlyRole(DEFAULT_ADMIN_ROLE)`
     * functions.
     *
     * For other roles, see {AccessControl-renounceRole}.
     *
     * NOTE: Renouncing `DEFAULT_ADMIN_ROLE` will leave the contract without a defaultAdmin,
     * thereby disabling any functionality that is only available to the default admin, and the
     * possibility of reassigning a non-administrated role.
     */
    function renounceRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
        if (role == DEFAULT_ADMIN_ROLE) {
            (address newDefaultAdmin, uint48 schedule) = pendingDefaultAdmin();
            require(
                newDefaultAdmin == address(0) && _isSet(schedule) && _hasPassed(schedule),
                "AccessControl: only can renounce in two delayed steps"
            );
        }
        super.renounceRole(role, account);
    }

    /**
     * @dev See {AccessControl-grantRole}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function grantRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't directly grant default admin role");
        super.grantRole(role, account);
    }

    /**
     * @dev See {AccessControl-revokeRole}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function revokeRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't directly revoke default admin role");
        super.revokeRole(role, account);
    }

    /**
     * @dev See {AccessControl-_setRoleAdmin}. Reverts for `DEFAULT_ADMIN_ROLE`.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual override {
        require(role != DEFAULT_ADMIN_ROLE, "AccessControl: can't violate default admin rules");
        super._setRoleAdmin(role, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * For `DEFAULT_ADMIN_ROLE`, it only allows granting if there isn't already a role's holder
     * or if the role has been previously renounced.
     *
     * For other roles, see {AccessControl-renounceRole}.
     *
     * NOTE: Exposing this function through another mechanism may make the
     * `DEFAULT_ADMIN_ROLE` assignable again. Make sure to guarantee this is
     * the expected behavior in your implementation.
     */
    function _grantRole(bytes32 role, address account) internal virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            require(defaultAdmin() == address(0), "AccessControl: default admin already granted");
            _currentDefaultAdmin = account;
        }
        super._grantRole(role, account);
    }

    /**
     * @dev See {changeDefaultAdminDelay}.
     *
     * Internal function without access restriction.
     */
    function _changeDefaultAdminDelay(uint48 newDefaultAdminDelay) internal virtual {
        uint48 delaySchedule = _pendingDelaySchedule;
        require(!_isSet(delaySchedule) || !_hasPassed(delaySchedule), "AccessControl: can't change virtual delay");

        (, uint48 transferSchedule) = pendingDefaultAdmin();
        require(!_isSet(transferSchedule), "AccessControl: default admin transfer pending");

        uint48 currentDelay = defaultAdminDelay();

        // Schedules defaultAdminDelayIncreaseWait() if the delay is increased, this is done so the user has time enough to fix an accidentally high new delay set.
        // If the delay is reduced, wait the difference between current and new delay to guarantee the delay change schedule + a default admin change
        // is effectively the current delay. For example, if delay is reduced from 10 days to 3 days, it's needed to wait 7 days
        // before starting the new 3 days delayed transfer summing up to 10 days, which is the current delay.
        uint48 changeDelay = newDefaultAdminDelay > currentDelay
            ? defaultAdminDelayIncreaseWait()
            : currentDelay - newDefaultAdminDelay;

        _pendingDelaySchedule = SafeCast.toUint48(block.timestamp) + changeDelay;
        _pendingDelay = newDefaultAdminDelay;

        uint48 newDelay;
        (newDelay, delaySchedule) = pendingDefaultAdminDelay();
        emit DefaultAdminDelayChangeScheduled(newDelay, delaySchedule);
    }

    /**
     * @dev See {beginDefaultAdminTransfer}.
     *
     * Internal function without access restriction.
     */
    function _beginDefaultAdminTransfer(address newAdmin) internal virtual {
        (, uint48 delaySchedule) = pendingDefaultAdminDelay();
        if (_isSet(delaySchedule)) _resetDefaultAdminDelayChange();

        _pendingDefaultAdminSchedule = SafeCast.toUint48(block.timestamp) + defaultAdminDelay();
        _pendingDefaultAdmin = newAdmin;

        (address newDefaultAdmin, uint48 transferSchedule) = pendingDefaultAdmin();
        emit DefaultAdminTransferScheduled(newDefaultAdmin, transferSchedule);
    }

    /**
     * @dev See {acceptDefaultAdminTransfer}.
     *
     * Internal function without access restriction.
     */
    function _acceptDefaultAdminTransfer() internal virtual {
        (address newDefaultAdmin, uint48 schedule) = pendingDefaultAdmin();
        require(_isSet(schedule) && _hasPassed(schedule), "AccessControl: transfer delay not passed");
        _revokeRole(DEFAULT_ADMIN_ROLE, defaultAdmin());
        _grantRole(DEFAULT_ADMIN_ROLE, newDefaultAdmin);
        _resetDefaultAdminTransfer();
    }

    /**
     * @dev See {AccessControl-_revokeRole}.
     */
    function _revokeRole(bytes32 role, address account) internal virtual override {
        if (role == DEFAULT_ADMIN_ROLE) {
            delete _currentDefaultAdmin;
        }
        super._revokeRole(role, account);
    }

    /**
     * @dev Sets a pending delay into effect if its delay has passed
     */
    function _materializeDefaultAdminTransfer() private {
        uint48 delaySchedule = _pendingDelaySchedule;
        if (_isSet(delaySchedule) && _hasPassed(delaySchedule)) _currentDelay = _pendingDelay;
    }

    /**
     * @dev Resets the pending default admin and delayed until.
     */
    function _resetDefaultAdminDelayChange() private {
        _materializeDefaultAdminTransfer();

        delete _pendingDelay;
        delete _pendingDelaySchedule;
    }

    /**
     * @dev Resets the pending default admin and delayed until.
     */
    function _resetDefaultAdminTransfer() private {
        delete _pendingDefaultAdmin;
        delete _pendingDefaultAdminSchedule;
    }

    function _hasPassed(uint48 schedule) private view returns (bool) {
        return schedule < block.timestamp;
    }

    function _isSet(uint48 schedule) private pure returns (bool) {
        return schedule != 0;
    }
}
