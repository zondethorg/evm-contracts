// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title  Wrapped ZND (wZND) – ERC‑20 + Permit
/// @dev    Mint/Burn fully controlled by the bridge contract.
contract WZND is ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address bridge)
        ERC20("Wrapped Zond", "wZND")
        ERC20Permit("Wrapped Zond")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, bridge);
        _grantRole(MINTER_ROLE, bridge);
    }

    /// @notice Mint wZND (`bridge` only).
    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
    {
        _mint(to, amount);
    }

    /// @notice Burn wZND (`bridge` only).
    function burn(address from, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
    {
        _burn(from, amount);
    }
}
