// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./WZND.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Bridge is Ownable {
    WZND public wznd;
    mapping(bytes => bool) public processedProofs;
    address public relayer;
    uint256 public bridgeFeeBasisPoints = 25; // 0.25%
    address public treasury;

    event MintWZND(address indexed to, uint256 amount, bytes zondProof);
    event BurnWZND(address indexed from, uint256 amount);
    event TreasuryUpdated(address indexed newTreasury);
    event RelayerUpdated(address indexed newRelayer);
    event BridgeFeeUpdated(uint256 newBridgeFeeBasisPoints);

    /**
     * @dev Initializes the Bridge contract with the `wZND` token, `relayer`, and `treasury` addresses.
     * @param _wznd The address of the wZND token contract.
     * @param _relayer The address of the relayer responsible for processing proofs.
     * @param _treasury The address where bridge fees are collected.
     */
    constructor(address _wznd, address _relayer, address _treasury) Ownable(msg.sender) {
        require(_wznd != address(0), "Bridge: wZND address cannot be zero");
        require(_relayer != address(0), "Bridge: relayer address cannot be zero");
        require(_treasury != address(0), "Bridge: treasury address cannot be zero");
        wznd = WZND(_wznd);
        relayer = _relayer;
        treasury = _treasury;
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "Bridge: Caller is not the relayer");
        _;
    }

    /**
     * @dev Updates the relayer address. Only callable by the contract owner.
     * @param _newRelayer The address of the new relayer.
     */
    function setRelayer(address _newRelayer) external onlyOwner {
        require(_newRelayer != address(0), "Bridge: relayer is the zero address");
        relayer = _newRelayer;
        emit RelayerUpdated(_newRelayer);
    }

    /**
     * @dev Updates the treasury address. Only callable by the contract owner.
     * @param _newTreasury The address of the new treasury.
     */
    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Bridge: treasury is the zero address");
        treasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }
    
    /**
     * @dev Updates the bridge fee. Only callable by the contract owner.
     * @param _bridgeFeeBasisPoints The new bridge fee in basis points.
     */
    function setBridgeFee(uint256 _bridgeFeeBasisPoints) external onlyOwner {
        require(_bridgeFeeBasisPoints <= 1000, "Bridge: bridge fee too high"); // Max 10%
        bridgeFeeBasisPoints = _bridgeFeeBasisPoints;
        emit BridgeFeeUpdated(_bridgeFeeBasisPoints);
    }

    /**
     * @dev Mints `wZND` tokens to the specified address after verifying the Zond proof.
     * Can only be called by the relayer.
     * @param to The recipient address on the EVM chain.
     * @param amount The amount of `wZND` to mint (before fee).
     * @param zondProof The proof from the Zond chain confirming ZND lock.
     */
    function mintWZND(address to, uint256 amount, bytes calldata zondProof) external onlyRelayer {
        require(to != address(0), "Bridge: cannot mint to zero address");
        require(amount > 0, "Bridge: amount must be greater than zero");
        require(!processedProofs[zondProof], "Bridge: Proof already processed");

        // TODO: Implement Zond proof verification logic here
        // This should verify that `zondProof` is a valid proof of ZND lock on the Zond chain.

        processedProofs[zondProof] = true;

        uint256 fee = (amount * bridgeFeeBasisPoints) / 10000;
        uint256 mintAmount = amount - fee;

        // Mint `wZND` to the recipient
        wznd.mint(to, mintAmount);

        // Mint bridge fee to treasury
        if (fee > 0) {
            wznd.mint(treasury, fee);
        }

        emit MintWZND(to, mintAmount, zondProof);
    }

    /**
     * @dev Burns `wZND` tokens from the caller and emits a Burn event for unlocking ZND on Zond.
     * A bridge fee is applied and sent to the treasury.
     * @param amount The total amount of `wZND` to burn (includes fee).
     */
    function burnWZND(uint256 amount) external {
        require(amount > 0, "Bridge: amount must be greater than zero");

        uint256 fee = (amount * bridgeFeeBasisPoints) / 10000;
        uint256 burnAmount = amount - fee;

        // Burn the total amount from the user
        wznd.burn(msg.sender, burnAmount);

        // Mint the fee to the treasury
        if (fee > 0) {
            wznd.transfer(treasury, fee);
        }

        emit BurnWZND(msg.sender, burnAmount);

        // Emit event for Relayer to unlock ZND on Zond
        // The relayer should listen to this event and perform the unlock on Zond
    }
}