// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IModule {
    function setInfo(bytes memory data) external virtual;
    function setMode(bytes memory data) external virtual;
    function removeInfo(bytes memory data) external virtual;
    function detect(address project, string[] memory params, bytes memory data) external virtual returns (bool);
}
