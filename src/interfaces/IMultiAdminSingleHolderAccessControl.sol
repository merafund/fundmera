// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund

pragma solidity 0.8.29;

/**
 * @dev External interface of MultiAdminSingleHolderAccessControl declared to support ERC-165 detection.
 * Based on OpenZeppelin's IAccessControl but modified for single holder pattern.
 */
interface IMultiAdminSingleHolderAccessControl {
    /**
     * @dev The `account` is missing a role.
     */
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /**
     * @dev The caller of a function is not the expected one.
     *
     * NOTE: Don't confuse with {AccessControlUnauthorizedAccount}.
     */
    error AccessControlBadConfirmation();

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted to signal this.
     */
    event RoleAdminAdded(bytes32 indexed role, bytes32 indexed adminRole);

    /**
     * @dev Emitted when `adminRole` is removed from ``role``'s admin roles.
     */
    event RoleAdminRemoved(bytes32 indexed role, bytes32 indexed adminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
     * Expected in cases where the role was granted using the internal {_grantRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the address that currently holds the specified role.
     * Returns address(0) if no one holds the role.
     */
    function getRoleHolder(bytes32 role) external view returns (address);

    /**
     * @dev Returns true if adminRole can control role
     */
    function isRoleAdmin(bytes32 role, bytes32 adminRole) external view returns (bool);

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
     */
    function grantRole(bytes32 role, address account) external;
}
