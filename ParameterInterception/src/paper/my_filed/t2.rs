// use super::constants::ChainType;
// use super::database_mod::{DatabaseManager, ProtectInfo};
// use super::expression::evaluate_exp_with_unknown;
// use super::sym_exec::sym_exec;
// use crate::paper::my_filed::parser::parse_expression;
// use ethers::abi::{AbiEncode, Hash};
// use ethers::types::{BlockId, Bytes, Transaction, H160, H256};
// use ethers_providers::{Middleware, Provider, StreamExt, Ws};
// use futures::future::join_all;
// use primitive_types::U256;
// use revm_primitives::HashMap;
// use std::collections::VecDeque;
// use std::str::FromStr;
// use std::sync::Arc;
// use tokio::sync::mpsc::{self, Receiver, Sender};
// use tokio::sync::{Mutex, Semaphore};
// use tokio::time::{self, Duration};
// use tracing::{debug, error, info, span, warn, Level};
// #[derive(Debug)]
// pub enum HandlerError {
//     RpcProviderError(ethers_providers::ProviderError),
//     DatabaseError(String),
//     InvalidAddress(String),
//     InvariantCheckFailed(String),
//     SymExecFailed(String),
//     TaskQueueError,
//     Other(String),
// }

// impl From<ethers_providers::ProviderError> for HandlerError {
//     fn from(error: ethers_providers::ProviderError) -> Self {
//         HandlerError::RpcProviderError(error)
//     }
// }

// impl std::fmt::Display for HandlerError {
//     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
//         match self {
//             HandlerError::RpcProviderError(e) => write!(f, "RPC provider error: {}", e),
//             HandlerError::DatabaseError(e) => write!(f, "Database error: {}", e),
//             HandlerError::InvalidAddress(e) => write!(f, "Invalid address: {}", e),
//             HandlerError::InvariantCheckFailed(e) => write!(f, "Invariant check failed: {}", e),
//             HandlerError::SymExecFailed(e) => write!(f, "Symbolic execution failed: {}", e),
//             HandlerError::TaskQueueError => write!(f, "SymTask queue error"),
//             HandlerError::Other(e) => write!(f, "Other error: {}", e),
//         }
//     }
// }

// impl std::error::Error for HandlerError {}

// #[derive(Debug, Clone)]
// pub struct SymTask {
//     pub chain: ChainType,
//     pub block_number: u64,
//     pub address: String,
// }

// #[derive(Debug, Clone)]
// pub struct HandleTable {
//     // 当前区块
//     pub block_number: u64,
//     // todo 链的区块数量不一定一样，所以需要修改的地方还很多！！！
//     // 状态变量对照表
//     // 链 => ChainState
//     pub state_table: HashMap<String, ChainState>,
// }
// #[derive(Debug, Clone)]
// pub struct ChainBlock {
//     pub chain: String,
//     pub block_number: u64,
// }

// #[derive(Debug, Clone)]
// pub struct ChainState {
//     // 地址 => 值暂存
//     pub state: HashMap<String, Vec<(String, U256)>>,
// }

// #[derive(Debug, Clone)]
// pub struct HandlerTest {
//     // rpcUrl
//     rpc: HashMap<String, String>,
//     // rpcProvider
//     rpc_providers: HashMap<String, Arc<Provider<Ws>>>,
//     // 信号量：为了确保不同操作之间能够有效并行处理，将信号量进行分割
//     info_semaphore: Arc<Semaphore>,
//     check_semaphore: Arc<Semaphore>,
//     sym_semaphore: Arc<Semaphore>,
//     // 数据库模块
//     database: Arc<Mutex<DatabaseManager>>,
//     // 不变量检查使用消息发送
//     check_receiver: Arc<Mutex<Receiver<ChainBlock>>>,
//     check_sender: Arc<Mutex<Sender<ChainBlock>>>,
//     // 符号执行检查
//     sym_receiver: Arc<Mutex<Receiver<SymTask>>>,
//     sym_sender: Sender<SymTask>,
//     max_per_second: usize, // 每秒最大并发量
//     handle_table: Arc<Mutex<HandleTable>>,
// }

