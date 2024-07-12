mod core_module;
use core_module::utils::errors::ExecutionError;
use mysql::binlog::value;
use primitive_types::U256;
use std::borrow::BorrowMut;
use std::str::FromStr;
// Colored output
use colored::*;
use evm_rs_emulator::paper::my_filed::expression::evaluate_exp_with_unknown;
use evm_rs_emulator::paper::my_filed::sym_exec::sym_exec;
use evm_rs_emulator::paper::my_filed::t3::HandlerTest;
use evm_rs_emulator::paper::my_filed::Handler::Handler;
// use evm_rs_emulator::paper::my_filed::Thread_test::{self, HandlerTest};
use local_ip_address::local_ip;
use std::collections::HashMap;
use std::env;
use std::sync::Arc;

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
