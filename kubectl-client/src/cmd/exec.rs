use k8s_openapi::api::core::v1::Pod;
use kube::api::AttachParams;
use kube::{Api, Client};
use mlua::{Lua, Result as LuaResult, Table as LuaTable};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::utils::debug_print;
use crate::with_client;

async fn exec_async(
    lua: &Lua,
    client: &Client,
    pod_name: String,
    cmd: Vec<String>,
) -> LuaResult<String> {
    let pods: Api<Pod> = Api::default_namespaced(client.clone());

    let mut attached = pods
        .exec(
            &pod_name,
            cmd,
            &AttachParams::default().stdin(true).tty(true),
        )
        .await
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    // Split the attached process into stdin and stdout streams.
    let mut proc_stdout = attached.stdout().expect("expected stdout");
    let mut proc_stdin = attached.stdin().expect("expected stdin");

    let _ = debug_print(lua, "testing");
    // Spawn a task to read from the process stdout and write to the Neovim terminal.
    // Replace the placeholder print! with your Neovim terminal output integration.
    let stdout_task = tokio::spawn(async move {
        let mut buf = [0u8; 1024];
        loop {
            match proc_stdout.read(&mut buf).await {
                Ok(0) => break, // EOF
                Ok(n) => {
                    // This should forward the output to Neovim's terminal.
                    print!("{}", String::from_utf8_lossy(&buf[..n]));
                }
                Err(e) => {
                    eprintln!("Error reading process stdout: {:?}", e);
                    break;
                }
            }
        }
    });

    // Spawn a task to read user input from Neovim and write to the process stdin.
    // Replace the simulated input below with your actual Neovim terminal input callback.
    let stdin_task = tokio::spawn(async move {
        // Example: Simulate user input. Replace this with real-time input from Neovim.
        let simulated_input = b"echo 'Hello from Rust interactive exec'\n";
        if let Err(e) = proc_stdin.write_all(simulated_input).await {
            eprintln!("Error writing to process stdin: {:?}", e);
        }
    });

    // Wait for both tasks to complete.
    let _ = tokio::join!(stdout_task, stdin_task);
    attached
        .join()
        .await
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok("".to_string())
}

pub fn exec(lua: &Lua, (pod_name, cmd_table): (String, LuaTable)) -> LuaResult<String> {
    let cmd: Vec<String> = cmd_table.sequence_values().collect::<Result<_, _>>()?;

    with_client(move |client| async move {
        exec_async(lua, &client, pod_name, cmd)
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))
    })
}
