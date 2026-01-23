--- @class kubectl.DashboardSession
--- @field write fun(self: kubectl.DashboardSession, data: string)
--- @field read_frame fun(self: kubectl.DashboardSession): table?
--- @field resize fun(self: kubectl.DashboardSession, width: number, height: number)
--- @field open fun(self: kubectl.DashboardSession): boolean
--- @field close fun(self: kubectl.DashboardSession)

--- @class kubectl.LogSession
--- @field open fun(self: kubectl.LogSession): boolean
--- @field close fun(self: kubectl.LogSession)
--- @field read_chunk fun(self: kubectl.LogSession): string[]?

--- @class kubectl.DescribeSession
--- @field open fun(self: kubectl.DescribeSession): boolean
--- @field close fun(self: kubectl.DescribeSession)
--- @field read_content fun(self: kubectl.DescribeSession): string?

--- @class kubectl.Session
--- @field open fun(self: kubectl.Session): boolean
--- @field close fun(self: kubectl.Session)
--- @field read_chunk fun(self: kubectl.Session): string?
--- @field write fun(self: kubectl.Session, data: string)

--- @class kubectl.NodeShellSession
--- @field open fun(self: kubectl.NodeShellSession): boolean
--- @field close fun(self: kubectl.NodeShellSession)
--- @field read_chunk fun(self: kubectl.NodeShellSession): string?
--- @field write fun(self: kubectl.NodeShellSession, data: string)

--- @class kubectl.ExecConfig
--- @field namespace string Namespace of the pod
--- @field pod string Pod name
--- @field container? string Container name (optional)
--- @field cmd string[] Command to execute

--- @class kubectl.DebugConfig
--- @field namespace string Namespace of the pod
--- @field pod string Pod name
--- @field image string Debug container image
--- @field target? string Target container to share namespaces with

--- @class kubectl.NodeShellConfig
--- @field node string Target node name
--- @field namespace? string Namespace for the debug pod (default: "default")
--- @field image? string Container image to use (default: "busybox:latest")
--- @field cpu_limit? string CPU limit (e.g., "100m")
--- @field mem_limit? string Memory limit (e.g., "128Mi")

--- @class kubectl.ClientImplementation
--- @field init_runtime fun(context_name: string)
--- @field init_logging fun(filepath: string)
--- @field init_metrics fun()
--- @field get_resource fun(resource_name: string, group: string?, version: string?, name: string?, namespace: string?)
--- @field get_all fun(gvk: {}, ns: string?)
--- @field get_single fun(gvk: {}, ns: string?, name: string, output: string?)
--- @field start_watcher fun(resource_name: string, group: string?, version: string?, name: string?, namespace: string?)
--- @field edit_resource fun(resource_name: string, namespace: string?, name: string, group: string?, version: string? )
--- @field exec fun(config: kubectl.ExecConfig): kubectl.Session
--- @field debug fun(config: kubectl.DebugConfig): kubectl.Session
--- @field node_shell fun(config: kubectl.NodeShellConfig): kubectl.NodeShellSession
--- @field portforward_start fun(kind: string, name: string, namespace: string, local_port: number, remote_port: number)
--- @field portforward_list fun()
--- @field portforward_stop fun(id: number)
--- @field daemonset_set_images fun(name: string, ns: string, image_spec: {} )
--- @field deployment_set_images fun(name: string, ns: string, image_spec: {} )
--- @field statefulset_set_images fun(name: string, ns: string, image_spec: {} )
--- @field start_dashboard fun(view_name: string)
--- @field start_buffer_dashboard fun(view_name: string): kubectl.DashboardSession
--- @field get_drift fun(path: string, hide_unchanged?: boolean): kubectl.DriftResult
--- @field create_job_from_cronjob fun(j_name: string, ns: string, cj_name: string, dry_run: boolean )
--- @field suspend_cronjob fun(cj_name: string, ns: string, suspend: boolean)
--- @field uncordon_node fun(name: string)
--- @field cordon_node fun(name: string)
--- @field get_config fun()
--- @field setup_queue fun()
--- @field pop_queue fun()
--- @field emit fun(key, payload)
--- @field log_session fun(pods: table[], container: string?, ...): kubectl.LogSession
--- @field describe_session fun(config: table): kubectl.DescribeSession
--- @field toggle_json fun(input: string): kubectl.ToggleJsonResult?

--- @class kubectl.ToggleJsonResult
--- @field json string
--- @field start_idx integer
--- @field end_idx integer

--- @class kubectl.DriftResult
--- @field entries kubectl.DriftEntry[]
--- @field counts {changed: integer, unchanged: integer, errors: integer}
--- @field build_error string|nil

--- @class kubectl.DriftEntry
--- @field kind string
--- @field name string
--- @field status "changed"|"unchanged"|"error"
--- @field diff string|nil
--- @field error string|nil
--- @field diff_lines integer
