// SPDX-License-Identifier: BSD-3-Clause
//   ::   .:      ...   :::::::::::: .::::::..::    .   .::::::.  ::::::::::.
//  ,;;   ;;,  .;;;;;;;.;;;;;;;;'''';;;`    `';;,  ;;  ;;;' ;;`;;  `;;;```.;;;
// ,[[[,,,[[[ ,[[     \[[,   [[     '[==/[[[[,'[[, [[, [[' ,[[ '[[, `]]nnn]]'
// "$$$"""$$$ $$$,     $$$   $$       '''    $  Y$c$$$c$P c$$$cc$$$c $$$""
//  888   "88o"888,_ _,88P   88,     88b    dP   "88"888   888   888,888o
//  MMM    YMM  "YMMMMMP"    MMM      "YMmMY"     "M "M"   YMM   ""` YMMMb

pragma solidity ^0.8.25;

import "./Ownable.sol";
import "./interfaces/ERC20.sol";
import "./interfaces/ERC721.sol";
import "./HotswapPair.sol";

contract HotswapLiquidity is HotswapPair {
    address public controller;

    modifier onlyAuthorized() {
        require(msg.sender == _owner || msg.sender == controller);
        _;
    }

    constructor(address nft, address fft) HotswapPair(nft, fft) {}

    function nftBalance() external view returns (uint256) {
        return _nft.balanceOf(address(this));
    }

    function fftBalance() external view returns (uint256) {
        return _fft.balanceOf(address(this));
    }

    function withdrawFFT(uint256 amount, address dest) external onlyAuthorized {
        if (amount == 0) return;

        require(_fft.transfer(dest, amount), "Withdrawal failed");
        emit WithdrawFFT(amount, dest);
    }

    function withdrawNFT(uint256 amount, address dest) external onlyAuthorized {
        if (amount == 0) return;

        uint256 tokenId;
        bytes memory data = new bytes(0);

        for (uint256 i = amount; i > 0; i--) {
            tokenId = _nft.tokenOfOwnerByIndex(address(this), i - 1);
            _nft.safeTransferFrom(address(this), dest, tokenId, data);
        }

        emit WithdrawNFT(amount, dest);
    }

    function setController(address addr) external onlyOwner {
        controller = addr;
    }

    event WithdrawNFT(uint256 amount, address addr);
    event WithdrawFFT(uint256 amount, address addr);
    error NoReason(uint256 a, uint256 b);
}
