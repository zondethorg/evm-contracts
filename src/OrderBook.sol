// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "./WZND.sol";

/// @title  Minimal on‑chain limit‑order orderbook (ETH ↔ wZND)
/// @notice Pure solidity – no oracles, no off‑chain matching.
///         Gas‑optimised constant‑memory queues per price tick.
contract OrderbookDEX is ReentrancyGuard {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    // --- immutables -------------------------------------------------------
    WZND  public immutable WZND_TOKEN;
    uint8 public constant PRICE_DECIMALS = 8;  // 1e‑8 ETH granularity

    constructor(WZND wznd) { WZND_TOKEN = wznd; }

    // --- order struct -----------------------------------------------------
    struct Order {
        uint128 amount;      // amount of wZND
        uint128 price;       // ETH per wZND * 1e8
        address maker;
        bool    isBuy;       // true = bid (ETH→wZND), false = ask
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    // price‑level queues
    mapping(uint128 => DoubleEndedQueue.Bytes32Deque) internal bids; // highest‑price first
    mapping(uint128 => DoubleEndedQueue.Bytes32Deque) internal asks; // lowest‑price first

    // --- events -----------------------------------------------------------
    event OrderPlaced(
        uint256 indexed id,
        address indexed maker,
        bool    isBuy,
        uint128 amount,
        uint128 price
    );

    event OrderFilled(
        uint256 indexed id,
        address indexed taker,
        uint128 amount,
        uint128 price
    );

    event OrderCancelled(uint256 indexed id);

    // --- helpers ----------------------------------------------------------
    function _enqueue(
        mapping(uint128 => DoubleEndedQueue.Bytes32Deque) storage book,
        uint128 price,
        uint256 id
    ) private {
        book[price].pushBack(bytes32(id));
    }

    function _dequeue(
        mapping(uint128 => DoubleEndedQueue.Bytes32Deque) storage book,
        uint128 price
    ) private returns (uint256 id) {
        id = uint256(book[price].popFront());
    }

    // --- place order ------------------------------------------------------
    function placeOrder(
        bool    isBuy,
        uint128 amount,
        uint128 price        // ETH per wZND * 1e‑8
    )
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        require(amount > 0, "amount=0");
        require(price  > 0, "price=0");

        if (isBuy) {
            // buyer escrows ETH
            uint256 cost = (uint256(amount) * price) / 1e8;
            require(msg.value == cost, "bad-eth");
        } else {
            // seller escrows wZND
            WZND_TOKEN.transferFrom(msg.sender, address(this), amount);
        }

        id = ++nextOrderId;
        orders[id] = Order({
            amount  : amount,
            price   : price,
            maker   : msg.sender,
            isBuy   : isBuy
        });

        _enqueue(isBuy ? bids : asks, price, id);
        emit OrderPlaced(id, msg.sender, isBuy, amount, price);

        // naive auto‑matching (one hop); full crossing left for v2
        _tryMatch(id);
    }

    // --- cancel -----------------------------------------------------------
    function cancel(uint256 id) external nonReentrant {
        Order storage o = orders[id];
        require(o.maker == msg.sender, "!maker");

        // refund
        if (o.isBuy) {
            uint256 refund = (uint256(o.amount) * o.price) / 1e8;
            payable(o.maker).transfer(refund);
        } else {
            WZND_TOKEN.transfer(o.maker, o.amount);
        }

        delete orders[id];
        emit OrderCancelled(id);
    }

    // --- internal match ---------------------------------------------------
    function _tryMatch(uint256 takerId) private {
        Order storage taker = orders[takerId];
        if (taker.amount == 0) return;                         // already filled

        mapping(uint128 => DoubleEndedQueue.Bytes32Deque) storage book =
            taker.isBuy ? asks : bids;

        // check best price level
        uint128 priceLevel = taker.price;
        if (book[priceLevel].empty()) return;

        uint256 makerId = _dequeue(book, priceLevel);
        Order storage maker = orders[makerId];
        if (maker.amount == 0) return;                         // cancelled

        uint128 tradeAmt = taker.amount < maker.amount
            ? taker.amount
            : maker.amount;

        // transfer assets
        if (taker.isBuy) {
            // taker sends ETH already, receives wZND
            WZND_TOKEN.transfer(taker.maker, tradeAmt);
            // maker receives ETH
            uint256 ethQty = (uint256(tradeAmt) * priceLevel) / 1e8;
            payable(maker.maker).transfer(ethQty);
        } else {
            // taker is seller
            uint256 ethQty = (uint256(tradeAmt) * priceLevel) / 1e8;
            payable(taker.maker).transfer(ethQty);
            WZND_TOKEN.transfer(maker.maker, tradeAmt);
        }

        taker.amount -= tradeAmt;
        maker.amount -= tradeAmt;

        emit OrderFilled(makerId, taker.maker, tradeAmt, priceLevel);
        emit OrderFilled(takerId, maker.maker, tradeAmt, priceLevel);
    }

    // --- fallback ---------------------------------------------------------
    receive() external payable {}
}
