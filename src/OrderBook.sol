// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./WZND.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OrderbookDEX is Ownable {
    WZND public wznd;
    address public treasury;
    uint256 public makerFeeBasisPoints = 10; // 0.1%
    uint256 public takerFeeBasisPoints = 10; // 0.1%
    uint256 public orderCount;

    enum OrderType { Buy, Sell }

    struct Order {
        uint256 id;
        OrderType orderType;
        address user;
        uint256 amountZND;    // Amount of ZND to buy/sell
        uint256 priceETH;     // Price per ZND in ETH
        bool isActive;
    }

    // Mapping from order ID to Order details
    mapping(uint256 => Order) public orders;

    // Events
    event OrderPlaced(uint256 indexed id, OrderType orderType, address indexed user, uint256 amountZND, uint256 priceETH);
    event OrderMatched(uint256 indexed buyOrderId, uint256 indexed sellOrderId, address indexed buyer, address seller, uint256 amountZND, uint256 priceETH);
    event OrderCancelled(uint256 indexed id);

    /**
     * @dev Initializes the DEX with the `wZND` token and `treasury` address.
     * @param _wznd The address of the wZND token contract.
     * @param _treasury The address where fees are collected.
     */
    constructor(address _wznd, address _treasury) Ownable(msg.sender) {
        require(_wznd != address(0), "OrderbookDEX: wZND address cannot be zero");
        require(_treasury != address(0), "OrderbookDEX: treasury address cannot be zero");
        wznd = WZND(_wznd);
        treasury = _treasury;
    }

    /**
     * @dev Updates the treasury address. Only callable by the contract owner.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "OrderbookDEX: treasury address cannot be zero");
        treasury = _treasury;
    }

    /**
     * @dev Places a new buy or sell order.
     * @param _type The type of order: Buy or Sell.
     * @param amountZND The amount of ZND to buy or sell.
     * @param priceETH The price per ZND in ETH.
     */
    function placeOrder(OrderType _type, uint256 amountZND, uint256 priceETH) external payable {
        require(amountZND > 0, "OrderbookDEX: amount must be greater than zero");
        require(priceETH > 0, "OrderbookDEX: price must be greater than zero");

        if (_type == OrderType.Buy) {
            uint256 totalCost = amountZND * priceETH;
            require(msg.value >= totalCost, "OrderbookDEX: insufficient ETH sent");
            if (msg.value > totalCost) {
                payable(msg.sender).transfer(msg.value - totalCost);
            }
        } else {
            require(wznd.balanceOf(msg.sender) >= amountZND, "OrderbookDEX: insufficient wZND balance");
            require(wznd.allowance(msg.sender, address(this)) >= amountZND, "OrderbookDEX: insufficient allowance");
            require(wznd.transferFrom(msg.sender, address(this), amountZND), "OrderbookDEX: transferFrom failed");
        }

        orderCount += 1;
        orders[orderCount] = Order({
            id: orderCount,
            orderType: _type,
            user: msg.sender,
            amountZND: amountZND,
            priceETH: priceETH,
            isActive: true
        });

        emit OrderPlaced(orderCount, _type, msg.sender, amountZND, priceETH);
    }

    /**
     * @dev Matches an existing order with compatible opposite orders.
     * @param orderId The ID of the order to match.
     */
    function matchOrder(uint256 orderId) external payable {
        Order storage order = orders[orderId];
        require(order.isActive, "OrderbookDEX: order is not active");

        if (order.orderType == OrderType.Buy) {
            // Find a matching sell order
            for (uint256 i = 1; i <= orderCount; i++) {
                Order storage sellOrder = orders[i];
                if (sellOrder.isActive && sellOrder.orderType == OrderType.Sell && sellOrder.priceETH <= order.priceETH) {
                    _executeTrade(order, sellOrder);
                    break;
                }
            }
        } else {
            // Find a matching buy order
            for (uint256 i = 1; i <= orderCount; i++) {
                Order storage buyOrder = orders[i];
                if (buyOrder.isActive && buyOrder.orderType == OrderType.Buy && buyOrder.priceETH >= order.priceETH) {
                    _executeTrade(buyOrder, order);
                    break;
                }
            }
        }
    }

    /**
     * @dev Cancels an active order. Only the order creator can cancel.
     * @param orderId The ID of the order to cancel.
     */
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.isActive, "OrderbookDEX: order is not active");
        require(order.user == msg.sender, "OrderbookDEX: not your order");

        if (order.orderType == OrderType.Buy) {
            uint256 refundETH = order.amountZND * order.priceETH;
            payable(order.user).transfer(refundETH);
        } else {
            require(wznd.transfer(order.user, order.amountZND), "OrderbookDEX: refund transfer failed");
        }

        order.isActive = false;

        emit OrderCancelled(orderId);
    }

    /**
     * @dev Internal function to execute a trade between a buy order and a sell order.
     * @param buyOrder The buy order.
     * @param sellOrder The sell order.
     */
    function _executeTrade(Order storage buyOrder, Order storage sellOrder) internal {
        uint256 matchedAmount = buyOrder.amountZND < sellOrder.amountZND ? buyOrder.amountZND : sellOrder.amountZND;
        uint256 tradePrice = sellOrder.priceETH;

        // Calculate fees
        uint256 makerFee = matchedAmount * makerFeeBasisPoints / 10000;
        uint256 takerFee = matchedAmount * takerFeeBasisPoints / 10000;
        uint256 netAmount = matchedAmount - makerFee - takerFee;

        // Transfer ETH from DEX to seller (minus taker fee)
        uint256 totalETH = matchedAmount * tradePrice;
        uint256 feeETH = totalETH * takerFeeBasisPoints / 10000;
        uint256 sellerETH = totalETH - feeETH;
        payable(sellOrder.user).transfer(sellerETH);
        payable(treasury).transfer(feeETH); // Taker fee

        // Transfer wZND from DEX to buyer (minus maker fee)
        require(wznd.transfer(buyOrder.user, netAmount), "OrderbookDEX: wZND transfer failed");
        require(wznd.transfer(treasury, makerFee), "OrderbookDEX: maker fee transfer failed");

        // Update order amounts
        buyOrder.amountZND = buyOrder.amountZND - matchedAmount;
        sellOrder.amountZND = sellOrder.amountZND - matchedAmount;

        // Deactivate orders if fully matched
        if (buyOrder.amountZND == 0) {
            buyOrder.isActive = false;
        }
        if (sellOrder.amountZND == 0) {
            sellOrder.isActive = false;
        }

        emit OrderMatched(buyOrder.id, sellOrder.id, buyOrder.user, sellOrder.user, matchedAmount, tradePrice);
    }

    /**
     * @dev Utility function to find the minimum of two numbers.
     * @param a First number.
     * @param b Second number.
     * @return The smaller of `a` and `b`.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Allows the contract to receive ETH.
     */
    receive() external payable {}
}