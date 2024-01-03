// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IEGGS.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}
 
interface IUniswapV2Router02 {
 
    function factory() external pure returns (address);

     function addLiquidityAVAX(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountAVAX,
            uint256 liquidity
        );

    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;


    function WAVAX() external pure returns (address);
}

contract EGGSV3 is IEGGS, ERC20, Ownable {
    uint256 private initialSupply;
    uint256 public maxSupply;
    address public uniswapPair;
    IUniswapV2Router02 private uniswapRouter;

    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    mapping(address => bool) private isController;

    bool public tradingEnabled = false;
    address public treasuryAddress;
    uint256 public taxPercent = 1;
    address public deployerWallet;
    bool private inSwap;
    uint256 public maxWallet = 1200 * 10 ** 18;
    uint256 public swapThreshold = 1000 * 10**18;
    bool public launchGuard = true;
    mapping(address => bool) public excludedFromTax;
    mapping(address => bool) public marketPairs;

    constructor(uint256 _initialSupply, uint256 _maxSupply, address _treasuryAddress) ERC20("EGGS", "EGGSV3") {
         //IUniswapV2Router02 _uniswapRouter = IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
         //uniswapRouter = _uniswapRouter;
        // uniswapPair = IUniswapV2Factory(_uniswapRouter.factory())
        //   .createPair(address(this), 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
        initialSupply = _initialSupply;
        maxSupply = _maxSupply;
        treasuryAddress = _treasuryAddress;
        isController[msg.sender] = true;
        excludedFromTax[msg.sender] = true;
        deployerWallet = msg.sender;
        _mint(msg.sender, initialSupply);

        
        _approve(address(this), address(msg.sender), type(uint256).max);
        
    }

    function mint(address to_, uint256 amount_) external override onlyController {
        require(totalSupply().add(amount_) <= maxSupply, "Maximum supply reached");
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) external override onlyController {
        _burn(from_, amount_);
    }

    event ControllerAdded(address newController);

    function addController(address toAdd_) external onlyOwner {
        isController[toAdd_] = true;
        emit ControllerAdded(toAdd_);
    }

    event ControllerRemoved(address controllerRemoved);

    function removeController(address toRemove_) external onlyOwner {
        isController[toRemove_] = false;
        emit ControllerRemoved(toRemove_);
    }

    modifier onlyController() {
        require(isController[_msgSender()], "CallerNotController");
        _;
    }
    modifier tradingLock(address from) {
        require(tradingEnabled || from == deployerWallet, "Token: Trading is not active.");
        _;
    }

    function pause_trading() public onlyOwner {
        tradingEnabled = false;
    }

    function enable_trading() public onlyOwner {
        tradingEnabled = true;
    }
    function getPair() public view returns (address) {
         return uniswapPair;
    }

     function transfer(address to, uint256 value)
        public
        override(ERC20, IERC20)
        tradingLock(msg.sender)
        returns (bool)
    {
        require(value <= balanceOf(msg.sender), "Not enough tokens");
        return _transferFrom(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, IERC20) tradingLock(from) returns (bool) {
        require(value <= balanceOf(from), "Not enough tokens");
        _spendAllowance(from,msg.sender, value);
        return _transferFrom(from, to, value);
    }

    function _transferFrom(
        address from,
        address to,
        uint256 value
    ) internal returns (bool) {
        if(inSwap){ return _basicTransfer(from, to, value); }  

        if(marketPairs[to]) {
            uint256 contractBalance = balanceOf(address(this));
            if(contractBalance >= swapThreshold) {
                swapBack();
                // send the ETH to the taxAddress
            }
        }  

        if (marketPairs[to] || marketPairs[from]) {
            // amount can't be more than 1% of the initial supply 

            if(excludedFromTax[to] || excludedFromTax[from]) {
                _basicTransfer(from, to, value);
                return true;
            }

            uint256 eggsTaxAmount = value.mul(taxPercent).div(100);


            _transfer(from, address(this), eggsTaxAmount);        
            uint256 eggsToTransfer = value.sub(eggsTaxAmount);

            if(marketPairs[to]) {
                require(value <= initialSupply.div(100), "Can't sell more than 1% of the supply at once");
            }
            else if(marketPairs[from]) {
                require(value <= initialSupply.div(20), "Can't buy more than 5% of the supply at once");
                if(launchGuard == true){ 
                    require(value <= initialSupply.div(100), "Can't buy more than 1% of the supply at once");
                    require(balanceOf(to).add(value) <= maxWallet, "Max tokens per wallet reached");
                }
            }
            _transfer(from, to, eggsToTransfer);
        } else {
            _transfer(from, to, value);
        }
        return true;
    }

    function _basicTransfer(address from, address to, uint256 value) internal returns (bool) {
        _transfer(from, to, value);
        emit Transfer(from, to, value);
        return true;
    }

    function setMarketPairs(address account, bool _marketPair) public onlyOwner {
        // exclude address from tax
        marketPairs[account] = _marketPair;
    }

    function setExcludedFromTax(address account, bool _excluded) public onlyOwner {
        // exclude address from tax
        excludedFromTax[account] = _excluded;
    }

    function removeLaunchGuard() public onlyOwner{
        launchGuard = false;
    }

    function setSwapThreshold(uint256 _swapThreshold) public onlyOwner {
        //set swapThreshold
        swapThreshold = _swapThreshold;
    }
    function setMaxWallet(uint256 _maxWallet) public onlyOwner {
        //set maxWallet
        maxWallet = _maxWallet;
    }


    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }
    
    function setIUniswapV2Router02(address _router) public onlyOwner {
        IUniswapV2Router02 _uniswapRouter = IUniswapV2Router02(_router);
        uniswapRouter = _uniswapRouter;
        uniswapPair = IUniswapV2Factory(_uniswapRouter.factory())
          .createPair(address(this), _uniswapRouter.WAVAX());
        _approve(address(this), address(uniswapRouter), type(uint256).max);
        
    }

    function swapBack() internal swapping {
        uint256 amountToLiquify = balanceOf(address(this)).div(2);
        uint256 balanceBefore = address(this).balance;
        uint256 toSwap = balanceOf(address(this)).sub(amountToLiquify);
        swapTokensForAvax(toSwap);
        uint256 amountAVAX = address(this).balance.sub(balanceBefore);
        uint256 amountAVAXLiquidity = amountAVAX.div(2); 

        
        if (amountToLiquify > 0) {
            uniswapRouter.addLiquidityAVAX{value: amountAVAXLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                deployerWallet,
                block.timestamp
            );
        }
    }

    function swapTokensForAvax(uint256 contractBalance) private {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WAVAX();

        // make the swap
        uniswapRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            contractBalance,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    receive() external payable {}
}
