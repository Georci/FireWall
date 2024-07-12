<a name="M1RqC"></a>
# 简介
智能合约防火墙是保护智能合约安全的有效手段，其主要有四种防护手段：1）参数拦截，2）重入拦截，3）价格操纵拦截，4）黑名单拦截。<br />本项目为智能合约防火墙的参数拦截部分。该模块实时监测被保护合约的不变量，如果出现不变量被打破情况，我们认为合约收到攻击。在此基础上，参数拦截部分可根据已有攻击交易，得到可防御该攻击的参数范围（当前仅支持uint256）。**由此可解决智能合约部署上链后无法进行漏洞修补的问题。**<br />防火墙参数拦截模块使用rust语言编写，使用了ether-rs、tokio、z3以及表达式解析等技术，并提供了自实现的rust-evm。<br />当前参数拦截模块已经是实现了不变量监测、符号执行功能，并使用多线程并发执行提高效率。<br />接下来，针对该项目的首要目标是持续优化系统保持系统的稳定运行，以及寻找链上实例对系统做进一步深度测试。
<a name="LUmMn"></a>
# 整体架构
![](https://cdn.nlark.com/yuque/0/2024/png/25588623/1720364826649-8509c4c7-84dc-4059-9466-53119ef842b7.png#averageHue=%23737373&from=url&id=MZ7xw&originHeight=797&originWidth=1722&originalType=binary&ratio=1.5&rotation=0&showTitle=false&status=done&style=none&title=)<br />防火墙的基本架构如上图。

1. **实时监控公链**：防火墙持续监控公链上的活动。一旦检测到新区块被挖掘，立即获取该区块的基本信息。
2. **触发不变量检查**：当获取到新区块信息后，防火墙会立即触发保护合约的不变量检查机制。如果不变量检查未通过，则认为合约可能遭受了攻击。
3. **获取参数表达式**：在确认可能存在攻击后，防火墙会获取合约项目方预先配置的参数表达式。该表达式用于计算各参数的基本范围。
4. **生成calldata**：根据参数的基本范围，针对每一个参数的取值生成对应的calldata，得到calldata集合。
5. **替换并执行calldata**：防火墙会遍历生成的calldata集合，将每个calldata替换原攻击交易的calldata，并执行新交易。
6. **比较执行序列**：防火墙会将新交易的执行序列与原攻击交易的执行序列进行比较。匹配度高的参数会被收集，从而最终得到可复现攻击的参数集。
<a name="spInH"></a>
# 目录结构

   - **core_module：核心包**
      - **context：evm上下文封装**
      - **opcodes：evm的opcode实现**
      - **utils：工具类**
      - **memory：evm的memory实现**
      - **stack：evm的stack实现**
      - **state：evm的worldstate实现**
      - **runner：evm的interepter实现**
   - **example：一些代码测试**
   - **paper/my_filed：与参数拦截相关的内容**
      - **constants：evm的链类型等常量枚举**
      - **database_mod：数据库模块**
      - **expression：表达式求解实现**
      - **Handler：核心文件，用于整个系统运作调度**
      - **parser：不变量解析模块**
      - **sym_exec：符号执行模块**
      - **t3：最新的Handler实现（Handler的架构处于优化过程）**
<a name="hlofp"></a>
# 主要对象
<a name="ASoch"></a>
## 	Handler对象--系统调度器
```rust
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
    // 出块时的消息发送者
    pub block_sender: Arc<Sender<SendData>>,
    pub block_receiver: Arc<Mutex<Receiver<SendData>>>,
    // 不变量被打破时的消息发送者
    pub sym_sender: Arc<Sender<SendData>>,
    pub sym_receiver: Arc<Mutex<Receiver<SendData>>>,
    // 为每条链的每个地址，暂存当前块的状态，每当出块就进行暂存
    pub state_cache: Arc<Mutex<ChainStateCache>>,
    // 在进行多条链的storage获取时限制rpc的每秒访问次数
    pub max_rpc_per_seconde: usize,
}
// 链信息
#[derive(Debug, Clone)]
pub struct ChainInfo {
    pub rpc_url: String,
    pub provider: Arc<Provider<Ws>>,
}
// 发送的信息
#[derive(Debug, Clone)]
pub struct SendData {
    // 链
    pub chain: ChainType,
    // 区块号
    pub block_number: u64,
    // 地址，这里使用Option的原因是，当address为None时代表这是出块信息，否则为符号执行信息
    pub address: Option<String>,
}
// 地址 -> 值暂存
type AddressStateCache = HashMap<String, Vec<(String, U256)>>;
// 链类型 -> 地址 -> 值暂存
type ChainStateCache = HashMap<ChainType, AddressStateCache>;
```
<a name="UIWg7"></a>
# 主要功能
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1720795310793-6213f4d8-e285-4668-bb61-5cc8c3196917.png#averageHue=%23181818&clientId=u16e4a5b7-b5d9-4&from=paste&height=785&id=otRH4&originHeight=1178&originWidth=2038&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=205825&status=done&style=none&taskId=u5bcf9393-3c54-4c8c-849c-2004e3626a9&title=&width=1358.6666666666667)<br />handler在初始化时，首先将mysql数据库中的数据加载到内存中，避免多次的数据库访问；只在必要时对数据库进行访问。（数据库出现修改）<br />接着，handler会一直监听链上区块，对于每一条支持的链，handler都会为其创建一个异步任务，永远占用一个线程，保证区块监听永远不被阻塞。<br />在一个区块被挖掘出来后，handler会立即发送信息，信息的格式为：
```rust
#[derive(Debug, Clone)]
pub struct SendData {
    // 链
    pub chain: ChainType,
    // 区块号
    pub block_number: u64,
    // 地址，这里使用Option的原因是，当address为None时代表这是出块信息，否则为符号执行信息
    pub address: Option<String>,
}
```
同时，handler维护一个check_looper，一直循环监听是否有handler发送的信息，一旦捕捉到发送的信息，也就说明有至少一条链挖掘出了新的区块，此时需要对该链中的保护合约进行不变量检查。<br />在进行不变量检查时，handler首先获取该链有关状态变量的值，并将其暂存。而后，handler读取保护合约的不变量信息，计算不变量的值是否被打破。（由于保护合约的地址都是确定性的，因此在本地直接保存其对应信息是针对本项目的更优选择。暂时不考虑保护合约非常多的情况，因为在这种情况下服务器的性能肯定可以跟上）<br />如果不变量的值被打破，消息发送者会立马发送符号执行信息，信息格式同上，只是address会存在值，该address就代表不变量被打破的合约地址。<br />handler维护一个sym_looper，一直循环监听handler是否发送符号执行消息。一旦捕捉到消息，则说明有受保护合约疑似收到攻击，则马上从当前块中筛选与受保护合约交互的交易。并读取该受保护合约预先配置的参数表达式。注意，这里的参数表达式可能不只一个。例如函数test(uint256 a,uint256 b)，项目方可以对参数a、b分别配置参数表达式。handler会遍历每个参数表达式，并根据当前链上状态，计算出参数的基本范围。有了基本范围，则根据index，替换当前交互交易的calldata。例如：<br />test(uint256 a,uint256 b)，其calldata为：0xeb8ac921{1}{2}，我们计算出a的基本范围为[1,10]，则生成一系列的calldata集：0xeb8ac921{2}{2}，0xeb8ac921{3}{2}...0xeb8ac921{10}{2}。而后遍历该calldata集，根据不同的calldata重新执行该交互交易。每次执行后的操作码流将被记录，用于比较其与原始calldata执行的操作码流的相似度，如果相似度高于某个阈值，我们认为该参数可得到与原始交易相同的效果。<br />在遍历完所有calldata后，我们得到了一系列的可复现交易的参数值。我们将该参数值反馈到链上（通过发送交易），从而保证受保护项目不再受到类似攻击。<br />在交易发送完毕后，我们将不再监听该受保护合约的不变量，因为经过不变量被打破，当前项目的配置信息已不足以保护其安全，因此可能需要重新配置保护信息。

<a name="AFFws"></a>
# mysql数据库
本项目使用了mysql数据库，版本0.8.0。<br />本项目共有四张表，分别为：address_invariants、chains、expressions和variables。<br />该数据库部分的主要作用是在进行初始化handler时，将数据库的一部分内容缓存在内存中，从而提升执行效率。<br />**todo：当数据库内容更改时，将触发链下部分，从而将数据库的修改同步到链下代码。**
<a name="NnE3d"></a>
## address_invariants表
| id | address | invariant | chain |
| --- | --- | --- | --- |
| 递增id | 保护合约的地址 | 不变量 | 地址所处链 |
| 1 | 0x4b00a35Eb8CAe62337f37FE561d7fF48987a4FED | reserveA + reserveB > 100 && reserveA >10 && reserveB > 10 | ethereum_sepolia |

chain、address、invariant都是一对一的关系，也即一条公链对应一个地址，一个地址也对应一个不变量。

<a name="qmODF"></a>
## chains表
| id | chain_name | chain_rpc |
| --- | --- | --- |
| 递增id | 支持的公链名 | 公链rpc_node |
| 1 | ethereum_sepolia | wss://lb.drpc.org/ogws?network=sepolia&dkey=AvZwUDJNQ0H-rfHFUNlC228dOWBjNHER76RXhkHL9tz4 |

chain_name与chain_rpc是一对一的关系，也即一条链仅能配置一个rpc，该rpc要求为websocket协议，否则将报错。

<a name="XNs1q"></a>
## expressions表
| id | address_id | selector | index | expression |
| --- | --- | --- | --- | --- |
| 递增id | 地址对应的id | 地址对应的函数选择器 | 函数参数下表 | 参数表达式 |
| 1 | 1 | 0x29e99f07 | 0 | param < reserveA && param < reserveB && param >0 |

address_id可以对应一个(chain,address)，因此该表中无需chain字段。<br />address_id与selector是一对多关系，一个地址可以有多个函数。<br />selector与index是一对多关系，一个selector可以有多个index。（注意：index必须为整数类型）<br />index与expression是一对一关系，一个index只有一个expression。

<a name="bFxci"></a>
## variables表
| id | address_id | variable | slot |
| --- | --- | --- | --- |
| 递增id | 地址对应的id | 该合约的状态变量名 | 状态变量所处的slot |
| 1 | 1 | reserveA | 0x00...000 |

address_id可以对应一个(chain,address)，因此该表中无需chain字段。<br />address_id与variable是一对多关系，一个地址可以有多个状态变量。<br />variable与slot是一对一关系，一个状态变量唯一对应一个slot。

<a name="GFCcY"></a>
## 数据库相关代码
<a name="sYkC9"></a>
# 测试用例
```rust
#[tokio::main]
async fn main() {
    let mut handler = HandlerTest::new().await;
    let handler_clone1 = handler.clone();
    let handler_clone2 = handler.clone();
    let _ = tokio::spawn(async move {
        let _ = handler.get_block().await;
    });
    let _ = tokio::spawn(async move {
        let _ = handler_clone1.check_looper().await;
    });
    let _ = tokio::spawn(async move {
        let _ = handler_clone2.sym_looper().await;
    })
    .await;
}

```
由于该系统需要无限循环，因此无法使用test，需要在main函数中编写逻辑进行测试。
<a name="McYMk"></a>
# TodoList

1. 错误处理
2. 系统效率优化
3. 系统健壮性提升
4. 系统模块化
5. 更多的测试用例
