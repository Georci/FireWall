<a name="pCgNv"></a>
# 简介
本代码用于检测重入攻击，给定一笔交易的tx_hash，可检测该交易是否存在重入风险。

检测思想基于数据库并发读写存在的问题。智能合约的重入攻击本质与数据库的并发读写类似。重入是一个递归的过程，即一个函数在执行过程中重新进入该函数。但是在第二次进入该函数时，由于第一次执行过程中所修改的状态并未真正写入状态数据库，因此在本次执行过程中的数据并不一定是正确的，也即数据的脏读写问题。

由上可知，重入攻击的本质即为对数据的脏读写。基于这个思路，我们提出了一种检测重入攻击的新方法，即将根据数据库并发读写存在的问题对重入攻击进行检测。

:::info
数据库并发读写存在的问题如下图
:::
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721012658675-1d3a4315-024a-484f-afda-15e34a007c33.png#averageHue=%23f8f8f7&clientId=u59378234-a788-4&from=paste&height=512&id=u9dfcce35&originHeight=768&originWidth=1855&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=556098&status=done&style=none&taskId=ucdde4108-8481-47dc-bed9-8003994b162&title=&width=1236.6666666666667)

:::info
本代码对于重入攻击的检测基于字节码的执行模式，即由数据库并发读写存在的问题推导出5种重入风险模式。这些重入风险模式的作用是：针对合约的某个状态变量，只要其在交易执行过程中，符合重入风险模式，则认为该状态变量可能被重入攻击。
:::

该代码下一步需要完善读偏差状态机的编写。
<a name="M544y"></a>
# 整体架构
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721012923142-a4fc5c84-3bdb-42d9-b4ab-278048a012b9.png#averageHue=%23f8f7f6&clientId=u59378234-a788-4&from=paste&height=632&id=u15407749&originHeight=948&originWidth=1813&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=367938&status=done&style=none&taskId=uf41a30ba-8994-44d8-b731-b546183868f&title=&width=1208.6666666666667)

<a name="fTjAO"></a>
## 准备工作
针对已有交易，我们可以从以太坊归档节点中读取其call_trace，而后根据call_trace分析其所有call调用路径。重入漏洞的主要特征就是递归，因此其call调用路径必然存在环路。我们下一步就是筛选出存在环路的call调用路径。针对该call调用路径中的重复出现的地址，我们将其所有的storage进行监控。
<a name="KIFVE"></a>
## 检测过程
在准备工作完成后，我们将交易进行重放，并在每次执行完一条指令后，检测storage随着执行过程的变化是否如执行**重入风险模式**一样。一旦检测到某个storage存在风险，则我们认为该交易存在重入风险。

<a name="dMRU9"></a>
# 目录结构
**common模块：包含基本类型的封装**<br />**	- config.py：配置文件，配置rpc使用**<br />**	- constant.py：代码所使用的常量**<br />**	- evm_network.py：以太坊网络的属性封装**<br />**	- evm_opcode.py：指令的具体实现**<br />**	- global_object.py：EVM的基本结构实现**<br />**- detector模块：重入漏洞检测功能**<br />**	- entrypoint.py：初始化重入漏洞检测器**<br />**	- path.py：路径类封装，根据call_trace获得所有调用路径和所有环路调用。**<br />**	- reentrancy_detector.py：重入检测器，用于获得交易信息，检测交易是否存在重入攻击。**<br />**	- state_machin.py：重入检测状态机，包含已定义的重入执行模式。**<br />**	- taint_engine.py：污点分析引擎**<br />**	- test.py：测试代码**<br />**- EXP模块：全网检测时使用的代码**<br />**	- get_all_call_trace.py：获取所有交易的call_trace**<br />**	- find_loop.py：分析交易是否环路**<br />**	- detect_all_tx.py：分析交易是否为重入攻击**<br />**	- foreach_result.py：分析结果**<br />**	- exp_utils.py：工具类**

<a name="vcXDd"></a>
# 主要对象
<a name="WGeF5"></a>
## 状态机
重入风险模式是字节码的执行模式，状态机是每个字节码执行后对执行模式的检测。
```python
class State:
    # 状态号
    number: int
    # 是否为初态
    is_start: bool
    # 是否为终态
    is_final: bool

    def __init__(self,
                 number: int,
                 is_start: bool = False,
                 is_final: bool = False):
        self.number = number
        self.is_start = is_start
        self.is_final = is_final
```