// impl HandlerTest {
//     pub async fn new(
//         rpc: HashMap<String, String>,
//         sql_url: String,
//     ) -> Result<Self, Box<dyn std::error::Error>> {
//         let mut rpc_providers = HashMap::new();
//         for (_chain, _rpc) in rpc.iter() {
//             let rpc_provider = Arc::new(
//                 Provider::<Ws>::connect(_rpc)
//                     .await
//                     .map_err(HandlerError::RpcProviderError)?,
//             );
//             rpc_providers.insert(_chain.clone(), rpc_provider);
//         }

//         // 信号量初始化，根据cpu线程数量来指定信号量的值
//         let cpu_count = num_cpus::get();
//         println!("当前cpu可支持的线程数为：{}", cpu_count);

//         let info_semaphore = Arc::new(Semaphore::new(8));
//         let check_semaphore = Arc::new(Semaphore::new(4));
//         let sym_semaphore = Arc::new(Semaphore::new(4));

//         let mut database = DatabaseManager::new(&sql_url)
//             .map_err(|e| HandlerError::DatabaseError(e.to_string()))?;

//         // 数据库模块加载初始值
//         database
//             .load_data_for_cache()
//             .map_err(|e| HandlerError::DatabaseError(e.to_string()))?;

//         // 创建通道
//         let (check_sender, check_receiver): (Sender<ChainBlock>, Receiver<ChainBlock>) =
//             mpsc::channel(10);
//         let (sym_sender, sym_receiver): (Sender<SymTask>, Receiver<SymTask>) = mpsc::channel(10);

//         // chain => 地址的复制
//         let addresses = database.protect_addresses.clone();
//         let mut temp_table = HashMap::new();
//         for (chain, addr_vec) in addresses {
//             let mut temp_map = HashMap::new();
//             for addr in addr_vec {
//                 temp_map.insert(addr, Vec::<(String, U256)>::new());
//             }
//             let chain_state = ChainState { state: temp_map };
//             temp_table.insert(chain, chain_state);
//         }

//         let handle_table = Arc::new(Mutex::new(HandleTable {
//             block_number: 0,
//             state_table: temp_table,
//         }));

//         Ok(Self {
//             rpc,
//             rpc_providers,
//             info_semaphore,
//             check_semaphore,
//             sym_semaphore,
//             database: Arc::new(Mutex::new(database)),
//             check_sender: Arc::new(Mutex::new(check_sender)),
//             check_receiver: Arc::new(Mutex::new(check_receiver)),
//             sym_sender,
//             sym_receiver: Arc::new(Mutex::new(sym_receiver)),
//             max_per_second: 40,
//             handle_table,
//         })
//     }

//     pub async fn get_block(self: Arc<Self>) -> Result<(), HandlerError> {
//         println!(
//             "尝试获取 info_semaphore，当前可用许可数：{}",
//             self.info_semaphore.available_permits()
//         );
//         let mut tasks = vec![];
//         // 同时监听多条链
//         for (chain, rpc_provider) in self.rpc_providers.iter() {
//             let check_sender = Arc::clone(&self.check_sender);
//             let info_semaphore = self.info_semaphore.clone();
//             let chain = chain.clone();
//             let rpc_provider = Arc::clone(rpc_provider);
//             println!("开始获取{:?}的区块信息", chain);

//             let task = tokio::spawn(async move {
//                 let permit = info_semaphore.acquire_owned().await.unwrap();
//                 // 订阅区块信息
//                 let mut block_stream = match rpc_provider.subscribe_blocks().await {
//                     Ok(block_stream) => block_stream,
//                     Err(_) => rpc_provider.subscribe_blocks().await.unwrap(),
//                 };
//                 while let Some(block) = block_stream.next().await {
//                     let block_number = block.number.unwrap().as_u64();
//                     {
//                         let sender = check_sender.lock().await;
//                         match sender
//                             .send(ChainBlock {
//                                 chain: chain.clone(),
//                                 block_number,
//                             })
//                             .await
//                         {
//                             Ok(_) => {
//                                 println!("链 {:?}已出现新的区块 {:?}", chain, block_number);
//                             }
//                             // 重发一次
//                             Err(_) => {
//                                 let send_data = ChainBlock {
//                                     chain: chain.clone(),
//                                     block_number,
//                                 };
//                                 sender.send(send_data.clone()).await.unwrap()
//                             }
//                         }
//                     }
//                 }
//                 // 线程释放
//                 drop(permit);
//             });
//             tasks.push(task);
//         }

