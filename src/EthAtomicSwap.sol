// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title EthAtomicSwap
 * @notice Production-grade HTLC for ETH & ERC‑20 with cross‑chain metadata.
 * @dev    Highlights
 *         – Ownable + Pausable emergency controls
 *         – ReentrancyGuard on state-changing functions
 *         – Supports non‑EVM address formats on both legs (bytes fields)
 *         – Records desired asset/amount expected on counter‑chain
 *         – swapID = keccak256(locker, hashSecret, recipientHash)
 */
contract EthAtomicSwap is Ownable, Pausable, ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Swap {
        // Asset the locker deposited on *this* chain
        address assetLocked;
        uint256 amountLocked;
        // Initiator (EVM address)
        address locker;
        // Counter‑party identifier on *other* chain
        bytes recipientRaw; // arbitrary bytes (bech32, base58, etc.)
        bytes32 recipientHash; // keccak256(recipientRaw)
        // What the locker expects back on the other chain
        bytes desiredAssetRaw; // token/denom identifier in raw bytes
        uint256 desiredAmount;
        // Time after which refund() unlocks
        uint256 expiryTs;
        // Terminal flag to prevent double‑spend
        bool claimed;
    }

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => Swap) public swaps; // swapID => Swap

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event Locked(
        bytes32 indexed swapID,
        bytes32 indexed hashSecret,
        address indexed assetLocked,
        uint256 amountLocked,
        bytes recipientRaw,
        bytes desiredAssetRaw,
        uint256 desiredAmount,
        uint256 expiryTs,
        address locker
    );

    event Claimed(bytes32 indexed swapID, bytes secret);
    event Refunded(bytes32 indexed swapID);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Initialize contract with deployer as owner.
    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier swapExists(bytes32 swapID) {
        require(swaps[swapID].locker != address(0), "AS: unknown swapID");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN
    //////////////////////////////////////////////////////////////*/
    /// @notice Pause claims & refunds (locking still allowed) in emergencies.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume normal operation.
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock ETH or ERC‑20 into the contract.
     * @param hashSecret         SHA‑256 hash of the secret.
     * @param recipientRaw       Counter‑party address (any format).
     * @param expiryTs           UNIX timestamp after which refund() is possible.
     * @param assetLocked        Asset deposited on this chain (address(0)=ETH).
     * @param amountLocked       Token amount; ignored for ETH (msg.value used).
     * @param desiredAssetRaw    Identifier of asset expected on other chain.
     * @param desiredAmount      Amount expected on the other chain.
     * @return swapID            Deterministic identifier for this swap.
     */
    function lock(
        bytes32 hashSecret,
        bytes calldata recipientRaw,
        uint256 expiryTs,
        address assetLocked,
        uint256 amountLocked,
        bytes calldata desiredAssetRaw,
        uint256 desiredAmount
    ) external payable whenNotPaused nonReentrant returns (bytes32 swapID) {
        // --- validation ----------------------------------------------------
        require(hashSecret != bytes32(0), "AS: empty hash");
        require(recipientRaw.length > 0, "AS: empty recipient");
        require(desiredAssetRaw.length > 0, "AS: empty desiredAsset");
        require(expiryTs > block.timestamp, "AS: expiry in past");
        require(desiredAmount > 0, "AS: zero desired");

        uint256 value;
        if (assetLocked == address(0)) {
            value = msg.value;
            require(value > 0, "AS: no ether supplied");
        } else {
            require(amountLocked > 0, "AS: zero token amount");
            IERC20(assetLocked).safeTransferFrom(msg.sender, address(this), amountLocked);
            value = amountLocked;
        }

        bytes32 recipientHash = keccak256(recipientRaw);
        swapID = keccak256(abi.encodePacked(msg.sender, hashSecret, recipientHash));
        require(swaps[swapID].locker == address(0), "AS: swap exists");

        swaps[swapID] = Swap({
            assetLocked: assetLocked,
            amountLocked: value,
            locker: msg.sender,
            recipientRaw: recipientRaw,
            recipientHash: recipientHash,
            desiredAssetRaw: desiredAssetRaw,
            desiredAmount: desiredAmount,
            expiryTs: expiryTs,
            claimed: false
        });

        emit Locked(
            swapID, hashSecret, assetLocked, value, recipientRaw, desiredAssetRaw, desiredAmount, expiryTs, msg.sender
        );
    }

    /**
     * @notice Claim locked funds by revealing the secret.
     * @param swapID Identifier obtained from the lock() event.
     * @param secret Original pre‑image whose SHA‑256 equals hashSecret.
     */
    function claim(bytes32 swapID, bytes calldata secret) external whenNotPaused nonReentrant swapExists(swapID) {
        Swap storage s = swaps[swapID];

        require(!s.claimed, "AS: already claimed");
        require(block.timestamp <= s.expiryTs, "AS: expired");

        bytes32 hashSecret = sha256(secret);
        require(keccak256(abi.encodePacked(s.locker, hashSecret, s.recipientHash)) == swapID, "AS: wrong secret");

        s.claimed = true;

        if (s.assetLocked == address(0)) {
            payable(msg.sender).sendValue(s.amountLocked);
        } else {
            IERC20(s.assetLocked).safeTransfer(msg.sender, s.amountLocked);
        }

        emit Claimed(swapID, secret);
    }

    /**
     * @notice Refund function callable by locker after expiry.
     * @param swapID Identifier obtained from lock() event.
     */
    function refund(bytes32 swapID) external whenNotPaused nonReentrant swapExists(swapID) {
        Swap storage s = swaps[swapID];

        require(msg.sender == s.locker, "AS: not locker");
        require(!s.claimed, "AS: already claimed");
        require(block.timestamp > s.expiryTs, "AS: not expired");

        s.claimed = true;

        if (s.assetLocked == address(0)) {
            payable(s.locker).sendValue(s.amountLocked);
        } else {
            IERC20(s.assetLocked).safeTransfer(s.locker, s.amountLocked);
        }

        emit Refunded(swapID);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Pure helper to predict swapID off‑chain.
     */
    function previewSwapID(address locker, bytes32 hashSecret, bytes calldata recipientRaw)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(locker, hashSecret, keccak256(recipientRaw)));
    }
}
