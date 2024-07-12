use crate::core_module::runner::Runner;
use crate::core_module::utils::errors::ExecutionError;

// Primitive types
use ethers::types::U256;

pub fn mload(runner: &mut Runner) -> Result<(), ExecutionError> {
    let offset = U256::from_big_endian(&runner.stack.pop()?);
    let word = unsafe { runner.memory.mload(offset.as_usize())? };
    let result = runner.stack.push(word);

    if result.is_err() {
        return Err(result.unwrap_err());
    }

    // Increment PC
    runner.increment_pc(1)
}

pub fn mstore(runner: &mut Runner) -> Result<(), ExecutionError> {
    let offset = U256::from_big_endian(&runner.stack.pop()?);
    let data = runner.stack.pop()?;

    let result = unsafe { runner.memory.mstore(offset.as_usize(), data) };

    if result.is_err() {
        return Err(result.unwrap_err());
    }

    // Increment PC
    runner.increment_pc(1)
}

pub fn msize(runner: &mut Runner) -> Result<(), ExecutionError> {
    let mut bytes_msize = [0u8; 32];
    U256::from(runner.memory.msize() as u64).to_big_endian(&mut bytes_msize);

    let result = runner.stack.push(bytes_msize);

    if result.is_err() {
        return Err(result.unwrap_err());
    }

    // Increment PC
    runner.increment_pc(1)
}
