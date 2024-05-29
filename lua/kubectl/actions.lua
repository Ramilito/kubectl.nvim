local hl = require("kubectl.view.highlight")
local layout = require("kubectl.view.layout")
local api = vim.api
local M = {}

function M.open_filter(content, filetype, opts)
	local bufname = "kubectl_filter"

	local buf = vim.fn.bufnr(bufname)

	if buf == -1 then
		buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(buf, bufname)
		api.nvim_buf_set_option(buf, "buftype", "prompt")
	end
	local win = layout.filter_layout(buf, filetype, opts.title or "")

	api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)

	vim.fn.prompt_setprompt(buf, content)
	vim.fn.prompt_setcallback(buf, function(input)
		if not input then
			FILTER = nil
		else
			FILTER = input
		end
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_input("R")
	end)

	vim.cmd("startinsert")

	layout.set_buf_options(buf, win, filetype, "")
	hl.set_highlighting()
end

function M.new_buffer(content, filetype, opts)
	local bufname = opts.title or ""
	if opts.is_float and bufname == "" then
		bufname = "kubectl_float"
	end

	local buf = vim.fn.bufnr(bufname)

	if buf == -1 then
		buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(buf, bufname)
	end

	if opts.hints and #opts.hints > 1 then
		api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
		api.nvim_buf_set_lines(buf, #opts.hints, -1, false, content)
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, content)
	end

	if opts.is_float then
		layout.float_layout(buf, filetype, opts.title or "", opts.syntax or filetype)
	else
		api.nvim_set_current_buf(buf)
		layout.main_layout(buf, filetype, opts.syntax or filetype)
	end
end

return M
