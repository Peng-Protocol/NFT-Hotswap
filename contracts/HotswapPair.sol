// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./HotswapBase.sol";
import "./interfaces/ERC20.sol";
import "./interfaces/ERC721.sol";

contract HotswapPair is HotswapBase {
    address public NFT;
    address public FFT;

    ERC20 internal _fft;
    ERC721Enumerable internal _nft;

    function name() external view returns (string memory) {
        if (NFT == address(0) && FFT == address(0)) {
            return "Legacy";
        }

        string memory nftName = _nft.name();
        string memory fftName = _fft.name();

        string memory buffer = string.concat(nftName, " - ");

        return string.concat(buffer, fftName);
    }

    function setNFT(address addr) private {
        NFT = addr;
        _nft = ERC721Enumerable(addr);
    }

    function setFFT(address addr) private {
        FFT = addr;
        _fft = ERC20(addr);
    }

    constructor(address nft, address fft) {
        setNFT(nft);
        setFFT(fft);
    }
}