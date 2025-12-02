// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKYCProvider {
    /**
     * @dev 查询用户是否通过了合规验证 (ZK-Proof 或其他方式)
     * @param user 要查询的用户地址
     * @return bool 如果合规返回 true
     */
    function isCompliant(address user) external view returns (bool);
}