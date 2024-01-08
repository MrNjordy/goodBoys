// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IMasterchef {
    function poolInfo(uint256 pid) external pure returns (address, uint256, uint256, uint256, uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function depositFor(uint256 _pid, uint256 _amount, address referral, address forWho) external;
    function pendingRewards(uint256 _pid, address _user) external view returns(uint256);
}

