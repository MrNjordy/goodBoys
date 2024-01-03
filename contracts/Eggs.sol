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

    function addLiquidity(
        address tokenA, 
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

contract EGGS is IEGGS, ERC20, Ownable {
    uint256 private initialSupply;
    uint256 public maxSupply;
    address public uniswapPair;
    IUniswapV2Router02 private uniswapRouter;

    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    mapping(address => bool) private isController;

    bool public tradingEnabled = false;
    address public treasuryAddress;
    uint256 public maxTransactionPercent = 1;
    uint256 private maxTransactionAmount;

    constructor(uint256 _initialSupply, uint256 _maxSupply, address _treasuryAddress) ERC20("EGGS", "EGGS") {
        IUniswapV2Router02 _uniswapRouter = IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        uniswapRouter = _uniswapRouter;
        uniswapPair = IUniswapV2Factory(_uniswapRouter.factory())
        .createPair(address(this), 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
        initialSupply = _initialSupply;
        maxSupply = _maxSupply;
        treasuryAddress = _treasuryAddress;
        isController[msg.sender] = true;
        _mint(msg.sender, initialSupply);
        maxTransactionAmount = initialSupply.mul(maxTransactionPercent).div(100);
    }

    function mint(address to_, uint256 amount_) external override onlyController {
        require(totalSupply().add(amount_) <= maxSupply, "Maximum supply reached");
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) external override onlyController {
        _burn(from_, amount_);
    }

    function checkMaxTransaction(address from, uint256 amount) internal view {
        require(amount <= maxTransactionAmount || isController[from], "Exceeds maximum transaction amount");
    }

    function removeLimits() external onlyOwner {
        maxTransactionPercent = 100; 
        maxTransactionAmount = type(uint256).max; 
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

    function pause_trading() public onlyOwner {
        tradingEnabled = false;
    }

    function enable_trading() public onlyOwner {
        tradingEnabled = true;
    }
    function getPair() public view returns (address) {
         return uniswapPair;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(tradingEnabled || from == owner(), "Transfer is disabled");
        checkMaxTransaction(from, amount);
        ERC20._transfer(from, to, amount);
    }
}