```python
class StateMachine:
    # 当前状态
    state: State
    # 状态集合(状态号=>状态)
    all_states: dict[int, State]
    # 初态序号
    start_state_number = 9999
    # 终态序号
    final_state_number = 10000

    def __init__(self):
        # 开始都是初态
        self.state = State(self.start_state_number, True)
        self.all_states = {self.start_state_number: self.state}

    # 当前状态号
    @property
    def number(self) -> int:
        return self.state.number

    # 当前是否为初态
    @property
    def is_start(self) -> bool:
        return self.state.is_start

    # 当前是否为终态
    @property
    def is_final(self) -> bool:
        return self.state.is_final

    # 设置状态集合
    def set_states(self, state_num: int, state: State):
        self.all_states[state_num] = state

    # 状态切换
    def state_transfer(self, state_num: int):
        self.state = self.all_states[state_num]
```
状态机最主要的内容在下面的代码，每当执行完一个字节码，状态机会检测当前状态是否符合重入风险模式的某个节点，如果符合则状态向后改变。**关键函数为storage_state_change。**
```python
class DirtyRead(ReentrancyStateMachine):
    # 重入调用中第一个sload的depth storage_key => depth
    reentrancy_first_sload_depth: dict[str, int]

    # 设置状态集合
    def __init__(self,
                 address: str,
                 storage_key_list: list[str],
                 to_is_target: bool = False):
        super().__init__(address, storage_key_list, to_is_target)
        self.reentrancy_first_sload_depth = {}

        # 实例化状态
        state0 = State(0)
        state1 = State(1)
        state2 = State(2)
        state3 = State(3)
        state4 = State(4)
        state5 = State(5)
        state6 = State(6)
        state7 = State(7)
        # 初态
        state_start = State(StateMachine.start_state_number, True)
        # 终态
        state_end = State(StateMachine.final_state_number, False, True)

        # 初始化一个用于判断脏读的状态机
        state_machine = StateMachine()
        # 设置状态机的状态集合
        state_machine.set_states(0, state0)
        state_machine.set_states(1, state1)
        state_machine.set_states(2, state2)
        state_machine.set_states(3, state3)
        state_machine.set_states(4, state4)
        state_machine.set_states(5, state5)
        state_machine.set_states(6, state6)
        state_machine.set_states(7, state7)
        state_machine.set_states(StateMachine.start_state_number, state_start)
        state_machine.set_states(StateMachine.final_state_number, state_end)

        # 初始化reentrancy_first_sload_depth和状态机
        for storage_key in self.storage_key_list:
            self.reentrancy_first_sload_depth[storage_key] = 1
            # 每个slot都分别部署一个状态机
            self.state[storage_key] = copy.deepcopy(state_machine)

    # 针对一个storage的状态变化
    def storage_state_change(
        self,
        storage_key: str,
        current_address: str,
        opcode: str,
        depth: int,
        stack: list[str],
    ):
```
<a name="TXvTk"></a>
# 主要功能（代码执行流程）
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721013924691-981fc219-1adf-4e54-822a-4a65dceca20a.png#averageHue=%23272727&clientId=u59378234-a788-4&from=paste&height=292&id=ue999213d&originHeight=438&originWidth=884&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=33759&status=done&style=none&taskId=u9f9c9eae-cbae-44eb-8518-d4c89d5267e&title=&width=589.3333333333334)

