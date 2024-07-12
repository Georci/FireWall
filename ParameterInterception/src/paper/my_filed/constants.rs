use serde::{Deserialize, Serialize};
use std::fmt;

// 都是ws
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ChainType {
    #[serde(rename = "ethereum_mainnet")]
    EthereumMainnet,
    #[serde(rename = "ethereum_sepolia")]
    EthereumSepolia,
    #[serde(rename = "bsc_mainnet")]
    BSCMainnet,
    #[serde(rename = "bsc_testnet")]
    BSCTestnet,
    #[serde(rename = "polygon_mainnet")]
    PolygonMainnet,
    #[serde(rename = "optimism_mainnet")]
    OptimismMainnet,
    #[serde(rename = "arbitrum_mainnet")]
    ArbitrumMainnet,
    #[serde(rename = "arbitrum_sepolia")]
    ArbitrumSepolia,
    #[serde(rename = "private_network")]
    PrivateNetwork,
}

impl ChainType {
    // 获取枚举类型的字符串表示
    pub fn as_str(&self) -> &'static str {
        match self {
            ChainType::EthereumMainnet => "ethereum_mainnet",
            ChainType::EthereumSepolia => "ethereum_sepolia",
            ChainType::BSCMainnet => "bsc_mainnet",
            ChainType::BSCTestnet => "bsc_testnet",
            ChainType::PolygonMainnet => "polygon_mainnet",
            ChainType::OptimismMainnet => "optimism_mainnet",
            ChainType::ArbitrumMainnet => "arbitrum_mainnet",
            ChainType::ArbitrumSepolia => "arbitrum_sepolia",
            ChainType::PrivateNetwork => "private_network",
        }
    }

    // 从字符串转换为 ChainType
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "ethereum_mainnet" => Some(ChainType::EthereumMainnet),
            "ethereum_sepolia" => Some(ChainType::EthereumSepolia),
            "bsc_mainnet" => Some(ChainType::BSCMainnet),
            "bsc_testnet" => Some(ChainType::BSCTestnet),
            "polygon_mainnet" => Some(ChainType::PolygonMainnet),
            "optimism_mainnet" => Some(ChainType::OptimismMainnet),
            "arbitrum_mainnet" => Some(ChainType::ArbitrumMainnet),
            "arbitrum_sepolia" => Some(ChainType::ArbitrumSepolia),
            "private_network" => Some(ChainType::PrivateNetwork),
            _ => None,
        }
    }
}

impl fmt::Display for ChainType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}
