use k8s_openapi::serde_json;
use k8s_openapi::{apimachinery::pkg::apis::meta::v1::Time, chrono::Utc};
use kube::api::ApiResource;
use kube::core::GroupVersionKind;
use kube::{
    api::{Api, DynamicObject, ListParams, ResourceExt},
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

/// Generic get function exposed to Lua.
/// 
/// ## Parameters (as a Lua tuple):
/// - `resource`: String (e.g. "Pod", "Deployment")
/// - `group`: Option<String> (e.g. "" for core resources; "apps" for Deployments)
/// - `version`: Option<String> (default "v1")
/// - `name`: Option<String> (if provided, a single GET is done; otherwise LIST)
/// - `namespace`: Option<String> (if provided, queries that namespace; else all)
/// - `output_mode`: Option<String> ("json" or "pretty", default "pretty")
fn get_resource(
    _lua: &Lua,
    (resource, group, version, name, namespace, output_mode): (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    // 1) Acquire the global runtime
    let rt: &Runtime = RUNTIME
        .get()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".to_string()))?;

    // 2) Acquire the global client
    let client: &Client = CLIENT_INSTANCE
        .get()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".to_string()))?;

    // 3) Build GroupVersionKind
    let group_str: String = group.unwrap_or_default(); // Default to "" (core resources)
    let version_str: String = version.unwrap_or_else(|| "v1".to_string());
    let gvk: GroupVersionKind = GroupVersionKind {
        group: group_str.clone(),
        version: version_str.clone(),
        kind: resource.clone(),
    };

    // 4) Create an ApiResource from GVK
    let ar: ApiResource = ApiResource::from_gvk(&gvk);

    // 5) Construct the Api<DynamicObject> (namespaced or cluster-wide)
    let api: Api<DynamicObject> = if let Some(ns) = namespace.clone() {
        Api::namespaced_with(client.clone(), &ns, &ar)
    } else {
        Api::all_with(client.clone(), &ar)
    };

    // 6) Default listing parameters
    let lp: ListParams = ListParams::default();

    // 7) Perform GET or LIST in an async block
    //    Explicitly type the Result so Rust can infer the error type.
    let fetch_result: Result<Vec<DynamicObject>, kube::Error> = rt.block_on(async {
        if let Some(n) = name {
            // Single GET
            let obj: DynamicObject = api.get(&n).await?;
            Ok(vec![obj])
        } else {
            // LIST all items
            let list = api.list(&lp).await?;
            Ok(list.items)
        }
    });

    // 8) Convert kube::Error to mlua::Error
    let mut items: Vec<DynamicObject> = fetch_result
        .map_err(|e: kube::Error| mlua::Error::RuntimeError(e.to_string()))?;

    // 9) Clear managed fields for clarity
    items.iter_mut().for_each(|x: &mut DynamicObject| {
        x.managed_fields_mut().clear();
    });

    // 10) Check the chosen output mode
    let output_mode_str: String = output_mode.unwrap_or_else(|| "json".to_string()).to_lowercase();
    let output: String = if output_mode_str == "json" {
        // JSON output
        serde_json::to_string_pretty(&items)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
    } else {
        // "Pretty" printing: table with NAME and AGE columns
        let max_name_len: usize = items
            .iter()
            .map(|x: &DynamicObject| x.name_any().len() + 2)
            .max()
            .unwrap_or(63);
        let mut s: String = format!(
            "{0:<width$} {1:<20}\n",
            "NAME",
            "AGE",
            width = max_name_len
        );
        for item in items {
            // let age_str: String = format_creation(item.creation_timestamp());
            // s.push_str(&format!(
            //     "{0:<width$} {1:<20}\n",
            //     item.name_any(),
            //     age_str,
            //     width = max_name_len
            // ));
        }
        s
    };

    Ok(output)
}

fn format_creation(time: Time) -> String {
    let dur = Utc::now().signed_duration_since(time.0);
    match (dur.num_days(), dur.num_hours(), dur.num_minutes()) {
        (days, _, _) if days > 0 => format!("{days}d"),
        (_, hours, _) if hours > 0 => format!("{hours}h"),
        (_, _, mins) => format!("{mins}m"),
    }
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