//         for task in tasks {
//             task.await.unwrap();
//         }

//         Ok(())
//     }

//     pub async fn check_looper(self: Arc<Self>) {
//         loop {
//             // 当接收到消息
//             if let Some(chain_block) = self.check_receiver.lock().await.recv().await {
//                 // 锁住表，更新区块
//                 let mut handle_table = self.handle_table.lock().await;
//                 handle_table.block_number = chain_block.block_number;
//                 println!("handle_table {:?}", handle_table);
//                 drop(handle_table);

//                 // 占用线程
//                 let permit = self.info_semaphore.clone().acquire_owned().await.unwrap();

//                 println!(
//                     "info_semaphore 剩余可用线程数：{:?}",
//                     self.info_semaphore.available_permits()
//                 );

//                 // 构建值缓存
//                 self.clone().get_state(block_number).await;
//                 drop(permit);

//                 println!(
//                     "check_semaphore 剩余可用线程数：{:?}",
//                     self.check_semaphore.available_permits()
//                 );
//                 let permit = self.info_semaphore.clone().acquire_owned().await.unwrap();
//                 // 检查不变量是否被打破
//                 if let Err(e) = self.clone().check().await {
//                     error!("Error during check: {}", e);
//                 }
//                 drop(permit);
//             }
//         }
//     }

//     async fn check(self: Arc<Self>) -> Result<(), HandlerError> {
//         let start = time::Instant::now();
//         let handle_table = &self.handle_table.lock().await;
//         let state_table = &handle_table.state_table;
//         let block_number = handle_table.block_number;

//         for (address, values) in state_table {
//             let state = values.state.get(address).unwrap();
//             let invariant = self.get_invariant(&address, state).await.unwrap();
//             // 将不变量中的状态变量都替换为其最新的值
//             // 根据&&分割表达式
//             let expressions: Vec<&str> = invariant.split("&&").collect();
//             // 计算表达式
//             for exp in expressions {
//                 if parse_expression(exp, None) == 0 {
//                     println!("不变量被打破，触发符号执行");
//                     let _ = self
//                         .sym_sender
//                         .send(SymTask {
//                             block_number,
//                             address: address.clone(),
//                         })
//                         .await;
//                 }
//             }
//         }
//         let end = time::Instant::now();
//         println!("不变量检查消耗时间：{:?}", end - start);
//         Ok(())
//     }

//     async fn get_invariant(
//         &self,
//         address: &str,
//         values: &Vec<(String, U256)>,
//     ) -> Result<String, HandlerError> {
//         // 首先获得保护信息
//         let all_pi = self.database.lock().await.clone().protect_infos;
//         let pi = all_pi
//             .get(address)
//             .ok_or_else(|| HandlerError::InvalidAddress(address.to_string()))?;
//         let mut invariant = pi.invariant.clone();

//         for (name, value) in values {
//             invariant = invariant.replace(name, &value.to_string());
//         }

//         println!("不变量 {:?}", invariant);
//         Ok(invariant)
//     }

//     pub async fn sym_looper(self: Arc<Self>) {
//         loop {
//             if let Some(task) = self.sym_receiver.lock().await.recv().await {
//                 println!("sym_task {:?}", task);
//                 let permit = self.info_semaphore.clone().acquire_owned().await.unwrap();
//                 println!(
//                     "剩余可用线程数：{:?}",
//                     self.sym_semaphore.available_permits()
//                 );
//                 if let Err(e) = self.clone().sym_exec(task.block_number, task.address).await {
//                     error!("Error during symbolic execution: {}", e);
//                 }

//                 drop(permit);
//             }
//         }
//     }

//     async fn sym_exec(
//         self: Arc<Self>,
//         block_number: u64,
//         address: String,
//     ) -> Result<(), HandlerError> {
//         if let Some(block) = self.rpc_provider.get_block_with_txs(block_number).await? {
//             let interact_txs: Vec<Transaction> = block
//                 .transactions
//                 .into_iter()
//                 .filter(|tx| tx.to == Some(H160::from_str(&address).unwrap()))
//                 .collect();
//             println!("interact tx {:?}", interact_txs);

