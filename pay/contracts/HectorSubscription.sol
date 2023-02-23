// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

error INVALID_ADDRESS();
error INVALID_AMOUNT();
error INVALID_TIME();
error INVALID_PLAN();
error PAYER_IN_DEBT();
error INACTIVE_SUBSCRIPTION();
error ACTIVE_SUBSCRIPTION();

contract HectorSubscription is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /* ======== STORAGE ======== */

    struct Plan {
        address token; // TOR, WFTM
        uint48 period; // 3 months, 6 months, 12 months
        uint256 amount;
    }

    struct Subscription {
        uint256 planId;
        uint48 expiredAt;
    }

    /// @notice treasury wallet
    address public treasury;

    /// @notice subscription plans configurable by admin
    Plan[] public plans;

    /// @notice users token balance data
    mapping(address => mapping(address => uint256)) public balanceOf;

    /// @notice users subscription data
    mapping(address => Subscription) public subscriptions;

    /* ======== EVENTS ======== */

    event PlanUpdated(
        uint256 indexed planId,
        address token,
        uint48 period,
        uint256 amount
    );
    event SubscriptionCreated(address indexed from, uint256 indexed planId);
    event SubscriptionSynced(address indexed from, uint48 expiredAt);
    event SubscriptionCancelled(address indexed from);
    event SubscriptionModified(address indexed from, uint256 indexed newPlanId);
    event PayerDeposit(
        address indexed from,
        address indexed token,
        uint256 amount
    );
    event PayerWithdraw(
        address indexed from,
        address indexed token,
        uint256 amount
    );

    /* ======== INITIALIZATION ======== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _treasury) external initializer {
        if (_treasury == address(0)) revert INVALID_ADDRESS();
        treasury = _treasury;

        if (plans.length == 0) {
            plans.push(Plan({token: address(0), period: 0, amount: 0}));
        }

        __Ownable_init();
    }

    /* ======== MODIFIER ======== */
    modifier onlyValidPlan(uint256 _planId) {
        if (_planId == 0 || _planId >= plans.length) revert INVALID_PLAN();
        _;
    }

    /* ======== POLICY FUNCTIONS ======== */

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert INVALID_ADDRESS();
        treasury = _treasury;
    }

    function appendPlan(Plan[] calldata _plans) external onlyOwner {
        uint256 length = _plans.length;
        for (uint256 i = 0; i < length; i++) {
            Plan memory _plan = _plans[i];

            if (_plan.token == address(0)) revert INVALID_ADDRESS();
            if (_plan.period == 0) revert INVALID_TIME();
            if (_plan.amount == 0) revert INVALID_AMOUNT();

            plans.push(_plan);

            emit PlanUpdated(
                plans.length - 1,
                _plan.token,
                _plan.period,
                _plan.amount
            );
        }
    }

    function updatePlan(uint256 _planId, Plan calldata _plan)
        external
        onlyOwner
        onlyValidPlan(_planId)
    {
        if (_plan.token == address(0)) revert INVALID_ADDRESS();
        if (_plan.period == 0) revert INVALID_TIME();
        if (_plan.amount == 0) revert INVALID_AMOUNT();

        plans[_planId] = _plan;

        emit PlanUpdated(_planId, _plan.token, _plan.period, _plan.amount);
    }

    /* ======== VIEW FUNCTIONS ======== */

    function allPlans() external view returns (Plan[] memory) {
        return plans;
    }

    function getSubscription(address from)
        external
        view
        returns (
            uint256 planId,
            uint48 expiredAt,
            bool isActiveForNow,
            uint256 chargeAmount
        )
    {
        Subscription memory subscription = subscriptions[from];
        planId = subscription.planId;

        // No subscription
        if (planId == 0) {
            return (0, 0, false, 0);
        }

        expiredAt = subscription.expiredAt;

        // before expiration
        if (block.timestamp < expiredAt) {
            isActiveForNow = true;
        }
        // after expiration
        else {
            Plan memory plan = plans[planId];
            uint256 count = (block.timestamp - expiredAt + plan.period) /
                plan.period;
            uint256 amount = plan.amount * count;
            uint256 balance = balanceOf[from][plan.token];

            if (balance >= amount) {
                isActiveForNow = true;
                chargeAmount = 0;
            } else {
                isActiveForNow = false;
                chargeAmount = amount - balance;
            }
        }
    }

    /* ======== USER FUNCTIONS ======== */

    function deposit(address _token, uint256 _amount) public {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit PayerDeposit(msg.sender, _token, _amount);
    }

    function createSubscription(uint256 _planId) public onlyValidPlan(_planId) {
        if (subscriptions[msg.sender].planId > 0) revert ACTIVE_SUBSCRIPTION();

        Plan memory plan = plans[_planId];

        if (balanceOf[msg.sender][plan.token] < plan.amount)
            revert PAYER_IN_DEBT();

        balanceOf[msg.sender][plan.token] -= plan.amount;
        IERC20(plan.token).safeTransfer(treasury, plan.amount);

        subscriptions[msg.sender] = Subscription({
            planId: _planId,
            expiredAt: uint48(block.timestamp + plan.period)
        });

        emit SubscriptionCreated(msg.sender, _planId);
    }

    function depositAndCreateSubscription(uint256 _planId, uint256 _amount)
        external
    {
        deposit(plans[_planId].token, _amount);
        createSubscription(_planId);
    }

    function syncSubscription(address from) public {
        Subscription storage subscription = subscriptions[from];
        uint256 planId = subscription.planId;

        if (planId == 0) revert INACTIVE_SUBSCRIPTION();

        // before expiration
        if (block.timestamp < subscription.expiredAt) {}
        // after expiration
        else {
            Plan memory plan = plans[planId];
            uint256 count = (block.timestamp -
                subscription.expiredAt +
                plan.period) / plan.period;
            uint256 amount = plan.amount * count;
            uint256 balance = balanceOf[from][plan.token];

            // not active for now
            if (balance < amount) {
                count = balance / plan.amount;
                amount = plan.amount * count;
            }

            if (count > 0) {
                balanceOf[from][plan.token] -= amount;
                subscription.expiredAt += uint48(plan.period * count);

                IERC20(plan.token).transfer(treasury, amount);

                emit SubscriptionSynced(from, subscription.expiredAt);
            }
        }
    }

    function cancelSubscription() external {
        syncSubscription(msg.sender);

        subscriptions[msg.sender].planId = 0;

        emit SubscriptionCancelled(msg.sender);
    }

    function modifySubscription(uint256 _newPlanId)
        external
        onlyValidPlan(_newPlanId)
    {
        syncSubscription(msg.sender);

        subscriptions[msg.sender].planId = _newPlanId;

        emit SubscriptionModified(msg.sender, _newPlanId);
    }

    function withdraw(address _token, uint256 _amount) external {
        if (subscriptions[msg.sender].planId > 0) {
            syncSubscription(msg.sender);
        }

        if (_token == address(0)) revert INVALID_ADDRESS();
        if (_amount == 0) revert INVALID_AMOUNT();
        if (balanceOf[msg.sender][_token] < _amount) revert INVALID_AMOUNT();

        balanceOf[msg.sender][_token] -= _amount;

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit PayerWithdraw(msg.sender, _token, _amount);
    }

    function withdrawAll(address _token) external returns (uint256 amount) {
        if (subscriptions[msg.sender].planId > 0) {
            syncSubscription(msg.sender);
        }

        if (_token == address(0)) revert INVALID_ADDRESS();

        amount = balanceOf[msg.sender][_token];

        if (amount > 0) {
            balanceOf[msg.sender][_token] = 0;
            IERC20(_token).safeTransfer(msg.sender, amount);

            emit PayerWithdraw(msg.sender, _token, amount);
        }
    }
}
