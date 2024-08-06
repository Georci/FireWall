// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceCleaningContract {
    // record a token price and it's dex info
    struct DexInfo {
        string dexName;
        string poolDescription;
        address pool;
        // 一般来说指默认价格高的那种代币，如ETH / USDT，默认为ETH
        address token;
        // 在当前代币对中，该代币的价格
        int256 price;
        // 该交易所的交易数量
        uint8 txAmount;
        //
        bool isEnabled;
    }

    function addDexInfo(
        address _oracle,
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        address _token,
        int256 _price,
        uint8 _txAmount,
        bool _isEnabled
    ) external;

    function updateDexInfo(
        address _oracle,
        uint8 index,
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        bool _isEnabled
    ) external;

    function setTokenPriceForAllDexs(address _oracle) external;

    function getDexInfo(
        address _oracle,
        uint8 index
    ) external returns (DexInfo memory);

    function setTokenPriceForOneDex(address _oracle, uint8 index) external;

    function updateOffchainPrice(
        address _oracle,
        bool _needReciprocal
    ) external;

    function cleanDexPrice(address _oracle) external;

    function calculateRealPrice(
        address _oracle
    ) external returns (int256);
}