<a name="LA9rC"></a>
# 测试用例
进入detector文件夹下的test.py中，修改detect函数中的交易hash即可检查。<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721013973358-b244f184-1892-4c63-929d-b92b1e924c23.png#averageHue=%23282e36&clientId=u59378234-a788-4&from=paste&height=82&id=u8c735a1e&originHeight=123&originWidth=1156&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=46510&status=done&style=none&taskId=uc4a8c501-14fb-47b1-be12-2efecce7475&title=&width=770.6666666666666)
```python
# 导包，sys包用于配置程序执行路径，如果报错如下图1，moduleNotFound，则需要添加该包
import web3
import time
import sys

# 添加路径，路径到EM_Team即可
sys.path.append("your code path")
# 导入模块
from common.config import load_config_file
from common.evm_network import build_rpc_node
from detector.reentrancy_detector import ReentrancyDetector

# 配置网络信息，连接到rpc节点
network = "eth"
config = load_config_file()
network_config = config.networks.get(network)
rpc_node = build_rpc_node(network_config)
# 创建detector，进行重入检查
detector = ReentrancyDetector(rpc_node=rpc_node)
print(rpc_node.web3.is_connected())
# 记录程序开始运行的时间
start = time.perf_counter()
# 重入检测
result = detector.detect(
    '0xd4fafa1261f6e4f9c8543228a67caf9d02811e4ad3058a2714323964a8db61f6')
# 输出为下图2
print(result)
# 记录程序结束运行的时间
end = time.perf_counter()

# 计算程序运行时间
elapsed = end - start
print(f"detector run time is {elapsed} s")
pass
```
**图1**<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721014006491-e71dccb6-aa5a-4643-82a8-03d533de4e82.png#averageHue=%23303842&clientId=u59378234-a788-4&from=paste&height=113&id=u1aa6a43a&originHeight=169&originWidth=1021&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=79751&status=done&style=none&taskId=uc55afee6-57ba-4acc-bd30-f53072b295b&title=&width=680.6666666666666)<br />**图2**<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721014014867-96ba6621-5146-48a5-adf2-e82e7a48b475.png#averageHue=%232d323b&clientId=u59378234-a788-4&from=paste&height=159&id=u0623709e&originHeight=238&originWidth=1795&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=128748&status=done&style=none&taskId=ufd0b5fe8-a7e1-4080-a44f-54632fd055b&title=&width=1196.6666666666667)<br />输出分析：

- True -> 连接到rpc节点
- rpc fetch is ok -> 已经通过rpc节点获得了该交易的信息
- start to detect address:  0xf2919d1d80aff2940274014bef534f7791906ff2 -> 开始检测地址，该地址为在环路call调用路径中重复进入的
- {'0xf2919d1d80aff2940274014bef534f7791906ff2': {0: [], 1: [], 2: [], 3: []} 
   - 0xf2919d1d80aff2940274014bef534f7791906ff2 -> 被检测地址
   - {0: [], 1: [], 2: [], 3: []} -> 0，1，2，3分别代表三个状态机，[]代表没有哪个storage被检测到存在重入风险
   - 下面是一个存在重入风险的例子：
      - '0x9c5a2a6431523fbbc648fb83137a20a2c1789c56': {0: ['0x8', '0x6', '0xa'], 1: ['0xa'], 2: ['0xa'], 3: []}}
      - 0x9c5a2a6431523fbbc648fb83137a20a2c1789c56被检测地址
      - {0: ['0x8', '0x6', '0xa'], 1: ['0xa'], 2: ['0xa'], 3: []}
         - 0: ['0x8', '0x6', '0xa'] -> 被检测地址0x9c5a2a6431523fbbc648fb83137a20a2c1789c56的slot 0x8,0x6,0xa可能被脏读
         - 1: ['0xa'] -> 被检测地址0x9c5a2a6431523fbbc648fb83137a20a2c1789c56的slot 0xa可能被覆盖更新
         - 2: ['0xa'] -> 被检测地址0x9c5a2a6431523fbbc648fb83137a20a2c1789c56的slot 0xa可能出现不可重复读情况
         - 3: [] -> 未检测到写偏差情况

