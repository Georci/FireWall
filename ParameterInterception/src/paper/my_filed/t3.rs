use super::constants::ChainType;
use super::database_mod::DatabaseManager;
use crate::core_module::utils;
use crate::paper::my_filed::expression::evaluate_exp_with_unknown;
use crate::paper::my_filed::parser::parse_expression;
use crate::paper::my_filed::sym_exec::sym_exec;
use crate::paper::my_filed::Handler::get_selector;
use dotenv::dotenv;
use ethers::abi::AbiEncode;
use ethers::types::Transaction;
use ethers::types::H160;
use ethers::types::{BlockId, H256, U256};
use ethers_providers::{Middleware, Provider, Ws};
use futures::future::join_all;
use futures::{join, StreamExt};
use revm_primitives::HashMap;
use std::env;
use std::str::FromStr;
use std::sync::Arc;
use tokio::sync::mpsc::{channel, Receiver, Sender};
use tokio::sync::{Mutex, Semaphore};
// 链信息
#[derive(Debug, Clone)]
pub struct ChainInfo {
    pub rpc_url: String,
    pub provider: Arc<Provider<Ws>>,
}

// 发送的信息
#[derive(Debug, Clone)]
pub struct SendData {
    pub chain: ChainType,
    pub block_number: u64,
    pub address: Option<String>,
}

// 地址 -> 值暂存
type AddressStateCache = HashMap<String, Vec<(String, U256)>>;
// 链类型 -> 地址 -> 值暂存
type ChainStateCache = HashMap<ChainType, AddressStateCache>;

#[derive(Debug, Clone)]
pub struct HandlerTest {
    // 链 => ChainInfo
    pub chains: Arc<HashMap<ChainType, ChainInfo>>,
    // 数据库管理
    pub database: Arc<DatabaseManager>,
    // 信号量
    pub rpc_semaphore: Arc<Semaphore>,
    pub cacl_semaphore: Arc<Semaphore>,
    pub sym_semaphore: Arc<Semaphore>,
    // 出块提醒
    pub block_sender: Arc<Sender<SendData>>,
    pub block_receiver: Arc<Mutex<Receiver<SendData>>>,
    // 符号执行提醒
    pub sym_sender: Arc<Sender<SendData>>,
    pub sym_receiver: Arc<Mutex<Receiver<SendData>>>,
    // 为每条链的每个地址，暂存当前块的状态，每当出块就进行暂存
    pub state_cache: Arc<Mutex<ChainStateCache>>,
    pub max_rpc_per_seconde: usize,
}

impl HandlerTest {
    // 从数据库加载rpc
    pub async fn new() -> Arc<Self> {
        dotenv().ok();
        println!("开始连接数据库");
        // 创建数据库
        let mut database = DatabaseManager::new().unwrap();
        // 数据库缓存加载
        let _ = database.load_data_to_local();
        println!("数据库缓存加载完毕！！！");

        // 数据库查询rpc
        let _chains = database.get_chain_rpc().unwrap();
        println!("当前支持的链，以及配置的rpc {:?}", _chains);
        // 初始化chains
        let mut chains = HashMap::new();
        for (_type, _rpc) in _chains {
            let temp_provider = Provider::<Ws>::connect(&_rpc).await.unwrap();
            chains.insert(
                _type,
                ChainInfo {
                    rpc_url: _rpc,
                    provider: Arc::new(temp_provider),
                },
            );
        }

        // 信号量
        let rpc_semaphore = Arc::new(Semaphore::new(10));
        let cacl_semaphore = Arc::new(Semaphore::new(4));
        let sym_semaphore = Arc::new(Semaphore::new(4));

        // 创建区块消息提醒
        let (block_sender, block_receiver): (Sender<SendData>, Receiver<SendData>) = channel(10);
        let (sym_sender, sym_receiver): (Sender<SendData>, Receiver<SendData>) = channel(10);

        Arc::new(HandlerTest {
            database: Arc::new(database),
            chains: Arc::new(chains),
            rpc_semaphore,
            cacl_semaphore,
            sym_semaphore,
            block_sender: Arc::new(block_sender),
            block_receiver: Arc::new(Mutex::new(block_receiver)),
            sym_sender: Arc::new(sym_sender),
            sym_receiver: Arc::new(Mutex::new(sym_receiver)),
            state_cache: Arc::new(Mutex::new(HashMap::new())),
            max_rpc_per_seconde: 40,
        })
    }

