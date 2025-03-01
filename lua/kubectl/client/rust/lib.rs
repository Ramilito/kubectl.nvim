use std::sync::Mutex;

use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::config::KubeConfigOptions;
use kube::core::GroupVersionKind;
use kube::{
    api::{Api, DynamicObject, ListParams},
    Client, Config,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
    let mut rt_guard = RUNTIME.lock().expect("Failed to lock RUNTIME");
    let mut client_guard = CLIENT_INSTANCE
        .lock()
        .expect("Failed to lock CLIENT_INSTANCE");

    // Create a new runtime.
    let new_rt = Runtime::new().expect("Failed to create Tokio runtime");

    // Create a new client with an optional context.
    let new_client = new_rt.block_on(async {
        let options = KubeConfigOptions {
            context: context_name.clone(),
            cluster: None,
            user: None,
        };
        let config = Config::from_kubeconfig(&options)
            .await
            .expect("Failed to load kubeconfig");
        Client::try_from(config).expect("Failed to create Kubernetes client")
    });

    // Replace any existing runtime/client.
    *rt_guard = Some(new_rt);
    *client_guard = Some(new_client);

    println!("Client initialized with context: {:?}", context_name);
    Ok(true)
}

// /// Initializes the Tokio runtime and Kubernetes client with an optional context name.
// fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
//     // Initialize the runtime if it hasn't been already.
//     let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
//
//     // Initialize the Kubernetes client with a specific context.
//     CLIENT_INSTANCE.get_or_init(|| {
//         rt.block_on(async {
//             let options = KubeConfigOptions {
//                 context: context_name.clone(),
//                 cluster: None,
//                 user: None,
//             };
//
//             let config = Config::from_kubeconfig(&options)
//                 .await
//                 .expect("Failed to load kubeconfig");
//             Client::try_from(config).expect("Failed to create Kubernetes client")
//         })
//     });
//
//     println!("Client initialized with context: {:?}", context_name);
//     Ok(true)
// }

fn get_resource(
    _lua: &Lua,
    (resource, group, version, name, namespace): (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    // Grab our runtime and client.
    let rt_opt = RUNTIME.lock().expect("Failed to lock RUNTIME");
    let client_opt = CLIENT_INSTANCE
        .lock()
        .expect("Failed to lock CLIENT_INSTANCE");
    let rt = rt_opt
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Tokio Runtime not initialized".to_string()))?;
    let client = client_opt.as_ref().ok_or_else(|| {
        mlua::Error::RuntimeError("Kubernetes Client not initialized".to_string())
    })?;

    // Build GroupVersionKind with defaults if not provided.
    let group_str: String = group.unwrap_or_default();
    let version_str: String = version.unwrap_or_else(|| "v1".to_string());
    let gvk = GroupVersionKind {
        group: group_str,
        version: version_str,
        kind: resource,
    };

    // Create the dynamic ApiResource from the GVK.
    let ar: ApiResource = ApiResource::from_gvk(&gvk);

    // Construct Api<DynamicObject>, namespaced or all.
    let api: Api<DynamicObject> = if let Some(ns) = namespace {
        Api::namespaced_with(client.clone(), &ns, &ar)
    } else {
        Api::all_with(client.clone(), &ar)
    };

    // Use default ListParams.
    let lp: ListParams = ListParams::default();

    // Perform GET or LIST within the Tokio runtime.
    let fetch_result: Result<Vec<DynamicObject>, kube::Error> = rt.block_on(async {
        if let Some(n) = name {
            // Single GET
            let obj = api.get(&n).await?;
            Ok(vec![obj])
        } else {
            // LIST
            let list = api.list(&lp).await?;
            Ok(list.items)
        }
    });

    // Convert any kube::Error to an mlua::Error.
    let items: Vec<DynamicObject> =
        fetch_result.map_err(|e: kube::Error| mlua::Error::RuntimeError(e.to_string()))?;

    // Convert to single-line JSON.
    let json_str: String =
        serde_json::to_string(&items).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    Ok(json_str)
}

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set("get_resource", lua.create_function(get_resource)?)?;

    Ok(exports)
}
