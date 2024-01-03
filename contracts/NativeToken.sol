// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/SafeMath.sol";

contract NativeToken is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 public constant maxSupply = 1_000_000_000e18;

    constructor(address initialOwner) Ownable(initialOwner) ERC20("Name", "Symbol") {
        _mint(msg.sender, 100_000e18);
    }
    /// @notice Creates `_amount` token to token address. Must only be called by the owner (MasterChef).
    function mint(uint256 _amount) public onlyOwner returns (bool) {
        return mintFor(address(this), _amount);
    }

    function mintFor(
        address _address,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        _mint(_address, _amount);
        require(totalSupply() <= maxSupply, "reach max supply");
        return true;
    }

    // Safe transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 nativeBal = balanceOf(address(this));
        if (_amount > nativeBal) {
            _transfer(address(this), _to, nativeBal);
        } else {
            _transfer(address(this), _to, _amount);
        }
    }
}