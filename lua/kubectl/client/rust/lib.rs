use k8s_openapi::serde_json;
use kube::api::ApiResource;
use kube::core::GroupVersionKind;
use kube::{
    api::{Api, DynamicObject, ListParams},
    Client,
};
use mlua::prelude::*;
use std::sync::OnceLock;
use tokio::runtime::Runtime;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static CLIENT_INSTANCE: OnceLock<Client> = OnceLock::new();

/// Initializes the Tokio runtime and Kubernetes client only once.
fn init_client(_lua: &Lua, _: ()) -> LuaResult<bool> {
    // Initialize the runtime if it hasn't been already.
    RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    // Initialize the Kubernetes client using the runtime.
    CLIENT_INSTANCE.get_or_init(|| {
        RUNTIME
            .get()
            .unwrap()
            .block_on(Client::try_default())
            .expect("Failed to create Kubernetes client")
    });

    println!("Client initatiet");
    Ok(true)
}

/// Fetch K8s resources (LIST or GET) as a single-line JSON string.
///
/// ## Parameters (as a Lua tuple):
/// - `resource`: String (e.g. "Pod", "Deployment")
/// - `group`: Option<String> (e.g. "" for core resources; "apps" for Deployments)
/// - `version`: Option<String> (default "v1")
/// - `name`: Option<String> (if provided, a single GET; otherwise LIST)
/// - `namespace`: Option<String> (if provided, queries that namespace; else all)
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
    let rt: &Runtime = RUNTIME
        .get()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?;
    let client: &Client = CLIENT_INSTANCE
        .get()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?;

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
    exports.set("init_client", lua.create_function(init_client)?)?;
    exports.set("get_resource", lua.create_function(get_resource)?)?;

    Ok(exports)
}
