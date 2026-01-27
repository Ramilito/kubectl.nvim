use mlua::{Lua, Result as LuaResult, Table as LuaTable};

pub mod builder;
pub mod orphan_rules;
pub mod query;
pub mod registry;
pub mod relationships;
pub mod resource_behavior;
pub mod tree;

pub use builder::{
    build_lineage_graph, build_lineage_graph_worker, compute_lineage_impact, export_lineage_dot,
    export_lineage_mermaid, export_lineage_subgraph_dot, export_lineage_subgraph_mermaid,
    find_lineage_orphans, get_lineage_related_nodes,
};

pub fn install(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
    exports.set(
        "build_lineage_graph",
        lua.create_function(|lua, (resources_json, root_name): (String, String)| {
            build_lineage_graph(lua, resources_json, root_name)
        })?,
    )?;

    exports.set(
        "build_lineage_graph_worker",
        lua.create_function(|_, json_input: String| build_lineage_graph_worker(json_input))?,
    )?;

    exports.set(
        "get_lineage_related_nodes",
        lua.create_function(get_lineage_related_nodes)?,
    )?;

    exports.set(
        "export_lineage_dot",
        lua.create_function(export_lineage_dot)?,
    )?;

    exports.set(
        "export_lineage_mermaid",
        lua.create_function(export_lineage_mermaid)?,
    )?;

    exports.set(
        "export_lineage_subgraph_dot",
        lua.create_function(export_lineage_subgraph_dot)?,
    )?;

    exports.set(
        "export_lineage_subgraph_mermaid",
        lua.create_function(export_lineage_subgraph_mermaid)?,
    )?;

    exports.set(
        "find_lineage_orphans",
        lua.create_function(find_lineage_orphans)?,
    )?;

    exports.set(
        "compute_lineage_impact",
        lua.create_function(compute_lineage_impact)?,
    )?;

    Ok(())
}
