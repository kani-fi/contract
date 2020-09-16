pragma solidity ^0.5.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./WETH.sol";

contract KaniTest is Ownable {
    IERC20 public pool0 = IERC20(0x09605d1118B4C5C013Fae56730188dA48A769ab6);

    function totalSupply() public onlyOwner view returns (uint256) {
        return pool0.totalSupply();
    }

    function supply(address account) public onlyOwner view returns (uint256) {
        return pool0.balanceOf(account);
    }

    // weth
    WETH9_ public weth = WETH9_(0xd0A1E359811322d97991E03f863a0C30C2cF029C);

    function() external payable {
        weth.deposit.value(msg.value)();
        // weth.deposit();
    }
}