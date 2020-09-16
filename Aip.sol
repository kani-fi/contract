pragma solidity ^0.5.0;

import "./IERC20.sol";

contract Pool2 is IERC20 {
    function stake(uint256 amount) external returns (bool);

    function getReward() external returns (bool);

    function withdraw(uint256 amount) external returns (bool);

    function exit() external returns (bool);
}

contract BptToken is IERC20 {
    function joinswapExternAmountIn(address tokenIn, uint256 tokenAmountIn, uint256 minPoolAmountOut) external returns (uint256);

    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn) external returns (uint256);
}

contract WETHToken is IERC20 {
    function deposit() public payable ;
}

library SafePool2 {
    using SafeMath for uint256;
    using Address for address;

    function safeStake(Pool2 token, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.stake.selector, value));
    }

    function safeGetReward(Pool2 token) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.getReward.selector));
    }

    function safeWithdraw(Pool2 token, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.withdraw.selector, value));
    }

    function safeExit(Pool2 token) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.exit.selector));
    }

    function callOptionalReturn(Pool2 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

library SafeBpt {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(BptToken token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function callOptionalReturn(BptToken token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

library SafeWETH {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

pragma solidity ^0.5.0;

import "./Math.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract AipRewards is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafePool2 for Pool2;
    using SafeWETH for WETHToken;
    using SafeBpt for BptToken;

    // pool0
    IERC20 public pool0 = IERC20(0x09605d1118B4C5C013Fae56730188dA48A769ab6);
    // weth
    WETHToken public weth = WETHToken(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    // kani
    IERC20 public kani = IERC20(0xbf2adbAEf67783a1ff894A4d63B16426844b54c2);
    // bpt
    BptToken public bpt = BptToken(0x0DCB7603105197333Ce123E010755F0F21C2934B);
    // pool2
    Pool2 public pool2 = Pool2(0x4FED7A096243bc7DA8940835Fe1A7935Dace2F89);

    uint256 public constant DURATION = 1 days;

    // weth
    uint256 public constant totalSupply = 100*1e18;
    uint256 public constant dailyJoin = 1*1e18;
    uint256 public totalJoined = 0;
    uint256 public lastJoinTime = 0;

    uint256 public rewardStartTime = 0;
    uint256 public totalReward = 0;
    mapping(address => uint256) public rewardPaids;

    event JoinPool(address indexed pool, uint256 amount);
    event Staked(address indexed pool, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 reward);

    function() external payable {
        weth.deposit.value(msg.value)();
    }

    function init() public onlyOwner{
        require(weth.balanceOf(address(this)) >= dailyJoin, "balance not enough");
        require(lastJoinTime == 0, "inited");
        lastJoinTime = block.timestamp.sub(1 days);
        rewardStartTime = block.timestamp.add(DURATION);
        joinPool();
    }

    /** balancer pool actions */
    // balancer pool : weth <=> kani
    // deposit eth to weth
    // join weth to b-pool and get bpt back
    // stake bpt to pool2
    function joinPool() public {
        require(lastJoinTime > 0, "not start");
        if (block.timestamp.sub(lastJoinTime) >= 1 days
            && totalJoined < totalSupply) {
            totalJoined = totalJoined.add(dailyJoin);
            lastJoinTime = block.timestamp;
            // and liquidity and get bpt
            uint256 reward = dailyJoin.mul(2).div(100);
            weth.approve(address(bpt), dailyJoin.sub(reward));
            uint256 amount = bpt.joinswapExternAmountIn(address(weth), dailyJoin.sub(reward), 0);
            emit JoinPool(address(bpt), dailyJoin.sub(reward));
            // stake bpt to pool2
            stake(amount);
            // get kani reward from pool2
            withdrawKani();
            // reward
            weth.safeTransfer(msg.sender, reward);
        }
    }

    // get weth back from balancer pool
    function exitBPool(uint256 amount) public onlyOwner {
        bpt.exitswapExternAmountOut(address(weth), amount, bpt.balanceOf(address(this)));
    }

    /** pool2 actions */
    // stake bpt to pool2
    function stake(uint256 amount) internal {
        if (amount > 0) {
            bpt.approve(address(pool2), amount);
            pool2.safeStake(amount);
            emit Staked(address(pool2), amount);
        }
    }

    // get kani reward from pool2
    function withdrawKani() internal {
        pool2.safeGetReward();
        totalReward = kani.balanceOf(address(this));
    }

    // get bpt & kani reward back
    function exitPool2() public onlyOwner {
        pool2.safeExit();
        totalReward = kani.balanceOf(address(this));
    }

    // get bpt back
    function withdrawBpt(uint256 amount) public onlyOwner {
        // require(block.timestamp.sub(rewardStartTime) > 49 days, "not start");
        // require(pool2.balanceOf(address(this)) >= amount, "balance not enough");
        pool2.safeWithdraw(amount);
    }

    /** user actions */
    // user get total earned kani
    function kaniEarned(address account) public view returns (uint256) {
        if (block.timestamp < rewardStartTime || totalReward <= 0)  return 0;
        return pool0.balanceOf(account).div(totalSupply).mul(totalReward);
    }

    // user get kani reward
    function getKaniReward() public checkStart {
        uint256 reward = kaniEarned(msg.sender).sub(rewardPaids[msg.sender]);
        if (reward > 0) {
            rewardPaids[msg.sender] = rewardPaids[msg.sender].add(reward);
            kani.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, address(kani), reward);
        }
    }

    // user get total earned bpt
    function bptEarned(address account) public view returns (uint256) {
        return pool0.balanceOf(account).div(totalSupply).mul(bpt.balanceOf(address(this)));
    }

    // user get bpt reward
    function getBptReward() public {
        // require(block.timestamp.sub(rewardStartTime) > 49 days, "not start");
        uint bptAmount = bpt.balanceOf(address(this));
        if (bptAmount > 0) {
            uint256 reward = pool0.balanceOf(msg.sender).div(totalSupply).mul(bptAmount);
            bpt.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, address(bpt), reward);
        }
    }

    modifier checkStart(){
        require(block.timestamp > rewardStartTime,"not start");
        _;
    }

    function exitToken(address token, address payable account, uint256 amount) public onlyOwner {
        IERC20 t = IERC20(token);
        require(t.balanceOf(address(this)) >= amount, "balance not enough");
        t.safeTransfer(account, amount);
    }
}