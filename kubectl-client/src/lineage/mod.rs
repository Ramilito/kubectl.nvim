use mlua::{Lua, Result as LuaResult, Table as LuaTable};

pub mod builder;
pub mod orphan_rules;
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
    // Lineage graph builder
    exports.set(
        "build_lineage_graph",
        lua.create_function(|lua, (resources_json, root_name): (String, String)| {
            build_lineage_graph(lua, resources_json, root_name)
        })?,
    )?;

    // Lineage graph builder for worker threads (used with commands.run_async)
    exports.set(
        "build_lineage_graph_worker",
        lua.create_function(|_, json_input: String| build_lineage_graph_worker(json_input))?,
    )?;

    // Get related nodes from stored lineage tree
    exports.set(
        "get_lineage_related_nodes",
        lua.create_function(get_lineage_related_nodes)?,
    )?;

    // Export lineage graph to DOT format
    exports.set(
        "export_lineage_dot",
        lua.create_function(export_lineage_dot)?,
    )?;

    // Export lineage graph to Mermaid format
    exports.set(
        "export_lineage_mermaid",
        lua.create_function(export_lineage_mermaid)?,
    )?;

    // Export lineage subgraph to DOT format
    exports.set(
        "export_lineage_subgraph_dot",
        lua.create_function(export_lineage_subgraph_dot)?,
    )?;

    // Export lineage subgraph to Mermaid format
    exports.set(
        "export_lineage_subgraph_mermaid",
        lua.create_function(export_lineage_subgraph_mermaid)?,
    )?;

    // Find orphan resources
    exports.set(
        "find_lineage_orphans",
        lua.create_function(find_lineage_orphans)?,
    )?;

    // Compute impact analysis
    exports.set(
        "compute_lineage_impact",
        lua.create_function(compute_lineage_impact)?,
    )?;

    Ok(())
}
