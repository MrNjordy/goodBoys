// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IChickenFarm.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

contract ChickenFarmV2 is Ownable {

    //Emit payment events

    event IERC20TransferEvent(IERC20 indexed token, address to, uint256 amount);
    event IERC20TransferFromEvent(IERC20 indexed token, address from, address to, uint256 amount);

    //SafeMathuse

    using SafeMath for uint256;


    //Variables

    IERC20 private usdc;
    IUniswapV2Pair private unipair;
    IChickenFarm public chickenFarmV1;

    address private pair;
    address public treasury;
    address private burn;

    uint256 ethPrice = 36;
    uint256 private nodeCost;
    uint256 public bondDiscount;


    bool public isLive = false;


    //Constructor

    constructor (
        address _usdc,          //Address of USDC stablecoin
        address _pair,          //Address of the liquidity pool 
        address _treasury,      //Address of a treasury wallet to hold fees and taxes
        uint256 _nodeCost,      //Cost of a node in $EGGS
        uint256 _bondDiscount,   //% of discount of the bonding  
        address _chickenFarmV1  //Address of the ChickenFarmV1 contract 
    ) {
        unipair = IUniswapV2Pair(_pair);
        usdc = IERC20(_usdc);

        pair = _pair;
        treasury = _treasury;
        nodeCost = _nodeCost.mul(1e18);
        bondDiscount = _bondDiscount;
        chickenFarmV1 = IChickenFarm(_chickenFarmV1);
    }

    //Price Checking Functions

    function getPrice() public view returns (uint256) {
    
        (uint112 reserve0, uint112 reserve1, ) = unipair.getReserves();

        require(reserve0 > 0 && reserve1 > 0, "Reserves not available");

        uint256 price = (uint256(reserve1) * ethPrice * 1e18) / uint256(reserve0);
        
        return price;
    }
    //Bond Setup

    function getBondCost() public view returns (uint256) {
        uint256 tokenPrice = getPrice();
        uint256 basePrice = nodeCost.mul(tokenPrice).div(1e18);

        uint256 discount = SafeMath.sub(100, bondDiscount);
        uint256 bondPrice = basePrice.mul(discount).div(100);

        // Convert the bondPrice from 18 decimals to 6 decimals
        return bondPrice.div(1e12);
    }

    //Set Addresses

    function setTreasuryAddr(address treasuryAddress) public onlyOwner {
        treasury = treasuryAddress;
        chickenFarmV1.setTreasuryAddr(treasuryAddress);
    }

    //Platform Settings

    function setPlatformState(bool _isLive) public onlyOwner {
        isLive = _isLive;
    }

    function setChickenFarmV1State(bool _isLive) public onlyOwner {
        chickenFarmV1.setPlatformState(_isLive);
    }

    function setEthPrice(uint256 _ethPrice) public onlyOwner {
        ethPrice = _ethPrice;
        chickenFarmV1.setEthPrice(_ethPrice);
    }

    //Node management - Buy - Claim - Bond - User front

    function bondNode(uint256 _amount) external payable {
        require(isLive, "Platform is offline");

        uint256 usdcAmount = getBondCost(); 
        uint256 transactionTotal = usdcAmount.mul(_amount);
        _transferFrom(usdc, msg.sender, address(treasury), transactionTotal);
        chickenFarmV1.awardNode(msg.sender, _amount);
    }

    //SafeERC20 transferFrom 

    function _transferFrom(IERC20 token, address from, address to, uint256 amount) private {
        SafeERC20.safeTransferFrom(token, from, to, amount);

    //Log transferFrom to blockchain
        emit IERC20TransferFromEvent(token, from, to, amount);
    }

    function transferOwnershipChickenFarmV1(address newOwner) public onlyOwner {
        chickenFarmV1.transferOwnership(newOwner);      
    }

}