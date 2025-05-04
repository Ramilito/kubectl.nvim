use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Gvk {
    pub k: String,
    pub v: String,
    pub g: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetTableArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
    pub sort_by: Option<String>,
    pub sort_order: Option<String>,
    pub filter: Option<String>,
    pub filter_label: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StartReflectorArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetServerRawArgs {
    pub path: String,
}

#[derive(Clone, Deserialize, Default)]
#[serde(default)]
pub struct GetSingleArgs {
    pub kind: String,
    pub name: String,
    pub namespace: Option<String>,
    pub output: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FetchArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: Option<String>,
    pub output: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdEditArgs {
    pub path: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdDeleteArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct GetMinifiedConfig {
    pub ctx_override: Option<String>,
}
