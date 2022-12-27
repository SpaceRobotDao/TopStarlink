/**
 *Submitted for verification at BscScan.com on 2022-09-02
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

interface ISwapRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface ISwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

abstract contract AbcToken is ERC20, Ownable {

    address private fundAddress;
    address private backflowAddress;

    mapping(address => bool) private _feeList;

    ISwapRouter private _swapRouter;
    mapping(address => bool) private _swapPairList;

    bool private inSwap;

    uint256 private constant MAX = ~uint256(0);

    uint256 private _buyBackflowFee = 500;
    uint256 private _sellFundFee = 500;

    uint256 private numTokensCanSwap = 30000 * 10**18;

    uint256 public totalBurn;

    address public mainPair;

    address private usdt;

    address private usdtPair;


    address private deadWallet = 0x000000000000000000000000000000000000dEaD;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (
        address RouterAddress, 
        string memory Name, string memory Symbol, uint256 Supply,
        address FundAddress, address BackflowAddress, address ReceiveAddress, address LPAddress, address NodeAddress
    ) ERC20(Name, Symbol) {
        
        ISwapRouter swapRouter = ISwapRouter(RouterAddress);
        _swapRouter = swapRouter;
        _approve(address(this), address(swapRouter), MAX);

        ISwapFactory swapFactory = ISwapFactory(swapRouter.factory());
        address swapPair = swapFactory.createPair(address(this), swapRouter.WETH());
        mainPair = swapPair;
        _swapPairList[swapPair] = true;

        _mint(address(ReceiveAddress),Supply * (30) / (100));
        _mint(address(LPAddress),Supply * (21) / (100));
        _mint(address(NodeAddress),Supply * (9) / (100));
        _mint(address(deadWallet),Supply * (40) / (100));
        totalBurn += Supply * (40) / (100);

        fundAddress = FundAddress;
        backflowAddress = BackflowAddress;

        usdt = address(0x55d398326f99059fF775485246999027B3197955);
        usdtPair = address(0x20bCC3b8a0091dDac2d0BC30F68E6CBb97de59Cd);

        _feeList[FundAddress] = true;
        _feeList[BackflowAddress] = true;
        _feeList[LPAddress] = true;
        _feeList[address(this)] = true;
        _feeList[address(swapRouter)] = true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )  internal override {
        uint256 balance = balanceOf(from);
        require(balance >= amount, "balanceNotEnough");

        if (!_feeList[from] && !_feeList[to]) {
            uint256 maxSellAmount = balance * 9999 / 10000;
            if (amount > maxSellAmount) {
                amount = maxSellAmount;
            }
        }

        bool takeFee;
        bool isSell;

        if (_swapPairList[from] || _swapPairList[to]) {
            if (!_feeList[from] && !_feeList[to]) {
                if (0 == startTradeBlock) {
                    require(0 < startAddLPBlock && _swapPairList[to], "!startAddLP");
                }

                if (block.number < startTradeBlock + 2) {
                    _funTransfer(from, to, amount);
                    return;
                }

                if (_swapPairList[to]) {
                    if (!inSwap) {
                        uint256 contractTokenBalance = balanceOf(address(this));
                        if (contractTokenBalance >= numTokensCanSwap) {
                            swapTokenForFund(numTokensCanSwap);
                        }
                    }
                }
                takeFee = true;
            }
            if (_swapPairList[to]) {
                isSell = true;
            }
        }

        _tokenTransfer(from, to, amount, takeFee, isSell);
    }

    function _funTransfer(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 feeAmount = tAmount * 75 / 100;
        _takeTransfer(
            sender,
            address(this),
            feeAmount
        );
        _takeTransfer(sender, recipient, tAmount - feeAmount);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee,
        bool isSell
    ) private {
        uint256 feeAmount;

        if (takeFee) {
            if (isSell) {
                uint256 sellFundFee = tAmount * _sellFundFee / 10000;

                if (sellFundFee > 0) {
                    feeAmount += sellFundFee;
                    _takeTransfer(sender, address(this), sellFundFee);
                }
            } else {
                uint256 buyBackflowFee = tAmount * _buyBackflowFee / 10000;

                if (buyBackflowFee > 0) {
                    feeAmount += buyBackflowFee;
                    _takeTransfer(sender, address(backflowAddress), buyBackflowFee);
                }
            }
        }

        _takeTransfer(sender, recipient, tAmount - feeAmount);
    }

    function swapTokenForFund(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _swapRouter.WETH();

        _swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,// accept any amount of ETH
            path,
            address(fundAddress),
            block.timestamp
        );
    }

    function _takeTransfer(
        address sender,
        address to,
        uint256 tAmount
    ) private {
        if(to == address(0) || to == deadWallet){
            totalBurn += tAmount;
            super._transfer(sender,deadWallet,tAmount);
        }else{
            super._transfer(sender,to,tAmount);
        }
    }

    uint256 private startTradeBlock;
    uint256 private startAddLPBlock;

    function startAddLP() external onlyOwner {
        require(0 == startAddLPBlock, "startedAddLP");
        startAddLPBlock = block.number;
    }

    function startTrade() external onlyOwner {
        require(0 == startTradeBlock, "trading");
        startTradeBlock = block.number;
    }

    function claimBalance() external {
        payable(fundAddress).transfer(address(this).balance);
    }

    receive() external payable {}

    function tokenData() public view returns (uint256 price, uint256 circulation, uint256 marketValue, uint256 burn) {
        price = bnbEqualsToUsdt(tokenEqualsToBnb(10 ** 18)) / (10 ** 14);
        circulation = (totalSupply() - totalBurn) / (10 ** 14);
        marketValue = bnbEqualsToUsdt(tokenEqualsToBnb(circulation));
        burn = totalBurn / (10 ** 14);
    }

    function tokenEqualsToBnb(uint256 tokenAmount) public view returns(uint256 bnbAmount) {
        uint256 tokenOfPair = balanceOf(mainPair);
        uint256 bnbOfPair = IERC20(_swapRouter.WETH()).balanceOf(mainPair);

        if(tokenOfPair > 0 && bnbOfPair > 0){
            bnbAmount = tokenAmount * bnbOfPair / tokenOfPair;
        }

        return bnbAmount;
    }

    function bnbEqualsToUsdt(uint256 bnbAmount) public view returns(uint256 usdtAmount) {
        uint256 tokenOfPair = IERC20(usdt).balanceOf(usdtPair);
        uint256 bnbOfPair = IERC20(_swapRouter.WETH()).balanceOf(usdtPair);

        if(tokenOfPair > 0 && bnbOfPair > 0){
            usdtAmount = bnbAmount * tokenOfPair / bnbOfPair;
        }

        return usdtAmount;
    }

}

contract TopStarlink is AbcToken {
    constructor() AbcToken(
        address(0x10ED43C718714eb63d5aA57B78B54704E256024E),//RouterAddress
        "Top Starlink",//Name
        "TOPSK",//Symbol
        100000000 * 10**18,//Supply
        address(0xAF4226A87cEE85a1924AC1F6Ba6AaF31EB1aC0Ef),//FundAddress
        address(0x20bf13bE83F073524145B3d2909D27a8533FB8C6),//BackflowAddress
        address(0x5dA1a119D6d0F89D4819AE80A6D23946aD9F8768),//ReceiveAddress
        address(0x5dA1a119D6d0F89D4819AE80A6D23946aD9F8768),//LPAddress
        address(0xf6Ee8cB89cd1D834CfCEa275600d1159a7a5113f)//NodeAddress
    ){

    }
}