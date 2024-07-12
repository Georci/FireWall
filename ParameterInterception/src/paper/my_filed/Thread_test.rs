// use super::database_mod::DatabaseManager;
// use super::expression::evaluate_exp_with_unknown;
// use super::sym_exec::sym_exec;
// use crate::paper::my_filed::parser::parse_expression;
// use ethers::abi::AbiEncode;
// use ethers::types::{Bytes, Transaction, H160, H256};
// use ethers_providers::{Middleware, Provider, StreamExt, Ws};
// use futures::future::join_all;
// use primitive_types::U256;
// use revm_primitives::HashMap;
// use std::collections::VecDeque;
// use std::str::FromStr;
// use std::sync::Arc;
// use tokio::sync::{Mutex, Semaphore};
// use tokio::time::{self, Duration};
// use tracing::{debug, error, info, span, warn, Level};
// use tracing_subscriber::FmtSubscriber;
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
//             HandlerError::TaskQueueError => write!(f, "Task queue error"),
//             HandlerError::Other(e) => write!(f, "Other error: {}", e),
//         }
//     }
// }

// impl std::error::Error for HandlerError {}

// #[derive(Debug, Clone)]
// pub struct Task {
//     pub block_number: u64,
//     pub address: String,
// }

// #[derive(Debug)]
// pub struct HandlerTest {
//     // rpcUrl
//     rpc: String,
//     // rpcProvider
//     rpc_provider: Arc<Provider<Ws>>,
//     // 所有的保护地址
//     protect_addresses: Vec<String>,
//     // 信号量：用于并发量控制，为了确保不同操作之间能够有效并行处理，将信号量进行分割
//     info_semaphore: Arc<Semaphore>,
//     check_semaphore: Arc<Semaphore>,
//     sym_semaphore: Arc<Semaphore>,
//     // 数据库模块
//     database: Arc<DatabaseManager>,
//     // 地址 => 值暂存
//     // 值缓存，variable_name => value
//     state_var_cache: Mutex<HashMap<String, Vec<(String, U256)>>>,
//     // 不变量检查待处理队列
//     check_queue: Arc<Mutex<VecDeque<Task>>>,
//     // 符号执行待处理队列
//     sym_exec_queue: Arc<Mutex<VecDeque<Task>>>,
//     max_per_second: usize, // 每秒最大并发量
// }

// impl HandlerTest {
//     pub async fn new(rpc: String, sql_url: String) -> Result<Self, Box<dyn std::error::Error>> {
//         let rpc_provider = Arc::new(
//             Provider::<Ws>::connect(&rpc)
//                 .await
//                 .map_err(HandlerError::RpcProviderError)?,
//         );

//         // 根据cpu线程数量来指定信号量的值
//         let cpu_count = num_cpus::get();
//         info!("当前cpu可支持的线程数为：{}", cpu_count);

//         let info_semaphore = Arc::new(Semaphore::new(4));
//         let check_semaphore = Arc::new(Semaphore::new(4));
//         let sym_semaphore = Arc::new(Semaphore::new(4));
//         let mut database = DatabaseManager::new(&sql_url)
//             .map_err(|e| HandlerError::DatabaseError(e.to_string()))?;

//         // 数据库模块加载初始值
//         database
//             .load_data_for_cache()
//             .map_err(|e| HandlerError::DatabaseError(e.to_string()))?;

//         // 初始化值缓存
//         let mut state_var_cache = HashMap::new();
//         for addr in database.protect_addresses.clone() {
//             state_var_cache.insert(addr, Vec::<(String, U256)>::new());
//         }

//         Ok(Self {
//             rpc,
//             rpc_provider,
//             protect_addresses: database.protect_addresses.clone(),
//             info_semaphore,
//             check_semaphore,
//             sym_semaphore,
//             database: Arc::new(database),
//             state_var_cache: Mutex::new(state_var_cache),
//             check_queue: Arc::new(Mutex::new(VecDeque::new())),
//             sym_exec_queue: Arc::new(Mutex::new(VecDeque::new())),
//             max_per_second: 40,
//         })
//     }

