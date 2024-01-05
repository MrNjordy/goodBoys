// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

 import "@openzeppelin/contracts/access/Ownable.sol";
 import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
 import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
 import "./utils/SafeMath.sol";
 import "./NativeToken.sol";
 import "./interfaces/IUniPairs.sol";
 import "./interfaces/IUniRouterV2.sol";

 import "hardhat/console.sol";

contract Masterchef is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    
    // Users' info
    struct UserInfo {
        uint256 amount; //how many lp tokens the user has provided
        uint256 rewardDebt; //what has already been claimed by the user, used to calculate pending rewards
                            // pending rewards = (user.amount * pool.accRewardsPerShare) - user.rewardDebt
    }

    // Pools' info
    struct PoolInfo {
        IERC20 lpToken; //address of token used for farming;
        uint256 allocPoint; //number of alloc points allocated to this pool. Tokens to distribute per block
        uint256 lastRewardBLock; // Last block number that tokens distribution occurred
        uint256 accRewardsPerShare; //Accumulated rewards per share, times 1e12, see below.
        uint256 stakingFee; //in percent ie: 1/2/3/4
    }

    // The native token
    NativeToken public nativeToken;
    // Rewards tokens created per block
    uint256 public rewardsPerBlock;
    // Bonus multiplier
    uint256 public BONUS_MULTIPLIER = 1;
    address public feeCollector;
    address public devAddress;

    IUniRouter public router;

    // Info of each pool
    PoolInfo[] public poolInfo;
    //Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points.  Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint = 0;
    // The block number when rewards mining starts
    uint256 public startBlock;
 
    mapping(address => bool) public lpTokenAdded;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address initialOwner,
        NativeToken _nativeToken,
        address _devAddress,
        address _feeCollector,
        uint256 _rewardsPerBlock,
        uint256 _startBlock,
        IUniRouter _router

    ) Ownable(initialOwner) {
        nativeToken = _nativeToken;
        devAddress = _devAddress;
        feeCollector = _feeCollector;
        rewardsPerBlock = _rewardsPerBlock;
        startBlock = _startBlock;
        router = _router;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns(uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Deposit Fee in exact percent i.e: 1, 2, 3, ...
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _stakingFee, bool _withUpdate) public onlyOwner {
        require(lpTokenAdded[address(_lpToken)] == false, 'Pool for this token already exists!');

        lpTokenAdded[address(_lpToken)] = true;

        if(_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBLock: lastRewardBlock,
            accRewardsPerShare: 0,
            stakingFee: _stakingFee * 100 //Later will be divided by 10000, this is in order to make it work with Solidity fractions
        }));
    }

    // Update the given pool's rewards allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if(_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if(prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

     // View function to see pending rewards on frontend.
     function pendingRewards(uint256 _pid, address _user) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if(block.number > pool.lastRewardBLock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBLock, block.number);
            uint256 tokenReward = multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e12).sub(user.rewardDebt);
     }

    // Update reward variables for all pools.
     function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for(uint256 pid = 0; pid<length; ++pid) {
            updatePool(pid);
        }
     }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if(block.number <= pool.lastRewardBLock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if(lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBLock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBLock, block.number);
        uint256 tokenReward = multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        nativeToken.mintFor(devAddress, tokenReward.div(10));
        nativeToken.mint(tokenReward);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardBLock = block.number;
    }

    // Deposit LP tokens to Masterchef for rewards allocation
    function deposit(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 lpTokenFromFees = _amount.mul(pool.stakingFee).div(10000);
            if (lpTokenFromFees > 0) {
                pool.lpToken.safeTransfer(feeCollector, lpTokenFromFees);
            }
            uint256 _after = pool.lpToken.balanceOf(address(this));
            _amount = _after.sub(before);

            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function depositReferral(uint256 _pid, uint256 _amount, address referral) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 lpTokenFromFees = _amount.mul(pool.stakingFee).div(10000);
            if (lpTokenFromFees > 0) {
                uint256 feeAddress1Share = lpTokenFromFees.mul(75).div(100);
                uint256 feeToReferee = lpTokenFromFees.sub(feeAddress1Share);

                pool.lpToken.safeTransfer(feeCollector, feeAddress1Share);
                pool.lpToken.safeTransfer(referral, feeToReferee);
            }
            uint256 _after = pool.lpToken.balanceOf(address(this));
            _amount = _after.sub(before);

            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    //Withdraw LP tokens from MasterChef
    function withdraw(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Don't have that much sir degen");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function withdrawReferral(uint256 _pid, uint256 _amount, address referral) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Don't have that much sir degen");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 lpTokenFromFees = _amount.mul(pool.stakingFee).div(10000);
            uint256 amountAfterFees = _amount.sub(lpTokenFromFees);

            if (lpTokenFromFees > 0) {
                uint256 feeAddress1Share = lpTokenFromFees.mul(75).div(100);
                uint256 feeToReferee = lpTokenFromFees.sub(feeAddress1Share);

                pool.lpToken.safeTransfer(feeCollector, feeAddress1Share);
                pool.lpToken.safeTransfer(referral, feeToReferee);
            }
            pool.lpToken.safeTransfer(address(msg.sender), amountAfterFees);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimAll() public {
        for(uint256 i=0; i<poolInfo.length; i++) {
            deposit(i, 0);
        }
    }

        //Router function names such as .WETH() might need updated dependiong on router
    function zapper(address _token, uint256 _pid) public payable {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 amountToSwap = (msg.value).div(2);
        uint256 amountLeft = msg.value.sub(amountToSwap);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(_token);

        uint256 tokenBalanceBefore = IERC20(_token).balanceOf(address(this));
        router.swapExactETHForTokens{value: amountToSwap}(0, path, address(this), block.timestamp);
        uint256 tokenBalanceAfter = IERC20(_token).balanceOf(address(this));
        uint256 tokensReceived = tokenBalanceAfter.sub(tokenBalanceBefore);

        uint256 lpTokensBefore = (pool.lpToken).balanceOf(address(this));
        router.addLiquidityETH{value: amountLeft}(address(_token), tokensReceived, 0, 0, address(this), block.timestamp);
        uint256 lpTokensAfter = (pool.lpToken).balanceOf(address(this));
        uint256 lpTokensReceived = lpTokensAfter.sub(lpTokensBefore);

        deposit(_pid, lpTokensReceived);
    }

        function zapperReferral(address _token, uint256 _pid, address referral) public payable {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 amountToSwap = (msg.value).div(2);
        uint256 amountLeft = msg.value.sub(amountToSwap);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(_token);

        uint256 tokenBalanceBefore = IERC20(_token).balanceOf(address(this));
        router.swapExactETHForTokens{value: amountToSwap}(0, path, address(this), block.timestamp);
        uint256 tokenBalanceAfter = IERC20(_token).balanceOf(address(this));
        uint256 tokensReceived = tokenBalanceAfter.sub(tokenBalanceBefore);

        uint256 lpTokensBefore = (pool.lpToken).balanceOf(address(this));
        router.addLiquidityETH{value: amountLeft}(address(_token), tokensReceived, 0, 0, address(this), block.timestamp);
        uint256 lpTokensAfter = (pool.lpToken).balanceOf(address(this));
        uint256 lpTokensReceived = lpTokensAfter.sub(lpTokensBefore);

        depositReferral(_pid, lpTokensReceived, referral);
    }

    function lpCompound(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        address[] memory path = new address[](2);
        path[0] = address(nativeToken);
        path[1] = router.WETH();

        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(address(this), pending);
                uint256 amountToSwap = pending.div(2);
                uint256 amountToAdd = pending.sub(amountToSwap);

                uint256 ethBalanceBefore = address(this).balance;
                router.swapExactTokensForETH(amountToSwap, 0, path, address(this), block.timestamp);
                uint256 ethBalanceAfter = address(this).balance;
                uint256 ethToAdd = ethBalanceAfter.sub(ethBalanceBefore);

                uint256 lpTokensBefore = (pool.lpToken).balanceOf(address(this));
                router.addLiquidityETH{value: ethToAdd}(address(nativeToken), amountToAdd, 0, 0, address(this), block.timestamp);
                uint256 lpTokensAfter = (pool.lpToken).balanceOf(address(this));
                uint256 lpTokensReceived = lpTokensAfter.sub(lpTokensBefore);

                deposit(_pid, lpTokensReceived);
            }
        }
    }

    function lpCompoundReferral(uint256 _pid, address referral) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        address[] memory path = new address[](2);
        path[0] = address(nativeToken);
        path[1] = router.WETH();

        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(address(this), pending);
                uint256 amountToSwap = pending.div(2);
                uint256 amountToAdd = pending.sub(amountToSwap);

                uint256 ethBalanceBefore = address(this).balance;
                router.swapExactTokensForETH(amountToSwap, 0, path, address(this), block.timestamp);
                uint256 ethBalanceAfter = address(this).balance;
                uint256 ethToAdd = ethBalanceAfter.sub(ethBalanceBefore);

                uint256 lpTokensBefore = (pool.lpToken).balanceOf(address(this));
                router.addLiquidityETH{value: ethToAdd}(address(nativeToken), amountToAdd, 0, 0, address(this), block.timestamp);
                uint256 lpTokensAfter = (pool.lpToken).balanceOf(address(this));
                uint256 lpTokensReceived = lpTokensAfter.sub(lpTokensBefore);

                depositReferral(_pid, lpTokensReceived, referral);
            }
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe token transfer function, just in case rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        nativeToken.safeTokenTransfer(_to, _amount);
    }

    function setRewardsPerBlock(uint _value) public onlyOwner {
        rewardsPerBlock = _value;
    }

    // Update dev address
    function setDevAddress(address _devAddress) public onlyOwner {
        devAddress = _devAddress;
    }

    //Update fee collector address
    function setFeeCollector(address _feeAddress1) public onlyOwner {
        feeCollector = _feeAddress1;
    }

    function setStakingFee(uint256 _pid, uint256 _stakingFee) public onlyOwner {
        require(_stakingFee <= 4, "Staking fee cannot be over 4%");
        poolInfo[_pid].stakingFee = _stakingFee * 100;
    }
}

