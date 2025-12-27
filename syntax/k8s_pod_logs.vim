" Syntax highlighting for kubectl.nvim pod logs
if exists("b:current_syntax")
  finish
endif

" Container prefix: [container-name] at start of line
syn match kubectlLogContainer /^\[[^\]]\+\]\s/

" Kubernetes timestamp: 2024-01-15T10:30:45.123456789Z
syn match kubectlLogTimestamp /\d\{4}-\d\{2}-\d\{2}T\d\{2}:\d\{2}:\d\{2}\(\.\d\+\)\?Z/

" Log levels (case-insensitive)
syn case ignore
syn keyword kubectlLogError ERROR FATAL PANIC CRITICAL
syn keyword kubectlLogWarn WARN WARNING
syn keyword kubectlLogInfo INFO
syn keyword kubectlLogDebug DEBUG TRACE
syn case match

" UUID: 550e8400-e29b-41d4-a716-446655440000
syn match kubectlLogUUID /\<\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}\>/

" IP addresses with optional port: 192.168.1.1 or 192.168.1.1:8080
syn match kubectlLogIP /\<\d\{1,3}\.\d\{1,3}\.\d\{1,3}\.\d\{1,3}\(:\d\+\)\?\>/

" URLs: http://... https://...
syn match kubectlLogURL /https\?:\/\/[^ \t"'<>]\+/

" Link to highlight groups
hi def link kubectlLogContainer KubectlPending
hi def link kubectlLogTimestamp KubectlGray
hi def link kubectlLogError KubectlError
hi def link kubectlLogWarn KubectlWarning
hi def link kubectlLogInfo KubectlInfo
hi def link kubectlLogDebug KubectlDebug
hi def link kubectlLogUUID Identifier
hi def link kubectlLogIP Constant
hi def link kubectlLogURL Underlined

let b:current_syntax = "k8s_pod_logs"
