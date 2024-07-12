use dotenv::dotenv;
use mysql::params;
use mysql::prelude::*;
use mysql::PooledConn;
use revm_primitives::HashMap;
use std::sync::Arc;
use std::{env, fmt};

use super::constants::ChainType;

// 地址 -> 保护信息
pub type AddressProtectInfo = HashMap<String, ProtectInfo>;
#[derive(Debug, Clone)]
pub struct DatabaseManager {
    // 数据库连接
    pub sql_pool: Arc<mysql::Pool>,
    // chain => 地址保护信息
    pub info: Arc<HashMap<ChainType, AddressProtectInfo>>,
}
#[derive(Debug, Clone)]
pub struct ProtectInfo {
    // 不变量
    pub invariant: String,
    // 相关的变量
    pub variables: Vec<String>,
    // 保护的选择器
    pub selectors: Vec<String>,
    // 变量 => slot
    pub slot_map: HashMap<String, String>,
    // 选择器 => index => 函数表达式
    pub expression_map: HashMap<String, HashMap<u8, String>>,
}

impl DatabaseManager {
    // 初始化
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        // 读取数据库
        dotenv().ok();
        let _sql_url = env::var("MYSQL_URL").unwrap();
        Ok(Self {
            sql_pool: Arc::new(mysql::Pool::new(_sql_url.as_str()).expect("error mysql url")),
            info: Arc::new(HashMap::new()),
        })
    }

    pub fn get_invariant(
        &self,
        chain_type: ChainType,
        address: String,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let address_pi = self.info.get(&chain_type).unwrap().get(&address).unwrap();
        Ok(address_pi.invariant.clone())
    }
    pub fn get_chain_rpc(&self) -> Result<HashMap<ChainType, String>, Box<dyn std::error::Error>> {
        let mut sql_conn = self.sql_pool.get_conn()?;
        let data: Vec<(String, String)> =
            sql_conn.query("SELECT chain_name, chain_rpc FROM chains")?;
        let mut temp_map = HashMap::new();
        data.into_iter().for_each(|(chain, rpc)| {
            temp_map.insert(ChainType::from_str(&chain).unwrap(), rpc);
        });
        Ok(temp_map)
    }

    pub fn load_data_to_local(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // 获得连接
        let mut conn = self.sql_pool.get_conn().unwrap();
        // 按照chain分组，获得所有地址
        let data: Vec<(u64, String, String, String)> = conn
            .query("SELECT* FROM address_invariants GROUP BY chain,address")
            .unwrap();
        let all_chain: Vec<String> = data.iter().map(|(_, _, _, chain)| chain.clone()).collect();
        let mut _info = HashMap::new();
        for chain in all_chain {
            let _type = ChainType::from_str(&chain).unwrap();
            let mut _address_protect_info: AddressProtectInfo = HashMap::new();
            for (_address_id, _address, _invariant, _) in data.iter() {
                let pi =
                    Self::get_pi(&mut conn, _address_id.clone(), &_address, _invariant).unwrap();
                _address_protect_info.insert(_address.to_string(), pi);
            }
            _info.insert(_type, _address_protect_info);
        }
        self.info = Arc::new(_info);
        Ok(())
    }

    fn get_pi(
        conn: &mut PooledConn,
        _address_id: u64,
        _address: &str,
        _invariant: &str,
    ) -> Result<ProtectInfo, Box<dyn std::error::Error>> {
        // 根据地址获得变量
        let variable_slot: Vec<(String, String)> = conn
            .exec(
                "Select variable,slot from variables Where address_id =:address_id ",
                params! {
                    "address_id" => _address_id
                },
            )
            .unwrap();
        // 获得var
        let variables = variable_slot
            .iter()
            .map(|(variable, _)| variable.clone())
            .collect();
        // 构造对应关系
        let mut slot_map = HashMap::new();
        for (var, slot) in variable_slot {
            slot_map.insert(var, slot);
        }
        // 根据地址获得选择器
        let selector_index_exp: Vec<(String, u8, String)> = conn.exec(
   "Select selector,`index`,expression from expressions Where address_id =:address_id ",
   params! {
       "address_id" => _address_id
   },
).unwrap();
        // 获得选择器
        let selectors = selector_index_exp
            .iter()
            .map(|(selector, _, _)| selector.clone())
            .collect();
        // 构造对应关系
        let mut expression_map = HashMap::new();
        for (selector, index, exp) in selector_index_exp {
            let mut temp_map3 = HashMap::new();
            temp_map3.insert(index, exp);
            expression_map.insert(selector, temp_map3);
        }
        Ok(ProtectInfo {
            invariant: _invariant.to_string(),
            variables,
            selectors,
            slot_map,
            expression_map,
        })
    }

    pub fn get_address_invar(&self, chain_type: ChainType) -> Vec<(String, String)> {
        let all_protect = self.info.get(&chain_type).clone().unwrap();
        let mut temp_vec = vec![];
        for (addr, pi) in all_protect {
            let invar = pi.invariant.clone();
            temp_vec.push((addr.clone(), invar));
        }
        temp_vec
    }

    pub fn get_expression_map(
        &self,
        chain_type: ChainType,
        address: String,
        selector: String,
    ) -> HashMap<u8, String> {
        // todo 如果在执行过程中,未注册的函数使得不变量进行了改变,则会导致程序中断
        let chain_info = self.info.get(&chain_type).unwrap();
        let pi = chain_info.get(&address).unwrap();
        println!("交互pi {:?}", pi);
        pi.expression_map.get(&selector).unwrap().clone()
    }
}

// #[test]
// fn test1() {
//     let mut database = DatabaseManager::new().unwrap();
//     database.load_data_to_local();
// }