<a name="QTMQW"></a>
# EXP代码
<a name="SxLZG"></a>
## 4.1 get_all_call_trace，获取所有交易的call_trace
代码作用：从rpc_node获取每个块中每笔交易的call_trace，并写入文件。<br />代码使用：<br />    main(10000000,11000000,8,30)<br />        start：10000000     开始区块号<br />        end：11000000       末尾区块号<br />        num：8                     区块号的长度，例如123，则num为3<br />        thread_num：30      使用的线程数，默认为23<br />代码执行结果：<br />    获得从10000000-11000000区块的所有交易的call_trace，所有结果保存在“./pickleFolder”文件夹中。<br />注意：本代码执行后所得到的结果是进行交易环路判断的基本信息，在find_loop文件中的load函数依赖于这些信息。
```python
# 读取pickle文件，该文件中包含了每个块中每笔交易的call_trace
def load(block_number) -> dict:
    # 注意！！！ 这里如果无法读取到信息会报错
    path = f"./pickleFolder/{block_number}.pickle"
    if os.path.getsize(path):
        with open(path, "rb") as f:
            return pickle.load(f)
```
<a name="iVvN8"></a>
## 4.2 find_loop 根据交易的call_trace判断交易是否存在环路，用于缩小数据集
代码作用：读取./pickleFolder中的指定区块区间，分析每个区块的交易call_trace是否存在环路，存在则保存到本地。<br />代码使用：<br />    main(10000000,11000000,8,120)<br />        start：10000000     开始区块号<br />        end：11000000       末尾区块号<br />        num：8                     区块号的长度，例如123，则num为3<br />        thread_num：120      使用的线程数，默认为60<br />代码执行结果：<br />    获得从10000000-11000000区块的所有交易的call_trace，所有结果保存在“./useful_tx”文件夹中，文件夹中的每个文件保存了当前块的环路交易。<br />注意：当前的环路判断存在一个todo，可能遗漏fallback情况，需要进行修改。
```python
    # 这里过滤非函数调用，但是重入存在一个fallback情况，这时的input也小于10.
    if len(calltrace.get("input")) < 10:
        return looplist
    
```
<a name="NOc5v"></a>
## 4.3 extract_tx 提取所有交易到一个文件
代码作用：读取./useful_tx中的指定区块区间，将区块的所有环路交易集中到一个pickle文件中，方便读取。<br />代码使用：<br />    main(10000000,11000000,120)<br />        start：10000000     开始区块号<br />        end：11000000       末尾区块号<br />        thread_num：120      使用的线程数，默认为100<br />代码执行结果：<br />    将10000000-11000000区块的所有环路交易保存到"./all_tx.pickle"中。<br />注意：本函数为一个辅助函数，依赖于./useful_tx文件夹中的内容，如果文件夹中缺少某个区块，则会报错！
<a name="TSjez"></a>
## 4.4 detect_all_tx 检测所有的交易
代码作用：读取tx_path中的所有交易，多进程，多线程的分析交易。将分析结果保存在result_path中。<br />代码使用：<br />    main("all_tx.pickle","./result")<br />        tx_path："all_tx.pickle"     所有交易所在的地址<br />        result_path："./result"       结果保存的地址<br />代码执行结果：<br />    分析all_tx.pickle中的所有交易是否存在重入，保存所有的重入检测结果到./result中。某些检测失败的交易保存在"./problem_tx.pickle"中。
<a name="oqKR0"></a>
## 4.5 foreach_result 遍历结果，得出结论
代码作用：读取result_path中的所有结果，并在控制台输出最终的重入交易比例。<br />代码使用：<br />    main("./result")<br />        result_path："./result"       所有的检测结果所在的地址<br />代码执行结果：<br />    在控制台输出"./result"中重入交易比例
<a name="ZA91p"></a>
## 4.6 全网检测流程

1. 使用get_all_call_trace获得大量交易的call_trace
2. 使用find_loop找出所有的环路交易
3. 使用extract_tx提取所有的环路交易到一个文件中
4. 使用detect_all_tx检测所有的环路交易，并将结果保存
5. 使用foreach_result遍历所有结果，得出重入交易占所有交易的数量

<a name="SXJHA"></a>
# 状态机解析
<a name="PcdBm"></a>
## 脏读
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1721014091300-4ff57e45-0d3a-459e-ac24-a4e03373092b.png#averageHue=%23fcfbfb&clientId=u59378234-a788-4&from=paste&height=770&id=uf53f2c22&originHeight=1155&originWidth=1500&originalType=binary&ratio=1.5&rotation=0&showTitle=false&size=277200&status=done&style=none&taskId=u70957418-3e96-454f-902e-8240ff3a975&title=&width=1000)<br />脏读：

例如：A -> B-1 -> C -> B-2 -> ... -> B-1 -> （B-1代表 地址-call_depth）

在重入过程中,某一层重入时出现了sload指令。

而后在重入回退时又出现了sstore指令，则说明为脏读。

在这里的例子体现为，在B-2时出现sload，而在B-1出现sstore。

  <br />为什么是脏读？

脏读即为读取到了为提交的数据，B-2读取的数据就是未提交数据，因为

B-1时又对数据进行了写入。我们不确定读取的数据是否正确，所以认为

这种情况存在重入风险。

**图解析**

