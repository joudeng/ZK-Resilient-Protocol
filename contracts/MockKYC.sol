// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IKYCProvider.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockKYC is IKYCProvider, Ownable {
    
    // 简单的白名单映射
    mapping(address => bool) public whitelist;

    event KYCStatusChanged(address indexed user, bool status);

    constructor() Ownable(msg.sender) {}

    // --- 演示专用功能 ---
    
    // 模拟用户通过了 ZK 验证，将其加入白名单
    function setStatus(address user, bool status) external onlyOwner {
        whitelist[user] = status;
        emit KYCStatusChanged(user, status);
    }

    // 批量设置 (方便初始化测试账号)
    function batchSetStatus(address[] calldata users, bool status) external onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            whitelist[users[i]] = status;
            emit KYCStatusChanged(users[i], status);
        }
    }

    // --- 接口实现 ---
    function isCompliant(address user) external view override returns (bool) {
        // 默认策略：如果是 0 地址(Mint/Burn)，永远合规；否则查表
        if (user == address(0)) return true;
        return whitelist[user];
    }
}