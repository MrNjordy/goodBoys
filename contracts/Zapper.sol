// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./utils/SafeMath.sol";
import "./NativeToken.sol";
import "./interfaces/IUniPairs.sol";
import "./interfaces/IMasterchef.sol";
import "./interfaces/IJoe.sol";

contract Zapper {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IMasterchef public masterchef;
    IERC20 public wrappedAsset;
    IERC20 public nativeToken;
    IJoeRouter public router;
    address referral;

    constructor (
        IMasterchef _masterchef,
        IERC20 _wrappedAsset,
        IERC20 _nativeToken,
        IJoeRouter _router
    ) {
        masterchef = _masterchef;
        wrappedAsset = _wrappedAsset;
        nativeToken = _nativeToken;
        router = _router;
    }

    receive() external payable {}

    function zapper(uint256 _pid, address _referral) public payable {
        (address poolToken,,,,) = masterchef.poolInfo(_pid);
        address token0 = IUniPair(poolToken).token0();
        address token1 = IUniPair(poolToken).token1();
        referral = _referral;

        if (token0 == address(wrappedAsset) || token1 == address(wrappedAsset)) {
            _zapInAvaxLP(_pid, token0, token1, poolToken, msg.value);
        }
        else {
            _zapInLP(_pid, token0, token1, poolToken, msg.value);
        }
    }

    function stakingZapper(uint256 _pid, address _referral) public payable{
        (address poolToken,,,,) = masterchef.poolInfo(_pid);

        address[] memory path = new address[](2);
        path[0] = address(wrappedAsset);
        path[1] = address(poolToken);

        uint256 tokenBalanceBefore = IERC20(poolToken).balanceOf(address(this));
        router.swapExactAVAXForTokens{value: msg.value}(0, path, address(this), block.timestamp);
        uint256 tokenBalanceAfter = IERC20(poolToken).balanceOf(address(this));
        uint256 tokensReceived = tokenBalanceAfter.sub(tokenBalanceBefore);

        IUniPair(poolToken).approve(address(masterchef), tokensReceived);
        masterchef.depositFor(_pid, tokensReceived, _referral, msg.sender);
    }

    function lpCompound(uint256 _pid, address _referral) public {
        (address poolToken,,,,) = masterchef.poolInfo(_pid);

        address[] memory path = new address[](2);
        path[0] = address(nativeToken);
        path[1] = address(wrappedAsset);

        uint256 pendingRewards = masterchef.pendingRewards(_pid, msg.sender);
        masterchef.depositFor(_pid, 0, referral, msg.sender);

        nativeToken.safeTransferFrom(address(msg.sender), address(this), pendingRewards);
        uint256 amountToSwap = (nativeToken.balanceOf(address(this))).div(2);
        uint256 amountToAdd = (nativeToken.balanceOf(address(this))).sub(amountToSwap);

        uint256 ethBalanceBefore = address(this).balance;
        nativeToken.approve(address(router), amountToSwap);
        router.swapExactTokensForAVAX(amountToSwap, 0, path, address(this), block.timestamp);
        uint256 ethBalanceAfter = address(this).balance;
        uint256 ethToAdd = ethBalanceAfter.sub(ethBalanceBefore);

        nativeToken.approve(address(router), amountToAdd);
        router.addLiquidityAVAX{value: ethToAdd}(address(nativeToken), amountToAdd, 0, 0, address(this), block.timestamp);

        uint256 lpTokensToDeposit = IERC20(poolToken).balanceOf(address(this));
        IERC20(poolToken).approve(address(masterchef), lpTokensToDeposit);
        masterchef.depositFor(_pid, lpTokensToDeposit, _referral, msg.sender);
    }

    function _zapInAvaxLP(uint256 _pid, address token0, address token1, address poolToken, uint256 amount) internal {
        address token;
        uint256 poolId = _pid;
        uint256 amountToSwap = (amount).div(2);
        uint256 amountLeft = (amount).sub(amountToSwap);

        if(address(token0) == address(wrappedAsset)) {
            token = token1;
            }
        else { token = token0; }

        address[] memory path = new address[](2);
        path[0] = address(wrappedAsset);
        path[1] = address(token);

        router.swapExactAVAXForTokens{value: amountToSwap}(0, path, address(this), block.timestamp);
        uint256 tokensReceived = IERC20(token).balanceOf(address(this));

        IERC20(token).approve(address(router), tokensReceived);
        router.addLiquidityAVAX{value: amountLeft}(address(token), tokensReceived, 0, 0, address(this), block.timestamp);
        uint256 lpTokensReceived = IERC20(poolToken).balanceOf(address(this));

        IUniPair(poolToken).approve(address(masterchef), lpTokensReceived);
        masterchef.depositFor(poolId, lpTokensReceived, referral, msg.sender);
    }

    function _zapInLP(uint256 _pid, address token0, address token1, address poolToken, uint256 amount) internal {
        uint256 poolId = _pid;
        uint256 amountToSwap = (amount).div(2);
        uint256 amountLeft = (amount).sub(amountToSwap);

        address[] memory path0 = new address[](2);
        path0[0] = address(wrappedAsset);
        path0[1] = address(token0);

        address[] memory path1 = new address[](2);
        path1[0] = address(wrappedAsset);
        path1[1] = address(token1);

        router.swapExactAVAXForTokens{value: amountToSwap}(0, path0, address(this), block.timestamp);
        uint256 token0Received = IERC20(token0).balanceOf(address(this));
        router.swapExactAVAXForTokens{value: amountLeft}(0, path1, address(this), block.timestamp);
        uint256 token1Received = IERC20(token0).balanceOf(address(this));

        IERC20(token0).approve(address(router), token0Received);
        IERC20(token1).approve(address(router), token1Received);
        router.addLiquidity(token0, token1, token0Received, token1Received, 0, 0, address(this), block.timestamp);
        uint256 lpTokensReceived = IERC20(poolToken).balanceOf(address(this));

        IUniPair(poolToken).approve(address(masterchef), lpTokensReceived);
        masterchef.depositFor(poolId, lpTokensReceived, referral, msg.sender);
    }

}