start是初始状态，当交易执行时出现对目标地址的调用时，可能转到状态0或状态1，这取决于to_is_target变量。

to_is_target变量标识交易的to地址是否为目标地址。例如交易call调用为A -> B -> C -> B，则to_is_target为true，因为to地址为B，且B地址重复出现。

to_is_target变量值为true，则call调用中在此调用一次目标地址则说明出现重入。

根据to_is_target来分情况讨论的原因是：当to_is_target时，说明交易的to地址为检测地址，那么当最外层重入结束时，可以直接结束检测。而to_is_not_target，当最外层重入结束时，依然存在可能存在调用，因此需要继续等待最外层call调用无回滚结束

状态1：有三种情况 1）重入直接结束，2）在重入最外层出现sload，3）在重入子调用中出现sload。关键在于sload指令的出现，并且分了两种情况：1）最外层重入，2）重入子调用。

分情况讨论的原因是：如果是在最外层重入中sload，则我们不关心重入子调用，只要当前层不回滚即可；如果是重入子调用中出现sload，我们要关心后续的重入子调用，因为重入子调用回滚将导致父调用也回滚。

状态4，5：在状态4，5时，关心是否有sstore出现在重入的父调用。<br />例如：A -> B-1 -> C -> B-2 -> B-3 -> ... -> B-2，这里的B-2就是重入父调用。

最终，我们需要等到最外层call不回滚才能说明该交易是一笔脏读。

<a name="s9YCp"></a>
# 服务器数据
![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1722306726736-c853c804-2ce3-49d2-b476-c3c75b10d627.png#averageHue=%23222832&clientId=uff6b68ca-8d14-4&from=paste&height=58&id=ue21465de&originHeight=73&originWidth=1006&originalType=binary&ratio=1.25&rotation=0&showTitle=false&size=13639&status=done&style=none&taskId=u0f996a35-6cc4-41ec-9542-a5544e3a4ba&title=&width=804.8)<br />data包含了用得上的数据

1. 21-23年所有交易的call_trace![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1722306961061-3ea46800-4f6b-4d86-9e7f-97535e14f902.png#averageHue=%2321252e&clientId=uff6b68ca-8d14-4&from=paste&height=86&id=ue202ce15&originHeight=129&originWidth=2196&originalType=binary&ratio=1.25&rotation=0&showTitle=false&size=26685&status=done&style=none&taskId=u150cc431-875e-4975-961e-a399df48df2&title=&width=1464)
2. 经过环路筛选的21-23所有交易![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1722307009026-e65fc8cb-d901-4100-9743-d1fd724d3b8d.png#averageHue=%23212732&clientId=uff6b68ca-8d14-4&from=paste&height=44&id=u4f58c598&originHeight=66&originWidth=2185&originalType=binary&ratio=1.25&rotation=0&showTitle=false&size=16178&status=done&style=none&taskId=u8f354759-697e-49c9-9c16-252c9793fea&title=&width=1456.6666666666667)
3. 21-23年每个块的环路交易![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1722307033581-a01bd2c2-2665-468f-ae2b-02f9dc56a4c3.png#averageHue=%23212630&clientId=uff6b68ca-8d14-4&from=paste&height=65&id=yrBy6&originHeight=97&originWidth=2179&originalType=binary&ratio=1.25&rotation=0&showTitle=false&size=22758&status=done&style=none&taskId=ud5993b66-e54a-4872-a3cd-a483755f4c9&title=&width=1452.6666666666667)
4. 21-23年已经跑出来的交易结果![image.png](https://cdn.nlark.com/yuque/0/2024/png/25588623/1722307060110-23a87f64-5e8d-4fd5-9330-46f604c779e5.png#averageHue=%2321252f&clientId=uff6b68ca-8d14-4&from=paste&height=69&id=u9c8d00b5&originHeight=103&originWidth=2197&originalType=binary&ratio=1.25&rotation=0&showTitle=false&size=21745&status=done&style=none&taskId=u6b0735e4-1bc1-4ff8-bd1b-c2ed981c341&title=&width=1464.6666666666667)

注意：

1. 状态机5还未完善
2. 状态机4的实验还没跑完
3. 还有一个文件result，里面包含了很多result，但是最初做实验时没有做标记，所以已经不知道是什么了😂
<a name="jZMsH"></a>
# todoList

1. 状态机5，读偏差状态机的编写

