// 一个内存模型实现
// rust中一个u8一个字节
use super::utils::errors::ExecutionError;

#[derive(Debug, Clone)]
pub struct Memory {
    pub heap: Vec<u8>,
}

impl Memory {
    // 初始化
    pub fn new(data: Option<Vec<u8>>) -> Self {
        match data {
            Some(_data) => Self { heap: _data },
            None => Self {
                heap: Vec::<u8>::new(),
            },
        }
    }

    // 读取32个字节
    pub fn mload(&self, offset: usize) -> Result<[u8; 32], ExecutionError> {
        Ok(self.heap[offset..offset + 32].try_into().unwrap())
    }

    // 写入32个字节
    pub fn mstore(&mut self, offset: usize, value: [u8; 32]) -> Result<(), ExecutionError> {
        self.resize(offset, 32);
        self.heap[offset..offset + 32].copy_from_slice(&value);
        Ok(())
    }

    fn mstore8(&mut self, offset: usize, value: u8) {
        // 判断value是否为1字节大小
        self.resize(offset, 1);
        self.heap[offset] = value;
    }

    fn resize(&mut self, offset: usize, value_size: usize) {
        let before_size = if offset > self.heap.len() {
            offset + value_size
        } else {
            self.heap.len() + value_size
        };
        let new_size = (before_size + 31) / 32 * 32;
        self.heap.resize(new_size, 0);
    }

    pub fn read(&self, offset: usize, size: usize) -> Result<Vec<u8>, ExecutionError> {
        // 读取函数
        Ok(self.heap[offset..offset + size].to_vec())
    }
    pub fn write(&mut self, offset: usize, value: Vec<u8>) -> Result<(), ExecutionError> {
        self.resize(offset, value.len());
        // 写入函数
        self.heap.extend(value);
        Ok(())
    }
    pub fn msize(&self) -> usize {
        self.heap.len()
    }
}

pub fn pad_left(bytes: &[u8]) -> [u8; 32] {
    let mut padded = [0u8; 32];
    padded[32 - bytes.len()..].copy_from_slice(bytes);
    padded
}
