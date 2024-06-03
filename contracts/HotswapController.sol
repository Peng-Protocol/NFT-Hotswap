// SPDX-License-Identifier: BSD-3-Clause
/// @title Hotswap Controller
//   ::   .:      ...   :::::::::::: .::::::..::    .   .::::::.  ::::::::::.
//  ,;;   ;;,  .;;;;;;;.;;;;;;;;'''';;;`    `';;,  ;;  ;;;' ;;`;;  `;;;```.;;;
// ,[[[,,,[[[ ,[[     \[[,   [[     '[==/[[[[,'[[, [[, [[' ,[[ '[[, `]]nnn]]'
// "$$$"""$$$ $$$,     $$$   $$       '''    $  Y$c$$$c$P c$$$cc$$$c $$$""
//  888   "88o"888,_ _,88P   88,     88b    dP   "88"888   888   888,888o
//  MMM    YMM  "YMMMMMP"    MMM      "YMmMY"     "M "M"   YMM   ""` YMMMb

pragma solidity ^0.8.25;

import "./interfaces/ERC20.sol";
import "./interfaces/ERC721.sol";
import "./HotswapControllerBase.sol";

contract HotswapController is HotswapControllerBase {
    uint256 private constant FEE = 5e14; // 0.05% [Normalized]
    uint256 private constant COLLECTOR_FEE_RATIO = 5e18; // 1/5 i.e 0.2, 20%

    uint256 public tVolume;

    constructor(address nft, address fft) HotswapControllerBase(nft, fft) {}

    function depositNFT(uint256 amount) external {
        _deposit(amount, true);
        _createLiquid(amount, true);
    }

    function depositFFT(uint256 amount) external {
        _deposit(amount, false);
        _createLiquid(amount, false);
    }

    function _deposit(uint256 amount, bool isNFT) private {
        if (amount <= 0) {
            revert DepositFailed();
        }

        if (isNFT) {
            uint256 tokenId;
            bytes memory data = new bytes(0);

            for (uint256 i = 0; i < amount; i++) {
                tokenId = _nft.tokenOfOwnerByIndex(msg.sender, i);
                _nft.safeTransferFrom(msg.sender, _liquidity, tokenId, data);
            }
        } else if (!_fft.transferFrom(msg.sender, _liquidity, amount)) {
            revert DepositFailed();
        }
    }

    function _createLiquid(uint256 amount, bool isNFT) private {
        uint256[] storage userLiquid = isNFT
            ? _nftUserLiquid[msg.sender]
            : _fftUserLiquid[msg.sender];
        uint256 index = userLiquid.length;

        uint256 price = _updatePrice();
        uint256 allocRatio;

        if (isNFT) {
            amount = _scaleUp(amount);
            allocRatio = _div(amount, _fetchLiquidity(isNFT));
        } else {
            amount = _normalize(amount);
            allocRatio = _div(amount, _fetchLiquidity(isNFT));
        }

        Liquid memory lq = Liquid(
            userLiquid.length,
            price,
            msg.sender,
            block.timestamp,
            amount,
            allocRatio,
            tVolume,
            isNFT,
            false
        );

        if (isNFT) {
            _nftLiquids.push(lq);
        } else {
            _fftLiquids.push(lq);
        }

        userLiquid.push(index);
    }

    function queryLiquid(
        uint256 index,
        bool isNFT
    ) external view returns (LiquidData memory) {
        return queryLiquidbyDepositor(msg.sender, index, isNFT);
    }

    function queryLiquidbyDepositor(
        address depositor,
        uint256 index,
        bool isNFT
    ) public view returns (LiquidData memory) {
        uint256[] memory indexes = isNFT
            ? _nftUserLiquid[depositor]
            : _fftUserLiquid[depositor];

        uint256 n = indexes[index];
        Liquid memory lq = isNFT ? _nftLiquids[n] : _fftLiquids[n];

        return
            LiquidData(
                lq.depositor,
                lq.depositedAt,
                lq.price,
                lq.alloc,
                lq.kind,
                lq.claimed
            );
    }

    function getLiquidityCount(bool isNFT) external view returns (uint256) {
        return isNFT ? _nftLiquids.length : _fftLiquids.length;
    }

    function _queryUserLiquid(
        address user,
        uint256 n,
        bool isNFT
    ) private view returns (Liquid storage) {
        uint256[] memory indexes = isNFT
            ? _nftUserLiquid[user]
            : _fftUserLiquid[user];

        return isNFT ? _nftLiquids[indexes[n]] : _fftLiquids[indexes[n]];
    }

    function _fetchLiquidity(bool isNFT) private returns (uint256) {
        if (isNFT) {
            return _scaleUp(nftLiquidity());
        }

        return _normalize(fftLiquidity());
    }

    function claimFee(uint256 index, bool isNFT) public {
        address targetAddr = msg.sender;
        Liquid storage liquid = _queryUserLiquid(msg.sender, index, isNFT);

        if (liquid.claimed) {
            revert FeeAlreadyClaimedForSlot();
        }

        uint256 tVol = tVolume;
        uint256 cumulativeVol = tVol - liquid.dVolume;

        uint256 fees = _mul(cumulativeVol, 4e18);
        fees = _div(fees, 10000e18);

        fees = _mul(liquid.allocRatio, fees);
        fees = _denormalize(fees);

        if (fees <= 0 || _fft.transfer(targetAddr, fees)) {
            liquid.claimed = true;
            emit FeeClaimed(targetAddr, fees);
        }
    }

    function withdrawLiquidity(uint256 index, bool isNFT) external {
        address user = msg.sender;
        uint256[] memory indexes = isNFT
            ? _nftUserLiquid[user]
            : _fftUserLiquid[user];

        uint256 n = indexes[index];

        Liquid memory lq = _queryUserLiquid(msg.sender, index, isNFT);
        uint256 price = lq.price > 0 ? lq.price : _price;

        if (price == 0) {
            revert InvalidWithdrawalRequest();
        }

        uint256 currentLiquidity = _fetchLiquidity(isNFT);

        uint256 nOutput = _mul(currentLiquidity, lq.allocRatio);
        uint256 outputAmount;

        if (nOutput > lq.alloc) {
            nOutput = lq.alloc;
        }

        if (isNFT) {
            outputAmount = _scaleDown(nOutput);
            _liq.withdrawNFT(outputAmount, msg.sender);
        } else {
            outputAmount = _normalize(nOutput);
            _liq.withdrawFFT(outputAmount, msg.sender);
        }

        _removeLiquidity(lq, n);
    }

    function _removeLiquidity(Liquid memory lq, uint256 index) private {
        uint256 userIndex = lq.userIndex;
        bool isNFT = lq.kind;

        Liquid storage last;
        mapping(address => uint256[]) storage liquidityByUser = isNFT
            ? _nftUserLiquid
            : _fftUserLiquid;

        uint256[] storage userLiquids = liquidityByUser[msg.sender];

        Liquid[] storage liquids = isNFT ? _nftLiquids : _fftLiquids;

        if (_removeItem(userLiquids, userIndex)) {
            last = liquids[userLiquids[userIndex]];
            last.userIndex = userIndex;
        }

        if (_removeItem(liquids, index)) {
            last = liquids[index];

            userIndex = last.userIndex;
            liquidityByUser[last.depositor][userIndex] = index;
        }
    }

    function _addVolume(uint256 amount) private {
        tVolume += amount;
    }

    function _determineCost(
        bool isSell,
        uint256 nft,
        uint256 constraint,
        uint256 price
    ) private returns (uint256 nftAmount, uint256 fftAmount, uint256 fee) {
        if (price == 0) {
            revert InvalidSwapPrice();
        }

        uint256 minout = 0;
        uint256 maxin = 0;

        uint256 threshold = _normalize(
            _div(_mul(fftLiquidity(), 51e18), 100e18)
        );

        if (isSell) {
            maxin = threshold;
            minout = _normalize(constraint);
        } else {
            maxin = _normalize(constraint);
            minout = 0;

            if (maxin > threshold) {
                maxin = threshold;
            }
        }

        nftAmount = _scaleUp(nft);
        fftAmount = _mul(nftAmount, _price);

        fee = _getFee(fftAmount);
        uint256 targetAmount = fftAmount + fee;
        uint256 allowance;

        if (isSell) {
            allowance = type(uint256).max;
        } else {
            allowance = _fft.allowance(msg.sender, address(this));
        }

        while (targetAmount > allowance || targetAmount > maxin) {
            nftAmount -= 1e18;
            fftAmount = _mul(nftAmount, _price);
            fee = _getFee(fftAmount);
            targetAmount = fftAmount + fee;
        }

        if (targetAmount == 0 || targetAmount < minout) {
            revert InsufficientSwapAmount();
        }
    }

    function _getFee(uint256 amount) private pure returns (uint256) {
        uint256 fee = _mul(amount, 5e18);
        return _div(fee, 10000e18);
    }

    function _deductFee(uint256 amount) private {
        uint256 nCollectorFee = _div(amount, COLLECTOR_FEE_RATIO);

        uint256 collectorFee = _denormalize(nCollectorFee);
        uint256 remFee = amount - collectorFee;

        _liq.withdrawFFT(collectorFee, _collector);
        _liq.withdrawFFT(remFee, address(this));
        _fees += remFee;

        emit Fee(amount);
    }

    function swapNFT(uint256 nftCount, uint256 minOutput) external {
        (uint256 nftAmount, uint256 fftAmount, uint256 fee) = _determineCost(
            true,
            nftCount,
            minOutput,
            _price
        );

        uint256 dnft = _scaleDown(nftAmount);
        uint256 dfft = _denormalize(fftAmount);

        uint256 newPrice = _computePrice(
            nftLiquidity() - dnft,
            dfft + fftLiquidity()
        );

        (nftAmount, fftAmount, fee) = _determineCost(
            true,
            nftCount,
            minOutput,
            newPrice
        );

        dnft = _scaleDown(nftAmount);
        dfft = _denormalize(fftAmount);

        _deposit(dnft, true);
        _deductFee(fee);

        uint256 ntfft = _normalize(fftLiquidity());
        if (fftAmount > ntfft) {
            revert InsufficientLiquidity();
        }

        _updatePrice();
        _addVolume(fftAmount);

        _liq.withdrawFFT(dfft, msg.sender);
        emit Swap(dnft, dfft, msg.sender);
    }

    function swapFFT(uint256 nftCount, uint256 maxInput) external {
        (uint256 nftAmount, uint256 fftAmount, uint256 fee) = _determineCost(
            false,
            nftCount,
            maxInput,
            _price
        );

        uint256 dnft = _scaleDown(nftAmount);
        uint256 dfft = _denormalize(fftAmount);

        uint256 dtnft = nftLiquidity();
        if (dnft > dtnft) {
            revert InsufficientLiquidity();
        }

        _deposit(dfft, false);
        _deductFee(fee);

        _liq.withdrawNFT(dnft, msg.sender);
        emit Swap(dnft, dfft, msg.sender);

        _updatePrice();
        _addVolume(fftAmount);
    }
}
