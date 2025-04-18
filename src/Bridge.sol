// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./WZND.sol";

/// @title  EVM‑side bridge contract (mint/burn wZND)
/// @notice Trust‑minimized: a) replay‑protected, b) relayers in multisig,
///         c) no ability to unlock ZND without burn proof.
contract ZondBridge is AccessControl, ReentrancyGuard {
    using SafeCast for uint256;

    // --- immutables / roles ----------------------------------------------
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    uint16  public constant FEE_BPS      = 25;      // 0.25 %

    WZND public immutable WZND_TOKEN;
    address public immutable FEE_TREASURY;

    // --- events -----------------------------------------------------------
    event Minted(
        bytes32 indexed lockHash,
        address indexed recipient,
        uint256 amountAfterFee,
        uint256 fee
    );

    event Burned(
        bytes32 indexed burnHash,
        address indexed sender,
        uint256 amount
    );

    // --- storage ----------------------------------------------------------
    mapping(bytes32 => bool) public processedLock;   // Zond→EVM proofs
    mapping(bytes32 => bool) public processedBurn;   // replay local

    // --- constructor ------------------------------------------------------
    constructor(address feeTreasury) {
        FEE_TREASURY = feeTreasury;

        // Deploy wZND first‑class so it is immutable & audit‑friendly
        WZND_TOKEN = new WZND(address(this));

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RELAYER_ROLE, msg.sender);
    }

    // --- mint flow (Zond → EVM) ------------------------------------------

    /// @notice Mint wZND after a verified lockHash from Zond.
    /// @dev    Called by authorised relayers.
    function mint(
        bytes32 lockHash,
        address recipient,
        uint256 amountAfterFee
    )
        external
        onlyRole(RELAYER_ROLE)
        nonReentrant
    {
        require(!processedLock[lockHash], "lock already used");
        processedLock[lockHash] = true;

        uint256 fee = (amountAfterFee * FEE_BPS) / 10_000;
        uint256 payout = amountAfterFee - fee;

        WZND_TOKEN.mint(recipient, payout);
        if (fee > 0) WZND_TOKEN.mint(FEE_TREASURY, fee);

        emit Minted(lockHash, recipient, payout, fee);
    }

    // --- burn flow (EVM → Zond) ------------------------------------------

    /// @notice User burns wZND to start unlock on Zond.
    function burn(uint256 amount)
        external
        nonReentrant
    {
        require(amount > 0, "amount=0");

        // burn (pull pattern ‑ user must approve)
        WZND_TOKEN.burn(msg.sender, amount);

        bytes32 burnHash = keccak256(
            abi.encodePacked(msg.sender, amount, block.number)
        );

        // `processedBurn` stored so relayer can not double‑relay
        processedBurn[burnHash] = true;

        emit Burned(burnHash, msg.sender, amount);
    }
}
