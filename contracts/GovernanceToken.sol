// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceToken is ERC20, ERC20Burnable, Ownable {
    
    constructor(address initialOwner) ERC20("Resilient Governance", "RES") Ownable(initialOwner) {
        // 初始铸造 1000 万代币给部署者 (用于分发给审计员测试)
        _mint(initialOwner, 10000000 * 10**decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}