//     pub async fn get_block(&self) -> Result<(), HandlerError> {
//         // 永远占用一个线程
//         let _permit = self.info_semaphore.clone().acquire_owned().await.unwrap();
//         info!("开始获取区块信息");
//         // 订阅区块信息
//         let mut block_stream = self.rpc_provider.subscribe_blocks().await?;
//         while let Some(block) = block_stream.next().await {
//             let block_number = block.number.unwrap().as_u64();
//             info!("已出现新的区块 {:?}", block_number);

//             // 在出现新区块时，锁住不变量检查队列，传输任务
//             let mut check_queue = self.check_queue.lock().await;
//             for address in &self.protect_addresses {
//                 check_queue.push_back(Task {
//                     block_number,
//                     address: address.clone(),
//                 });
//             }
//         }
//         drop(_permit);
//         Ok(())
//     }

//     pub async fn check_trigger(self: Arc<Self>) {
//         // 一直查询check_queue，有了新的信息则添加
//         loop {
//             if let Some(task) = self.pop_task(&self.check_queue).await {
//                 // 占用一个线程进行不变量检查处理
//                 let permit = self.check_semaphore.clone().acquire_owned().await.unwrap();
//                 info!(
//                     "剩余可用线程数：{:?}",
//                     self.check_semaphore.available_permits()
//                 );

//                 // 构建值缓存
//                 self.clone().get_state().await;

//                 // 检查不变量是否被打破
//                 if let Err(e) = self.clone().check(task).await {
//                     error!("Error during check: {}", e);
//                 }

//                 // 丢弃信号量，放弃对线程的占用
//                 drop(permit);
//             } else {
//                 // 等待0.1s
//                 tokio::time::sleep(Duration::from_millis(100)).await;
//             }
//         }
//     }

//     async fn check(self: Arc<Self>, task: Task) -> Result<(), HandlerError> {
//         let start = time::Instant::now();
//         // 将不变量中的状态变量都替换为其最新的值
//         let invariant = self.get_invariant(&task.address).await?;
//         // 根据&&分割表达式
//         let expressions: Vec<&str> = invariant.split("&&").collect();

//         // 计算表达式
//         for exp in expressions {
//             if parse_expression(exp, None) == 0 {
//                 info!("不变量被打破，触发符号执行");
//                 // 创建新任务，并插入符号执行队列
//                 self.push_task(&self.sym_exec_queue, task.clone()).await;
//             }
//         }

//         let end = time::Instant::now();
//         info!("不变量检查消耗时间：{:?}", end - start);
//         Ok(())
//     }

//     async fn get_invariant(&self, address: &str) -> Result<String, HandlerError> {
//         // 首先获得保护信息
//         let data = self
//             .database
//             .protect_infos
//             .get(address)
//             .ok_or_else(|| HandlerError::InvalidAddress(address.to_string()))?;

//         let mut invariant = data.invariant.clone();

//         // 根据值缓存来替换
//         let state = self.state_var_cache.lock().await;
//         let all_state = state.get(address).unwrap();

//         for (name, value) in all_state {
//             invariant = invariant.replace(name, &value.to_string());
//         }

//         info!("不变量 {:?}", invariant);
//         Ok(invariant)
//     }

//     pub async fn sym_exec_trigger(self: Arc<Self>) {
//         loop {
//             if let Some(task) = self.pop_task(&self.sym_exec_queue).await {
//                 info!("sym_task {:?}", task);
//                 let permit = self.sym_semaphore.clone().acquire_owned().await.unwrap();
//                 info!(
//                     "剩余可用线程数：{:?}",
//                     self.sym_semaphore.available_permits()
//                 );

//                 if let Err(e) = self.clone().sym_exec(task).await {
//                     error!("Error during symbolic execution: {}", e);
//                 }

//                 drop(permit);
//             } else {
//                 tokio::time::sleep(Duration::from_millis(100)).await;
//             }
//         }
//     }

