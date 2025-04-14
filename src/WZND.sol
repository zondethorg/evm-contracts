// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WZND is ERC20, Ownable {
    address public bridge;

    modifier onlyBridge() {
        require(msg.sender == bridge, "wZND: Caller is not the bridge");
        _;
    }

    constructor() ERC20("Wrapped ZOND", "wZND") Ownable(msg.sender) {}

    /**
     * @dev Sets the bridge contract address. Can only be called by the contract owner.
     * @param _bridge The address of the Bridge contract.
     */
    function setBridge(address _bridge) external onlyOwner {
        require(_bridge != address(0), "wZND: bridge is the zero address");
        bridge = _bridge;
    }

    /**
     * @dev Mints `amount` tokens to address `to`. Can only be called by the Bridge contract.
     * @param to The address to receive the minted tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    /**
     * @dev Burns `amount` tokens from address `from`. Can only be called by the Bridge contract.
     * @param from The address from which tokens will be burned.
     * @param amount The number of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyBridge {
        _burn(from, amount);
    }
}