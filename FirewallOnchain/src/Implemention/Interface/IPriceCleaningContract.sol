// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceCleaningContract {
    // record a token price and it's dex info
    struct DexInfo {
        string dexName;
        string poolDescription;
        address pool;
        address token;
        int256 price;
        uint8 txAmount;
    }

    function addDexInfo(
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        address _token,
        int256 _price,
        uint8 _txAmount
    ) external;

    function updateDexInfo(
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        uint8 index
    ) external;

    function setTokenPriceForAllDexs() external;

    function getDexInfo(uint8 index) external returns (DexInfo memory);

    function getUsefulDexInfo(uint8 index) external returns (DexInfo memory);

    function setTokenPriceForOneDex(uint8 index) external;

    function updateOffchainPrice(
        address _oracle,
        bool _needReciprocal
    ) external;

    function cleanDexPrice(address _oracle) external;

    function calculateRealPrice(address targetToken) external returns (int256);
}
