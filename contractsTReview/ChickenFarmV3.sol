// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./EggsV3.sol";
import "./IEGGS.sol";

import "hardhat/console.sol";
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

contract ChickenFarmV3 is Ownable {

    //Emit payment events

    event IERC20TransferEvent(IERC20 indexed token, address to, uint256 amount);
    event IERC20TransferFromEvent(IERC20 indexed token, address from, address to, uint256 amount);

    //SafeMathuse

    using SafeMath for uint256;

    //Variables

    IEGGS private eggs;
    IERC20 private usdc;
    IUniswapV2Pair private unipair;
    address public treasury;
    address private burn;

    uint256 ethPrice = 36;
    uint256 private dailyInterest;
    uint256 private chickenCost;
    uint256 private chickenBase;
    uint256 public bondDiscount;

    uint256 public claimTaxEggs = 8;
    uint256 public claimTaxBond = 12;
    uint256 public bondChickenStartTime;

    bool public isLive = false;
    uint256 totalChickens = 0;
    uint256 totalChickenHouses = 0;

    uint256 gmoFood = 12 hours;
    uint256 normalFood = 24 hours;
    uint256 organicFood = 72 hours;

    uint256 foodTypeFee = 0.1 ether;
    uint256 compoundFee = 0.1 ether;

    //Array

    address [] public farmersAddresses;

    //Farmers Struct

    struct Farmer {
        bool exists;
        uint256 chickens;
        uint256 eggsClaimed;
        uint256 lastClaimed;
    }

    struct ChickenHouse {
        uint256 id;
        uint256 chickens;
        uint256 creationDate;
        uint256 foodType;
    }

    //Mappings

    mapping(address => Farmer) private farmers;
    // Farmers ChickenHouses :
    mapping(address => ChickenHouse[]) private chickenHouses;


    event ChickenBought(address indexed user, uint256 amount, uint256 transactionTotal);
    event ChickenBond(address indexed user, uint256 amount, uint256 transactionTotal);
    event ChickenHouseCreated(address indexed user, uint256 amount, uint256 id);
    event ChickenAwarded(address indexed user, uint256 amount);
    event ClaimedEggs(address indexed user, uint256 amount);
    event FoodTypeChanged(address indexed user, uint256 id, uint256 foodType);
    event ChickenCompounded(address indexed user, uint256 chickensToAllocate);
    //Constructor

    constructor (
        address _eggs,        //Address of the $EGGS token to use in the platform
        address _usdc,          //Address of USDC stablecoin
        address _treasury,      //Address of a treasury wallet to hold fees and taxes
        uint256 _dailyInterest, //DailyInterest
        uint256 _chickenCost,      //Cost of a chicken in $EGGS
        uint256 _bondDiscount   //% of discount of the bonding      
    ) {
        eggs = IEGGS(_eggs);
        usdc = IERC20(_usdc);

        treasury = _treasury;
        dailyInterest = _dailyInterest;
        chickenCost = _chickenCost.mul(1e18);
        chickenBase = SafeMath.mul(10, 1e18);
        bondDiscount = _bondDiscount;
    }

    //Price Checking Functions

    function setPair(address _pair) public onlyOwner {
        unipair = IUniswapV2Pair(_pair);
    }

    function getPrice() public view returns (uint256) {
    
        (uint112 reserve0, uint112 reserve1, ) = unipair.getReserves();

        require(reserve0 > 0 && reserve1 > 0, "Reserves not available");

        uint256 price = (uint256(reserve0) * ethPrice * 1e18) / uint256(reserve1);
    
        return price;
    }   
    //Bond Setup

     function getBondCost() public view returns (uint256) {
         uint256 tokenPrice = getPrice();
         uint256 basePrice = chickenCost.mul(tokenPrice).div(1e18);

         uint256 discount = SafeMath.sub(100, bondDiscount);
         uint256 bondPrice = basePrice.mul(discount).div(100);

         // Convert the bondPrice from 18 decimals to 6 decimals
         return bondPrice.div(1e12);
     }

    // test function to get bond price

    // function getBondCost() public pure returns (uint256) {
    //     return 10 ether;
    // }

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

    function setBondChickenStartTime(uint256 _newStartTime) external onlyOwner {
        bondChickenStartTime = _newStartTime;
    }

    function setFoodTypeFee(uint256 _newFee) external onlyOwner {
        foodTypeFee = _newFee;
    }

    function setCompoundFee(uint256 _newFee) external onlyOwner {
        compoundFee = _newFee;
    }

    //Chicken management - Buy - Claim - Bond - User front

    function buyChicken(uint256 _amount) external payable {  
        require(isLive, "Platform is offline");
        uint256 chickensOwned = farmers[msg.sender].chickens + _amount;
        require(chickensOwned < 101, "Max Chickens Owned");
        uint256 transactionTotal = chickenCost.mul(_amount);
        require(eggs.balanceOf(msg.sender) >= transactionTotal, "Not enough $EGGS");

        Farmer memory farmer;
        if(farmers[msg.sender].exists){
            farmer = farmers[msg.sender];
        } else {
            createFarmer(msg.sender);
        }

        createChickenHouse(_amount, msg.sender);

        eggs.burn(msg.sender , transactionTotal);
        
        emit ChickenBought(msg.sender, _amount, transactionTotal);
    }

    function createFarmer(address _recipient) internal {
        Farmer memory farmer;
        farmer = Farmer(true, 0, 0, block.timestamp);
        farmers[_recipient] = farmer;
        farmersAddresses.push(_recipient);
    }

    function createChickenHouse(uint256 _chickenAmount, address _recipient) internal {
        ChickenHouse memory chickenHouse;
        totalChickenHouses++;
        // creating chickenHouse
        chickenHouse = ChickenHouse(totalChickenHouses, _chickenAmount, block.timestamp, 0);
        // adding chickenHouses
        chickenHouses[_recipient].push(chickenHouse);
        // adding chickens to farmer
        farmers[_recipient].chickens += _chickenAmount;
        // adding total chickens
        totalChickens += _chickenAmount;
        // adding chickenHouse id
        emit ChickenHouseCreated(_recipient, _chickenAmount, totalChickenHouses);
    }

    function bondChicken(uint256 _amount) external payable {
        require(isLive, "Platform is offline");
        require(block.timestamp >= bondChickenStartTime, "BondChicken not available yet");
        uint256 chickensOwned = farmers[msg.sender].chickens + _amount;
        require(chickensOwned < 101, "Max Chickens Owned");
        uint256 usdcAmount = getBondCost(); 
        uint256 transactionTotal = usdcAmount.mul(_amount);
        require(usdc.balanceOf(msg.sender) >= transactionTotal, "Not enough USDC");

        Farmer memory farmer;
        if(farmers[msg.sender].exists){
            farmer = farmers[msg.sender];
        } else {
            createFarmer(msg.sender);
        }

        createChickenHouse(_amount, msg.sender);

        _transferFrom(usdc, msg.sender, address(treasury), transactionTotal);

        emit ChickenBond(msg.sender, _amount, transactionTotal);
    }

    function awardChicken(address _address, uint256 _amount) public onlyOwner {
        uint256 chickensOwned = farmers[_address].chickens + _amount;
        require(chickensOwned < 101, "Max Chickens Owned");
        Farmer memory farmer;
        if(farmers[_address].exists){
            farmer = farmers[_address];
        } else {
            createFarmer(_address);
        }
        createChickenHouse(_amount, _address);

        emit ChickenAwarded(_address, _amount);
    }

    function compoundChicken() public payable {
        uint256 pendingReward = getTotalClaimable(msg.sender);
        uint256 chickensToAllocate = pendingReward.div(chickenCost);
        uint256 remainingEggs = pendingReward.mod(chickenCost);
        uint256 chickensOwned = farmers[msg.sender].chickens + chickensToAllocate;

        require(chickensToAllocate > 0, "Not enough $EGGS");
        require(chickensOwned < 100, "Max Chickens Owned");
        require(msg.value >= 0.1 ether, "Invalid fee");

        updateChickenHouses(msg.sender); 
        createChickenHouse(chickensToAllocate, msg.sender);

        farmers[msg.sender].lastClaimed = block.timestamp;
        eggs.mint(msg.sender, remainingEggs);
        emit ChickenCompounded(msg.sender, chickensToAllocate);
    }
    
    function getTotalClaimable(address _user) public view returns (uint256) {
        uint256 lastClaimed = farmers[_user].lastClaimed;
        uint256 time = block.timestamp;
        // Calculate the decreasing APR factor
        uint256 pending;
        
        for (uint i = 0; i < chickenHouses[_user].length; i++) {

            uint256 chickenHouseTimeElapsed = time.sub(chickenHouses[_user][i].creationDate);
            uint256 timeElapsed = time.sub(lastClaimed);
            uint256 chickens = chickenHouses[_user][i].chickens;
            uint256 foodType = chickenHouses[_user][i].foodType;
            // If chickenHouse is older than 6 hours, skip it no rewards
            if (timeElapsed > chickenHouseTimeElapsed) {
                timeElapsed = chickenHouseTimeElapsed;
            } 

            pending += calculateChickenHouseReward(chickens,
                                                   foodType,
                                                   chickenHouseTimeElapsed,
                                                   timeElapsed);
        }
        return pending;
    }

    function calculateChickenHouseReward(
        uint256 _chickens,
        uint256 _foodType,
        uint256 _chickenHouseTimeElapsed,
        uint256 _timeElapsed)
        public
        view
        returns (uint256) 
    {
        // Default life expectancy and daily APR
        uint256 lifeExpectancy = normalFood;
        uint256 dailyAPR = 110;

        // Adjusting life expectancy and daily APR based on foodType
        if (_foodType == 1) {
            lifeExpectancy = gmoFood;
        } else if (_foodType == 2) {
            lifeExpectancy = organicFood;
            dailyAPR = 40;
        }

        // Check if within life expectancy
        if (_chickenHouseTimeElapsed < lifeExpectancy) {
            uint256 pendingEggs = _chickens
                                .mul(chickenBase)
                                .mul(dailyAPR)
                                .mul(_timeElapsed)
                                .div(8640000); // APR divisor for percentage calculation

            // Adjusting reward based on foodType
            if (_foodType == 1) {
                pendingEggs = pendingEggs.mul(250).div(100); // Multiply reward by 2.5
            }

            return pendingEggs;
        } else {
            return 0;
        }
    }

    function claim() external payable {
        require(msg.sender == tx.origin, "Sender must be the origin");
        require(farmers[msg.sender].exists, "sender must be registered farmer to claim yields");
        uint256 pendingReward = getTotalClaimable(msg.sender);
        updateChickenHouses(msg.sender); 
		if (pendingReward > 0) {
            farmers[msg.sender].lastClaimed = block.timestamp;
            eggs.mint(msg.sender, pendingReward);
		}
        emit ClaimedEggs(msg.sender, pendingReward);
	}

    function updateChickenHouses(address _user) internal {
        uint256 time = block.timestamp;
        uint256 i = 0;

        while (i < chickenHouses[_user].length) {
            uint256 timeElapsed = time - chickenHouses[_user][i].creationDate;
            uint256 foodType = chickenHouses[_user][i].foodType;
            uint256 lifeExpectancy = normalFood;

            // Adjusting life expectancy and daily APR based on foodType
            if (foodType == 1) {
                lifeExpectancy = gmoFood;
            } else if (foodType == 2) {
                lifeExpectancy = organicFood;
            }

            // Delete ChickenHouse if it's older than 6 hours
            if (timeElapsed > lifeExpectancy) {
                uint256 expiredChickens = chickenHouses[_user][i].chickens;
                // Decrease farmer's chickens
                farmers[_user].chickens -= expiredChickens;
                // Move the last element to the current index
                chickenHouses[_user][i] = chickenHouses[_user][chickenHouses[_user].length - 1];
                // Remove the last element
                chickenHouses[_user].pop();
                // Decrease total chickenHouses
                totalChickenHouses--;
            } else {
                // Only increment if no deletion was made
                i++;
            }
        }
    }
    
    function contains(ChickenHouse[] memory array, uint256 value) public view returns(uint256) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i].id == value) {
                return i;
            }
        }
    }

    function changeFoodType(uint256 _chickenHouseId, uint256 _foodType) external payable {
        require(isLive, "Platform is offline");
        require(msg.sender == tx.origin, "Sender must be the origin");

        require(_foodType == 1 || _foodType == 2, "Invalid food type");

        uint256 index = contains(chickenHouses[msg.sender], _chickenHouseId);
        ChickenHouse memory chickenHouse = chickenHouses[msg.sender][index];
        require(chickenHouse.id == _chickenHouseId, "Chicken house does not exist");

        require(chickenHouse.foodType == 0, "Food type already set");
        require(chickenHouse.creationDate + 3600 > block.timestamp, "Chickens are too old");

        require(msg.value == foodTypeFee, "Invalid fee");

        chickenHouses[msg.sender][index].foodType = _foodType;

        emit FoodTypeChanged(msg.sender, _chickenHouseId, _foodType);
    }

    function withdrawFee() public onlyOwner {
        uint256 ethBalance = address(this).balance;
        payable(msg.sender).transfer(ethBalance);
    }

    function getChickenHousesIds(address _user) external view returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](chickenHouses[_user].length);
        for (uint256 i = 0; i < chickenHouses[_user].length; i++) {
            ids[i] = chickenHouses[_user][i].id;
        }
        return ids;
    }

    //Platform Info

    function currentDailyRewards() external view returns (uint256) {
        uint256 dailyRewards = chickenBase.mul(dailyInterest).div(100);
        return dailyRewards;
    }

    function getOwnedChickens(address user) public view returns (uint256) {
        uint256 ownedChickens = farmers[user].chickens;
        return ownedChickens;
    }

    function getTotalChickens() external view returns (uint256) {
        return totalChickens;
    }

    //SafeERC20 transferFrom 

    function _transferFrom(IERC20 token, address from, address to, uint256 amount) private {
        SafeERC20.safeTransferFrom(token, from, to, amount);

    //Log transferFrom to blockchain
        emit IERC20TransferFromEvent(token, from, to, amount);
    }
    
    function withdrawAvax() public onlyOwner {
        uint256 avaxBalance = address(this).balance;
        payable(msg.sender).transfer(avaxBalance);
    }

    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) public onlyOwner {
        require(to != address(0), "Rescue to the zero address");
        require(token != address(0), "Rescue of the zero address");
        
        // transfer to
        SafeERC20.safeTransfer(IERC20(token),to, amount);
    }
    
    receive() external payable {}
}


