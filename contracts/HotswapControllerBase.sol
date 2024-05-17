// SPDX-License-Identifier: BSD-3-Clause
//   ::   .:      ...   :::::::::::: .::::::..::    .   .::::::.  ::::::::::.
//  ,;;   ;;,  .;;;;;;;.;;;;;;;;'''';;;`    `';;,  ;;  ;;;' ;;`;;  `;;;```.;;;
// ,[[[,,,[[[ ,[[     \[[,   [[     '[==/[[[[,'[[, [[, [[' ,[[ '[[, `]]nnn]]'
// "$$$"""$$$ $$$,     $$$   $$       '''    $  Y$c$$$c$P c$$$cc$$$c $$$""
//  888   "88o"888,_ _,88P   88,     88b    dP   "88"888   888   888,888o
//  MMM    YMM  "YMMMMMP"    MMM      "YMmMY"     "M "M"   YMM   ""` YMMMb

pragma solidity ^0.8.25;

import "./Ownable.sol";
import "./HotswapPair.sol";
import "./interfaces/ERC721.sol";
import "./libraries/SafeMath.sol";
import "./libraries/PreciseMath.sol";
import "./HotswapLiquidity.sol";

interface IHotswapController {
    function setCollector(address addr) external;

    function setLiquidity(address addr) external;
}

interface IHotswapLiquidity {
    function setController(address addr) external;

    function withdrawFFT(uint256 amount, address dest) external;

    function withdrawNFT(uint256 amount, address dest) external;
}

contract HotswapControllerBase is HotswapPair, IHotswapController {
    using SafeMath for uint256;

    address public _collector;
    address public _liquidity;

    uint256 public _price;
    mapping(uint8 => uint256) private _scalars;
    mapping(address => uint256[]) internal _liquidityByUser;

    Liquid[] public _liquids;
    uint256 public _fees;

    HotswapLiquidity internal _liq;

    constructor(address nft, address fft) HotswapPair(nft, fft) {
        _collector = msg.sender;
    }

    function _computePrice() internal returns (uint256) {
        uint256 fBalance = _fft.balanceOf(_liquidity);
        uint256 nNFT = _nft.balanceOf(_liquidity);

        uint256 nFFT = _normalize(fBalance, decimals);
        nNFT = _normalize(nNFT, 18);

        _price = _div(nFFT, nNFT);

        return _price;
    }

    function setCollector(address addr) public onlyOwner {
        _collector = addr;
    }

    function setLiquidity(address addr) public onlyOwner {
        _liquidity = addr;
        _liq = HotswapLiquidity(addr);
        _computePrice();
    }

    struct Liquid {
        address depositor;
        uint256 depositedAt;
        uint256 price;
        uint256 nftAlloc;
        uint256 fftAlloc;
        bool claimed;
        uint256 userIndex;
    }

    struct LiquidData {
        address depositor;
        uint256 depositedAt;
        uint256 price;
        uint256 nftAlloc;
        uint256 fftAlloc;
        bool claimed;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Math
    function _mul(uint256 num1, uint256 num2) internal pure returns (uint256) {
        return PreciseMath.mul(num1, num2);
    }

    function _div(uint256 num1, uint256 num2) internal pure returns (uint256) {
        return PreciseMath.div(num1, num2);
    }

    function _normalize(
        uint256 amount,
        uint8 decimals
    ) internal returns (uint256) {
        return decimals == 1 ? amount : amount * _computeScalar(decimals);
    }

    function _denormalize(
        uint256 amount,
        uint8 decimals
    ) internal returns (uint256) {
        return decimals == 1 ? amount : amount / _computeScalar(decimals);
    }

    function _computeScalar(uint8 decimals) internal returns (uint256 scalar) {
        scalar = _scalars[decimals];

        if (scalar == 0) {
            unchecked {
                _scalars[decimals] = scalar = 10 ** (18 - decimals);
            }
        }
    }
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
}