    pub async fn get_block(self: Arc<Self>) {
        println!("开始获取区块");
        // 要获取多条链的区块
        let chains = Arc::clone(&self.chains);

        // 为每条链创建一个异步任务
        let all_chain_task = chains.iter().map(|(_type, _chain_info)| {
            // 复制信息
            let _type = _type.clone();
            let _chain_info = _chain_info.clone();
            let _provider = Arc::clone(&_chain_info.provider);
            let _rpc_semaphore = Arc::clone(&self.rpc_semaphore);
            let _block_sender = Arc::clone(&self.block_sender);
            // 异步任务创建
            tokio::spawn(async move {
                // 消耗信号量
                let permit = _rpc_semaphore.acquire_owned().await.unwrap();
                // 订阅区块，可重试一次
                let mut block_stream = match _provider.subscribe_blocks().await {
                    Ok(block_stream) => block_stream,
                    Err(_) => _provider.subscribe_blocks().await.unwrap(),
                };
                while let Some(block) = block_stream.next().await {
                    let block_number = block.number.unwrap().as_u64();
                    // 发送区块信息
                    {
                        match _block_sender
                            .send(SendData {
                                chain: _type.clone(),
                                block_number,
                                address: None,
                            })
                            .await
                        {
                            Ok(_) => {
                                println!("{:?}已出现新的区块 {:?}", _type.as_str(), block_number);
                            }
                            // 重发一次
                            Err(_) => _block_sender
                                .send(SendData {
                                    chain: _type.clone(),
                                    block_number,
                                    address: None,
                                })
                                .await
                                .unwrap(),
                        }
                    }
                }
                // 信号量丢弃
                drop(permit);
            })
        });
        // 等待所有异步任务完毕
        let _ = join_all(all_chain_task).await;
    }

    pub async fn check_looper(self: Arc<Self>) {
        loop {
            // 缓存区
            let mut buffer = Vec::new();
            {
                // 一次可接收100条信息
                self.block_receiver
                    .lock()
                    .await
                    .recv_many(&mut buffer, 100)
                    .await;
                println!("buffer {:?}", buffer);
            }

            if buffer.len() > 0 {
                for data in buffer.clone() {
                    // 获取每个地址的值暂存
                    let self_clone = Arc::clone(&self);
                    self_clone
                        .get_state(data.chain.clone(), data.block_number)
                        .await;
                    println!("当前值暂存：{:?}", self.state_cache);
                    let self_clone = Arc::clone(&self);
                    self_clone
                        .check(data.chain.clone(), data.block_number)
                        .await;
                }
                // 检查所有地址的不变量
            }
        }
    }