//     async fn sym_exec(self: Arc<Self>, task: Task) -> Result<(), HandlerError> {
//         let block_number = task.block_number;
//         if let Some(block) = self.rpc_provider.get_block_with_txs(block_number).await? {
//             let interact_txs: Vec<Transaction> = block
//                 .transactions
//                 .into_iter()
//                 .filter(|tx| tx.to == Some(H160::from_str(&task.address).unwrap()))
//                 .collect();
//             info!("interact tx {:?}", interact_txs);

//             let pi = self
//                 .database
//                 .protect_infos
//                 .get(&task.address)
//                 .ok_or_else(|| HandlerError::InvalidAddress(task.address.clone()))?;

//             for tx in interact_txs {
//                 let selector = get_selector(&tx.input);
//                 if let Some(index_exp) = pi.expression_map.get(&selector) {
//                     let state_var_cache = self.state_var_cache.lock().await;
//                     let cache = state_var_cache.get(&task.address).unwrap().clone();
//                     drop(state_var_cache);

//                     for (index, exp) in index_exp {
//                         let mut new_expression = exp.to_string();
//                         for (name, value) in cache.iter() {
//                             new_expression = new_expression.replace(name, &value.to_string());
//                         }
//                         let (min, max) = evaluate_exp_with_unknown(&new_expression)
//                             .map_err(|e| HandlerError::Other(e.to_string()))?;
//                         sym_exec(
//                             &self.rpc,
//                             tx.hash.encode_hex().as_str(),
//                             &task.address,
//                             index.clone(),
//                             min,
//                             max,
//                         )
//                         .await
//                         .map_err(|e| HandlerError::SymExecFailed(e.to_string()))?;
//                         // todo 发送交易，修改不变量
//                     }
//                 }
//             }
//         }
//         Ok(())
//     }

//     async fn pop_task(&self, queue: &Mutex<VecDeque<Task>>) -> Option<Task> {
//         let mut task_queue = queue.lock().await;
//         task_queue.pop_front()
//     }

//     async fn push_task(&self, queue: &Mutex<VecDeque<Task>>, task: Task) {
//         let mut task_queue = queue.lock().await;
//         task_queue.push_back(task);
//     }

//     async fn get_state(self: Arc<Self>) {
//         let start = time::Instant::now();
//         let data = self.database.protect_infos.clone();
//         let mut futures = Vec::new();
//         let semaphore = Arc::new(Semaphore::new(self.max_per_second));

//         for (address, pi) in data.iter() {
//             for (_name, _slot) in pi.slot_map.iter() {
//                 let provider = self.rpc_provider.clone();
//                 let address_clone = address.clone();
//                 let slot_clone = _slot.clone();
//                 let s = semaphore.clone();

//                 let future = async move {
//                     let _permit = s.acquire().await.unwrap();
//                     let result = provider
//                         .get_storage_at(
//                             address_clone.as_str(),
//                             H256::from_str(&slot_clone).unwrap(),
//                             None,
//                         )
//                         .await;
//                     drop(_permit);

//                     match result {
//                         Ok(value) => Ok((
//                             address_clone,
//                             _name,
//                             U256::from_big_endian(value.as_bytes()),
//                         )),
//                         Err(e) => {
//                             error!(
//                                 "Failed to get storage at address: {} slot: {}: {:?}",
//                                 address_clone, slot_clone, e
//                             );
//                             Err(e)
//                         }
//                     }
//                 };
//                 futures.push(future);
//             }
//         }

//         let results: Vec<_> = join_all(futures).await;

//         let mut final_results = Vec::new();

//         for res in results {
//             if let Ok((address, name, value)) = res {
//                 final_results.push((address, name, value));
//             }
//         }

//         let mut cache = self.state_var_cache.lock().await;
//         for (address, name, value) in final_results {
//             cache
//                 .entry(address)
//                 .or_insert_with(Vec::new)
//                 .push((name.to_string(), value));
//         }
//         let end = time::Instant::now();
//         info!("构建值缓存花费时间 {:?}", end - start);
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
//     let _ = handler.get_state().await;
// }
