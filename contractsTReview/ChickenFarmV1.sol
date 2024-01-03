// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Eggs.sol";
import "./IEGGS.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

contract ChickenFarm is Ownable {

    //Emit payment events

    event IERC20TransferEvent(IERC20 indexed token, address to, uint256 amount);
    event IERC20TransferFromEvent(IERC20 indexed token, address from, address to, uint256 amount);

    //SafeMathuse

    using SafeMath for uint256;


    //Variables

    IEGGS private eggs;
    IERC20 private usdc;
    IUniswapV2Pair private unipair;
    address private pair;
    address public treasury;
    address private burn;

    uint256 ethPrice = 36;
    uint256 private dailyInterest;
    uint256 private nodeCost;
    uint256 private nodeBase;
    uint256 public bondDiscount;

    uint256 public claimTaxEggs = 8;
    uint256 public claimTaxBond = 12;
    uint256 public bondNodeStartTime;

    bool public isLive = false;
    uint256 totalNodes = 0;

    //Array

    address [] public farmersAddresses;

    //Farmers Struct

    struct Farmer {
        bool exists;
        uint256 eggsNodes;
        uint256 bondNodes;
        uint256 claimsEggs;
        uint256 claimsBond;
        uint256 lastUpdate;
        
    }

    //Mappings

    mapping(address => Farmer) private farmers;

    //Constructor

    constructor (
        address _eggs,        //Address of the $EGGS token to use in the platform
        address _usdc,          //Address of USDC stablecoin
        address _pair,          //Address of the liquidity pool 
        address _treasury,      //Address of a treasury wallet to hold fees and taxes
        uint256 _dailyInterest, //DailyInterest
        uint256 _nodeCost,      //Cost of a node in $EGGS
        uint256 _bondDiscount   //% of discount of the bonding      
    ) {
        eggs = IEGGS(_eggs);
        unipair = IUniswapV2Pair(_pair);
        usdc = IERC20(_usdc);

        pair = _pair;
        treasury = _treasury;
        dailyInterest = _dailyInterest;
        nodeCost = _nodeCost.mul(1e18);
        nodeBase = SafeMath.mul(10, 1e18);
        bondDiscount = _bondDiscount;
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
        return bondPrice;
    }

    function setBondDiscount(uint256 newDiscount) public onlyOwner {
        require(newDiscount <= 75, "Discount above limit");
        bondDiscount = newDiscount;
    }

    //Set Addresses

    function setTreasuryAddr(address treasuryAddress) public onlyOwner {
        treasury = treasuryAddress;
    }
    function setEggsAddr(address eggsaddress) public onlyOwner {
        eggs = IEGGS(eggsaddress);
    }
    function setEggsTax(uint256 _claimTaxEggs) public onlyOwner {
        claimTaxEggs = _claimTaxEggs;
    }

    function setBondTax(uint256 _claimTaxBond) public onlyOwner {
        claimTaxBond = _claimTaxBond;
    }

    //Platform Settings

    function setPlatformState(bool _isLive) public onlyOwner {
        isLive = _isLive;
    }

    function setEthPrice(uint256 _ethPrice) public onlyOwner {
        ethPrice = _ethPrice;
    }
    function setDailyInterest(uint256 _dailyInterest) public onlyOwner {
        dailyInterest = _dailyInterest;
    }


    function updateAllClaims() internal {
        uint256 i;
        for(i=0; i<farmersAddresses.length; i++){
            address _address = farmersAddresses[i];
            updateClaims(_address);
        }
    }
    

    function setBondNodeStartTime(uint256 _newStartTime) external onlyOwner {
    bondNodeStartTime = _newStartTime;
}

    //Node management - Buy - Claim - Bond - User front

    function buyNode(uint256 _amount) external payable {  
        require(isLive, "Platform is offline");
        uint256 nodesOwned = farmers[msg.sender].eggsNodes + farmers[msg.sender].bondNodes + _amount;
        require(nodesOwned < 101, "Max Chickens Owned");
        Farmer memory farmer;
        if(farmers[msg.sender].exists){
            farmer = farmers[msg.sender];
        } else {
            farmer = Farmer(true, 0, 0, 0, 0, 0);
            farmersAddresses.push(msg.sender);
        }
        uint256 transactionTotal = nodeCost.mul(_amount);
        eggs.burn(msg.sender , transactionTotal);
        farmers[msg.sender] = farmer;
        updateClaims(msg.sender);
        farmers[msg.sender].eggsNodes += _amount;
        totalNodes += _amount;
    }

    function bondNode(uint256 _amount) external payable {
        require(isLive, "Platform is offline");
        require(block.timestamp >= bondNodeStartTime, "BondNode not available yet");
        uint256 nodesOwned = farmers[msg.sender].eggsNodes + farmers[msg.sender].bondNodes + _amount;
        require(nodesOwned < 101, "Max Chickens Owned");
        Farmer memory farmer;
        if(farmers[msg.sender].exists){
            farmer = farmers[msg.sender];
        } else {
            farmer = Farmer(true, 0, 0, 0, 0, 0);
            farmersAddresses.push(msg.sender);
        }
        uint256 usdcAmount = getBondCost(); 
        uint256 transactionTotal = usdcAmount.mul(_amount);
        _transferFrom(usdc, msg.sender, address(treasury), transactionTotal);
        farmers[msg.sender] = farmer;
        updateClaims(msg.sender);
        farmers[msg.sender].bondNodes += _amount;
        totalNodes += _amount;
    }

    function awardNode(address _address, uint256 _amount) public onlyOwner {
        uint256 nodesOwned = farmers[_address].eggsNodes + farmers[_address].bondNodes + _amount;
        require(nodesOwned < 101, "Max Chickens Owned");
        Farmer memory farmer;
        if(farmers[_address].exists){
            farmer = farmers[_address];
        } else {
            farmer = Farmer(true, 0, 0, 0, 0, 0);
            farmersAddresses.push(_address);
        }
        farmers[_address] = farmer;
        updateClaims(_address);
        farmers[_address].eggsNodes += _amount;
        totalNodes += _amount;
        farmers[_address].lastUpdate = block.timestamp;
    }

    function compoundNode() public {
        uint256 pendingClaims = getTotalClaimable(msg.sender);
        uint256 nodesOwned = farmers[msg.sender].eggsNodes + farmers[msg.sender].bondNodes;
        require(pendingClaims>nodeCost, "Not enough pending eggsEggs to compound");
        require(nodesOwned < 100, "Max Chickens Owned");
        updateClaims(msg.sender);
        if (farmers[msg.sender].claimsEggs > nodeCost) {
            farmers[msg.sender].claimsEggs -= nodeCost;
            farmers[msg.sender].eggsNodes++;
        } else {
            uint256 difference = nodeCost - farmers[msg.sender].claimsEggs;
            farmers[msg.sender].claimsEggs = 0;
            farmers[msg.sender].claimsBond -= difference;
            farmers[msg.sender].bondNodes++;
        }
        totalNodes++;
    }

    function updateClaims(address _address) internal {
        uint256 time = block.timestamp;
        uint256 timerFrom = farmers[_address].lastUpdate;
        if (timerFrom > 0)
            farmers[_address].claimsEggs += farmers[_address].eggsNodes.mul(nodeBase).mul(dailyInterest).mul((time.sub(timerFrom))).div(8640000);
            farmers[_address].claimsBond += farmers[_address].bondNodes.mul(nodeBase).mul(dailyInterest).mul((time.sub(timerFrom))).div(8640000);
            farmers[_address].lastUpdate = time;
    }

    function getTotalClaimable(address _user) public view returns (uint256) {
        uint256 time = block.timestamp;
        uint256 pendingEggs = farmers[_user].eggsNodes.mul(nodeBase).mul(dailyInterest).mul((time.sub(farmers[_user].lastUpdate))).div(8640000);
        uint256 pendingBond = farmers[_user].bondNodes.mul(nodeBase.mul(dailyInterest.mul((time.sub(farmers[_user].lastUpdate))))).div(8640000);
        uint256 pending = pendingEggs.add(pendingBond);
        return farmers[_user].claimsEggs.add(farmers[_user].claimsBond).add(pending);
	}

    function getTaxEstimate() external view returns (uint256) {
        uint256 time = block.timestamp;
        uint256 pendingEggs = farmers[msg.sender].eggsNodes.mul(nodeBase).mul(dailyInterest).mul((time.sub(farmers[msg.sender].lastUpdate))).div(8640000);
        uint256 pendingBond = farmers[msg.sender].bondNodes.mul(nodeBase).mul(dailyInterest).mul((time.sub(farmers[msg.sender].lastUpdate))).div(8640000);
        uint256 claimableEggs = pendingEggs.add(farmers[msg.sender].claimsEggs); 
        uint256 claimableBond = pendingBond.add(farmers[msg.sender].claimsBond); 
        uint256 taxEggs = claimableEggs.div(100).mul(claimTaxEggs);
        uint256 taxBond = claimableBond.div(100).mul(claimTaxBond);
        return taxEggs.add(taxBond);
	}

    function calculateTax() public returns (uint256) {
        updateClaims(msg.sender); 
        uint256 taxEggs = farmers[msg.sender].claimsEggs.div(100).mul(claimTaxEggs);
        uint256 taxBond = farmers[msg.sender].claimsBond.div(100).mul(claimTaxBond);
        uint256 tax = taxEggs.add(taxBond);
        return tax;
    }


    function claim() external payable {

    //Ensure msg.sender is sender

        require(farmers[msg.sender].exists, "sender must be registered farmer to claim yields");

        uint256 tax = calculateTax();
		uint256 reward = farmers[msg.sender].claimsEggs.add(farmers[msg.sender].claimsBond);
        uint256 toBurn = tax;
        uint256 toFarmer = reward.sub(tax);
		if (reward > 0) {
            farmers[msg.sender].claimsEggs = 0;		
            farmers[msg.sender].claimsBond = 0;
            eggs.mint(msg.sender, toFarmer);
            eggs.burn(msg.sender, toBurn);
		}
	}

    //Platform Info

    function currentDailyRewards() external view returns (uint256) {
        uint256 dailyRewards = nodeBase.mul(dailyInterest).div(100);
        return dailyRewards;
    }

    function getOwnedNodes(address user) external view returns (uint256) {
        uint256 ownedNodes = farmers[user].eggsNodes.add(farmers[user].bondNodes);
        return ownedNodes;
    }

    function getTotalNodes() external view returns (uint256) {
        return totalNodes;
    }

    //SafeERC20 transferFrom 

    function _transferFrom(IERC20 token, address from, address to, uint256 amount) private {
        SafeERC20.safeTransferFrom(token, from, to, amount);

    //Log transferFrom to blockchain
        emit IERC20TransferFromEvent(token, from, to, amount);
    }

}