    async fn check(self: Arc<Self>, chain_type: ChainType, block_number: u64) -> bool {
        println!("链:{:?}", chain_type);
        // 获取该链所有的保护地址
        // 得到所有保护地址的不变量
        // 替换状态变量
        // 拆分
        // 计算
        // 打破则发送信息
        let all_protect_address = self.database.get_address_invar(chain_type.clone());
        println!("所有受保护地址以及其不变量为:{:?}", all_protect_address);
        let _cache = self.state_cache.lock().await;
        let state = _cache.get(&chain_type).clone().unwrap();
        for (addr, mut invar) in all_protect_address {
            let value_maps = state.get(&addr).unwrap();
            for (name, value) in value_maps {
                invar = invar.replace(name, &value.to_string());
            }
            let expressions: Vec<&str> = invar.split("&&").collect();
            // 计算表达式
            for exp in expressions {
                println!("当前计算的表达式为:{:?}", exp);
                if parse_expression(exp, None) == 0 {
                    println!("不变量被打破，触发符号执行");
                    // 创建新任务，并插入符号执行队列
                    self.sym_sender
                        .send(SendData {
                            chain: chain_type.clone(),
                            block_number: block_number,
                            address: Some(addr.clone()),
                        })
                        .await;
                }
            }
        }
        true
    }
    // 每当某条链出块则调用该函数，先将所有保护地址的状态暂存在本地
    pub async fn get_state(self: Arc<Self>, chain_type: ChainType, block_number: u64) {
        println!("self {:?}", self);
        println!("开始获取值暂存");
        // 根据并发访问限制创建信号量
        let rpc_semaphore = Semaphore::new(self.max_rpc_per_seconde);
        // 读取数据库数据
        let data = Arc::clone(&self.database.info);
        // 获取本条链的信息
        let chain_info = Arc::clone(&self.chains).get(&chain_type).unwrap().clone();
        let _cache = data.get(&chain_type).unwrap();
        // 遍历该链的每个地址
        let futures = _cache.iter().flat_map(|(_addr, _pi)| {
            println!("当前地址为：{:?}", _addr);
            // 得到该地址的每个状态变量
            _pi.slot_map.iter().map(|(_var_name, _slot)| async {
                // 复制值
                let _provider = Arc::clone(&chain_info.provider);
                let address_clone = _addr.clone();
                let var_name = _var_name.clone();
                let slot = _slot.clone();
                let chain_type = chain_type.clone();
                // 获取信号量
                let permit = rpc_semaphore.acquire().await.unwrap();

                // 得到value
                let res = _provider
                    .get_storage_at(
                        address_clone.as_str(),
                        H256::from_str(slot.as_str()).unwrap(),
                        Some(BlockId::Number(block_number.into())),
                    )
                    .await;
                // 丢弃信号量
                drop(permit);
                match res {
                    Ok(value) => Ok((
                        chain_type,
                        address_clone,
                        var_name,
                        U256::from_big_endian(value.as_bytes()),
                    )),
                    Err(e) => {
                        print!(
                            "Failed to get storage at address: {} slot: {}: {:?}",
                            address_clone, slot, e
                        );
                        Err(e)
                    }
                }
            })
        });

        // 得到 Chain -> Address -> Slot -> Value
        let results = join_all(futures).await;
        println!("result {:?}", results);
        let mut temp_map: AddressStateCache = HashMap::new();
        for res in results {
            if let Ok((_, address, slot, value)) = res {
                temp_map
                    .entry(address)
                    .or_insert_with(Vec::new)
                    .push((slot, value));
            }
        }
        {
            let mut state_cache = self.state_cache.lock().await;
            state_cache.insert(chain_type, temp_map);
            println!("当前的值暂存为{:?}", state_cache);
        }
    }

    pub async fn sym_looper(self: Arc<Self>) {
        loop {
            // 缓存区
            let mut buffer = Vec::new();
            {
                // 一次可接收100条信息
                self.sym_receiver
                    .lock()
                    .await
                    .recv_many(&mut buffer, 100)
                    .await;
                println!("buffer {:?}", buffer);
            }

            if buffer.len() > 0 {
                for data in buffer.clone() {
                    // 进行符号执行
                    let self_clone = Arc::clone(&self);
                    self_clone
                        .sym_exec(data.chain, data.block_number, data.address.unwrap())
                        .await;
                }
            }
        }
    }

    async fn sym_exec(
        self: Arc<Self>,
        chain_type: ChainType,
        block_number: u64,
        address: String,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let chains = self.chains.clone();
        if let Some(block) = self
            .chains
            .get(&chain_type)
            .unwrap()
            .provider
            .get_block_with_txs(block_number)
            .await?
        {
            // 获得交互的交易
            let interact_txs: Vec<Transaction> = block
                .transactions
                .into_iter()
                .filter(|tx| tx.to == Some(H160::from_str(&address).unwrap()))
                .collect();
            // 对所有交易进行处理
            for tx in interact_txs {
                println!("交互的hash为 {:?}", tx.hash());
                println!("受害的地址为 {:?}", tx.to.unwrap());
                let selector = get_selector(&tx.input);
                println!("受害的函数为 {:?}", selector);
                let exp_map = self.database.clone().get_expression_map(
                    chain_type.clone(),
                    address.clone(),
                    selector,
                );
                println!("当前的所有参数表达式是 {:?}", exp_map);
                for (index, mut param_exp) in exp_map {
                    let _cache = self.state_cache.lock().await;
                    println!("当前的值缓存为 {:?}", _cache);
                    let value_maps = _cache.get(&chain_type).unwrap().get(&address).unwrap();
                    for (name, value) in value_maps {
                        param_exp = param_exp.replace(name, &value.to_string());
                    }
                    // 得到范围
                    let range = evaluate_exp_with_unknown(&param_exp).unwrap();
                    println!("当前的基本范围是{:?}", range);
                    let real_ranges = sym_exec(
                        &chains.get(&chain_type).unwrap().rpc_url.to_string(),
                        tx.hash.encode_hex().as_str(),
                        &address,
                        index,
                        range.0,
                        range.1,
                    )
                    .await;
                    println!("real_ranges {:?}", real_ranges);
                    //todo 发送交易
                }
            }
        }
        Ok(())
    }
}
#[test]
fn test() {}
