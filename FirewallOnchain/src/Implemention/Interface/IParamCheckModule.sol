pragma solidity ^0.8.0;

interface IParamCheckModule{
    function removePartialInfo(bytes memory data) external virtual;
}