//             let all_pi = self.database.lock().await.clone().protect_infos;
//             let pi = all_pi
//                 .get(&address)
//                 .ok_or_else(|| HandlerError::InvalidAddress(address.clone()))?;
//             for tx in interact_txs {
//                 let selector = get_selector(&tx.input);
//                 if let Some(index_exp) = pi.expression_map.get(&selector) {
//                     let cache_lock = &self.handle_table.lock().await;
//                     let state_var_cache = &cache_lock.state_table;
//                     for (index, exp) in index_exp {
//                         let mut new_expression = exp.to_string();
//                         for (name, value) in state_var_cache.get(&address).unwrap() {
//                             new_expression = new_expression.replace(name, &value.to_string());
//                         }
//                         let (min, max) = evaluate_exp_with_unknown(&new_expression)
//                             .map_err(|e| HandlerError::Other(e.to_string()))?;
//                         sym_exec(
//                             &self.rpc,
//                             tx.hash.encode_hex().as_str(),
//                             &address,
//                             index.clone(),
//                             min,
//                             max,
//                         )
//                         .await
//                         .map_err(|e| HandlerError::SymExecFailed(e.to_string()))?;
//                         // todo 发送交易，修改不变量
//                         {
//                             let mut cache_lock = self.handle_table.lock().await;
//                             cache_lock.state_table.remove(&address);
//                         }
//                     }
//                 } else {
//                     // todo 非注册函数，不做处理，但是这时不变量依然被打破
//                 }
//             }
//         }
//         Ok(())
//     }

//     async fn get_state(self: Arc<Self>, block_number: u64) {
//         let start = time::Instant::now();
//         let data = self.database.lock().await.clone().protect_infos;
//         let semaphore = Arc::new(Semaphore::new(self.max_per_second));

//         let futures = data.iter().flat_map(|(address, pi)| {
//             pi.slot_map.iter().map(|(_name, _slot)| {
//                 let provider = Arc::clone(&self.rpc_provider);
//                 let address_clone = address.clone();
//                 let slot = _slot.clone();
//                 let semaphore = Arc::clone(&semaphore);
//                 async move {
//                     let permit = semaphore.acquire().await.unwrap();
//                     let result = provider
//                         .get_storage_at(
//                             address_clone.as_str(),
//                             H256::from_str(&slot).unwrap(),
//                             Some(BlockId::Number(block_number.into())),
//                         )
//                         .await;
//                     drop(permit);

//                     match result {
//                         Ok(value) => Ok((
//                             address_clone,
//                             _name.clone(),
//                             U256::from_big_endian(value.as_bytes()),
//                         )),
//                         Err(e) => {
//                             error!(
//                                 "Failed to get storage at address: {} slot: {}: {:?}",
//                                 address_clone, slot, e
//                             );
//                             Err(e)
//                         }
//                     }
//                 }
//             })
//         });

//         let results: Vec<_> = join_all(futures).await;
//         let mut final_results = Vec::new();
//         for res in results {
//             if let Ok((address, name, value)) = res {
//                 final_results.push((address, name, value));
//             }
//         }

//         // 更新缓存
//         let mut new_state_table = HashMap::new();
//         for (address, name, value) in final_results {
//             new_state_table
//                 .entry(address.to_string())
//                 .or_insert_with(Vec::new)
//                 .push((name, value));
//         }

//         // 获取锁并替换 state_table
//         {
//             let mut cache_lock = self.handle_table.lock().await;
//             cache_lock.state_table = new_state_table;
//         }

//         let end = time::Instant::now();
//         println!("构建值缓存花费时间 {:?}", end - start);
//     }
// }

// pub fn get_selector(input: &Bytes) -> String {
//     format!("0x{}", hex::encode(&input[..4]))
// }

// #[tokio::test]
// async fn test() {
//     let sql_url = format!("mysql://root:1234@{}:3306/new_data", "172.29.218.244");
//     let mut _handler = HandlerTest::new(
//         "wss://eth-sepolia.g.alchemy.com/v2/OHqKhm7IeJM6N54ff9ZpcGfCxPAj0Y6Y".to_string(),
//         sql_url,
//     )
//     .await
//     .unwrap();
//     let handler = Arc::new(_handler);
// }
