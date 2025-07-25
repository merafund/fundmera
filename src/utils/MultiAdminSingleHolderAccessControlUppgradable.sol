// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund

pragma solidity 0.8.29;

import {IMultiAdminSingleHolderAccessControl} from "../interfaces/IMultiAdminSingleHolderAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

abstract contract MultiAdminSingleHolderAccessControlUppgradable is
    Initializable,
    ContextUpgradeable,
    IMultiAdminSingleHolderAccessControl,
    ERC165Upgradeable
{
    struct RoleData {
        address roleHolder; // Single holder - only one address can hold the role
        mapping(bytes32 => bool) adminRole; // Multiple admin roles can control this role
    }

    /// @custom:storage-location erc7201:openzeppelin.storage.AccessControl
    struct AccessControlStorage {
        mapping(bytes32 role => RoleData) _roles;
        mapping(address account => bytes32[] roles) _accountRoles;
    }

    bytes32 private constant AccessControlStorageLocation =
        0xdbadc8f809858f78abc0d8ad2d539141b11227e3823afc1897c7978d63569f00; //keccak256(abi.encode(uint256(keccak256("merafund.storage.MultiAdminSingleHolderAccessControlUppgradable")) - 1)) & ~bytes32(uint256(0xff));

    function _getAccessControlStorage() private pure returns (AccessControlStorage storage $) {
        assembly {
            $.slot := AccessControlStorageLocation
        }
    }

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    function __AccessControl_init() internal onlyInitializing {}

    function __AccessControl_init_unchained() internal onlyInitializing {}
    /**
     * @dev See {IERC165-supportsInterface}.
     */

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IMultiAdminSingleHolderAccessControl).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        AccessControlStorage storage $ = _getAccessControlStorage();
        return $._roles[role].roleHolder == account;
    }

    /**
     * @dev Returns the address that currently holds the specified role.
     * Returns address(0) if no one holds the role.
     */
    function getRoleHolder(bytes32 role) public view virtual returns (address) {
        AccessControlStorage storage $ = _getAccessControlStorage();
        return $._roles[role].roleHolder;
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
     * is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    /**
     * @dev Returns true if adminRole can control role
     */
    function isRoleAdmin(bytes32 role, bytes32 adminRole) public view virtual returns (bool) {
        AccessControlStorage storage $ = _getAccessControlStorage();
        return $._roles[role].adminRole[adminRole];
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If another account already has the role, it will be revoked from them first.
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have an admin role that can control ``role``.
     *
     * May emit {RoleRevoked} and {RoleGranted} events.
     */
    function grantRole(bytes32 role, address account) public virtual {
        _checkRoleAdmin(role);
        _grantRole(role, account);
    }

    /**
     * @dev Internal function to check if caller has admin rights for the role
     */
    function _checkRoleAdmin(bytes32 role) internal view virtual {
        AccessControlStorage storage $ = _getAccessControlStorage();
        bytes32[] memory userRoles = $._accountRoles[_msgSender()];
        // Check if caller has DEFAULT_ADMIN_ROLE and it's set as admin for this role
        for (uint256 i = 0; i < userRoles.length; i++) {
            if ($._roles[role].adminRole[userRoles[i]]) {
                return;
            }
        }

        // Check all possible admin roles
        // Note: In practice, you'd need to track which roles exist to iterate them
        // For now, we assume DEFAULT_ADMIN_ROLE is the primary admin mechanism
        revert AccessControlUnauthorizedAccount(_msgSender(), 0x00);
    }

    /**
     * @dev Sets `adminRole` as one of ``role``'s admin roles.
     *
     * Emits a {RoleAdminAdded} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        AccessControlStorage storage $ = _getAccessControlStorage();
        $._roles[role].adminRole[adminRole] = true;
        emit RoleAdminAdded(role, adminRole);
    }

    /**
     * @dev Removes `adminRole` from ``role``'s admin roles.
     *
     * Emits a {RoleAdminRemoved} event.
     */
    function _removeRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        AccessControlStorage storage $ = _getAccessControlStorage();
        $._roles[role].adminRole[adminRole] = false;
        emit RoleAdminRemoved(role, adminRole);
    }

    /**
     * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
     *
     * Internal function without access restriction.
     * If another account holds the role, it will be revoked first.
     *
     * May emit {RoleRevoked} and {RoleGranted} events.
     */
    function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
        AccessControlStorage storage $ = _getAccessControlStorage();
        address currentHolder = $._roles[role].roleHolder;

        // If role is already held by the same account, do nothing
        if (currentHolder == account) {
            return false;
        }

        // Revoke from current holder if exists
        if (currentHolder != address(0)) {
            $._roles[role].roleHolder = address(0);
            for (uint256 i = 0; i < $._accountRoles[currentHolder].length; i++) {
                if ($._accountRoles[currentHolder][i] == role) {
                    $._accountRoles[currentHolder][i] =
                        $._accountRoles[currentHolder][$._accountRoles[currentHolder].length - 1];
                    $._accountRoles[currentHolder].pop();
                    break;
                }
            }
            emit RoleRevoked(role, currentHolder, _msgSender());
        }

        // Grant to new account
        $._roles[role].roleHolder = account;
        $._accountRoles[account].push(role);
        emit RoleGranted(role, account, _msgSender());
        return true;
    }

    /**
     * @dev Attempts to revoke `role` from `account` and returns a boolean indicating if `role` was revoked.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
        AccessControlStorage storage $ = _getAccessControlStorage();
        if ($._roles[role].roleHolder == account) {
            $._roles[role].roleHolder = address(0);
            for (uint256 i = 0; i < $._accountRoles[account].length; i++) {
                if ($._accountRoles[account][i] == role) {
                    $._accountRoles[account][i] = $._accountRoles[account][$._accountRoles[account].length - 1];
                    $._accountRoles[account].pop();
                    break;
                }
            }
            emit RoleRevoked(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}
