//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract PriceManipulationPrevention {
    // 结算价格信息
    struct DexPrice {
        string dexName;
        string poolDescription;
        address pool;
        uint256 price;
    }

    // 项目地址 => 项目中的函数 => 结算价格信息
    mapping(address => mapping(bytes4 => DexPrice)) funcToDexPrice;

    // 获取该函数的结算价格
    /**
     * @notice 获取受保护项目特定函数进行金融结算所使用的价格信息
     * @param data：包括受保护项目地址、特定函数、金融结算使用的交易所名称、金融结算使用的币对名称以及金融计算使用币对的地址
     */
    function setInfo(bytes memory data) external {
        (
            address project,
            bytes4 func_selector,
            string memory DexName,
            string memory PoolDescription,
            address Pool
        ) = abi.decode(data, (address, bytes4, string, string, address));

        funcToDexPrice[project][func_selector].dexName = DexName;
        funcToDexPrice[project][func_selector].poolDescription = PoolDescription;
        funcToDexPrice[project][func_selector].pool = Pool;
        
        // 获取对应交易所代币价格
    }

    // TODO:怎样获取链上价格
    function getPriceFromDex() internal {
        
    }

    function compare() external {

    }
}
