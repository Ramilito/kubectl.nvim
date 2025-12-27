" Syntax highlighting for kubectl.nvim pod logs
if exists("b:current_syntax")
  finish
endif

" Container prefix: [container-name]
syn match kubectlLogContainer /^\[[^\]]\+\]\s/

" Timestamp: 2024-01-15T10:30:45.123456789Z
syn match kubectlLogTimestamp /\d\{4}-\d\{2}-\d\{2}T\d\{2}:\d\{2}:\d\{2}\(\.\d\+\)\?Z\?/

" Log levels (case-insensitive)
syn case ignore
syn keyword kubectlLogError ERROR FATAL PANIC CRITICAL
syn keyword kubectlLogWarn WARN WARNING
syn keyword kubectlLogInfo INFO
syn keyword kubectlLogDebug DEBUG TRACE
syn case match

" HTTP methods
syn keyword kubectlLogMethod GET POST PUT DELETE PATCH HEAD OPTIONS CONNECT TRACE

" HTTP status codes
syn match kubectlLogStatus2xx /\<2\d\d\>/
syn match kubectlLogStatus3xx /\<3\d\d\>/
syn match kubectlLogStatus4xx /\<4\d\d\>/
syn match kubectlLogStatus5xx /\<5\d\d\>/

" UUID: 550e8400-e29b-41d4-a716-446655440000
syn match kubectlLogUUID /\<\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}\>/

" IP addresses: 192.168.1.1
syn match kubectlLogIP /\<\d\{1,3}\.\d\{1,3}\.\d\{1,3}\.\d\{1,3}\>/

" URLs: http://... https://...
syn match kubectlLogURL /https\?:\/\/[^ \t"'<>]\+/

" Paths: /api/v1/pods (must start with / and contain more path segments)
syn match kubectlLogPath /\/[a-zA-Z0-9_.-]\+\(\/[a-zA-Z0-9_.-]*\)\+/

" Quoted strings
"syn region kubectlLogString start=/"/ skip=/\\"/ end=/"/ oneline
"syn region kubectlLogString start=/'/ skip=/\\'/ end=/'/ oneline

" Key-value pairs: key=value key="value"
syn match kubectlLogKey /\<[a-zA-Z_][a-zA-Z0-9_]*\ze=/
syn match kubectlLogKeyColon /\<[a-zA-Z_][a-zA-Z0-9_]*\ze:\s/

" JSON braces
syn match kubectlLogBrace /[{}\[\]]/

" Numbers (standalone, not part of timestamps/IPs/UUIDs)
syn match kubectlLogNumber /\s\zs-\?\d\+\(\.\d\+\)\?\ze\s/
syn match kubectlLogNumber /\s\zs-\?\d\+\(\.\d\+\)\?\ze$/
syn match kubectlLogNumber /^\zs-\?\d\+\(\.\d\+\)\?\ze\s/

" Link to highlight groups
hi def link kubectlLogContainer KubectlPending
hi def link kubectlLogTimestamp KubectlGray
hi def link kubectlLogError KubectlError
hi def link kubectlLogWarn KubectlWarning
hi def link kubectlLogInfo KubectlInfo
hi def link kubectlLogDebug KubectlDebug
hi def link kubectlLogMethod Keyword
hi def link kubectlLogStatus2xx KubectlSuccess
hi def link kubectlLogStatus3xx KubectlPending
hi def link kubectlLogStatus4xx KubectlWarning
hi def link kubectlLogStatus5xx KubectlError
hi def link kubectlLogUUID Identifier
hi def link kubectlLogIP Constant
hi def link kubectlLogURL Underlined
hi def link kubectlLogPath Directory
hi def link kubectlLogString String
hi def link kubectlLogKey Label
hi def link kubectlLogKeyColon Label
hi def link kubectlLogBrace Delimiter
hi def link kubectlLogNumber Number

let b:current_syntax = "k8s_pod_logs"
