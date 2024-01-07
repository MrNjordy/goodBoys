// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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
    IJoeRouter public router;

    constructor (
        address _masterchef,
        address _wrappedAsset,
        address _router
    ) {
        masterchef = IMasterchef(_masterchef);
        wrappedAsset = IERC20(_wrappedAsset);
        router = IJoeRouter(_router);
    }

    function zapper(uint256 _pid, address _referral) public payable {
        (address poolToken,,,,) = masterchef.poolInfo(_pid);
        address token;
        uint256 poolId = _pid;
        address referral = _referral;

        address token0 = IUniPair(poolToken).token0();
        address token1 = IUniPair(poolToken).token1();

        if(address(token0) == address(wrappedAsset)) {
            token = token1;
        }
        else { token = token0; }

        uint256 amountToSwap = (msg.value).div(2);
        uint256 amountLeft = (msg.value).sub(amountToSwap);

        address[] memory path = new address[](2);
        path[0] = address(wrappedAsset);
        path[1] = address(token);

        uint256 tokenBalanceBefore = IERC20(token).balanceOf(address(this));
        router.swapExactAVAXForTokens{value: amountToSwap}(0, path, address(this), block.timestamp);
        uint256 tokenBalanceAfter = IERC20(token).balanceOf(address(this));
        uint256 tokensReceived = tokenBalanceAfter.sub(tokenBalanceBefore);

        uint256 lpTokensBefore = IERC20(poolToken).balanceOf(address(this));
        IERC20(token).approve(address(router), tokensReceived);
        router.addLiquidityAVAX{value: amountLeft}(address(token), tokensReceived, 0, 0, address(this), block.timestamp);
        uint256 lpTokensAfter = IERC20(poolToken).balanceOf(address(this));
        uint256 lpTokensReceived = lpTokensAfter.sub(lpTokensBefore);
        
        IUniPair(poolToken).approve(address(masterchef), lpTokensReceived);
        masterchef.depositFor(poolId, lpTokensReceived, referral, msg.sender);
    }

}