local function keymap_in_bufs(bufs, modes, key, action, opts)
  for _, buf in ipairs(bufs) do
    for _, mode in ipairs(modes) do
      vim.api.nvim_buf_set_keymap(buf, mode, key, action, opts)
    end
  end
end

local function get_lines(range, buf)
  if range == "%" then
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end
  local cmd = string.format('echo join(getbufline(%d, %s), "\\n")', buf, range)
  return vim.fn.execute(cmd) -- Evaluate in Vim and return result
end

local function expand_pattern_in_string(str, buf)
  local expanded_str = str:gsub("expand:([^\n\r ]+)", function(match)
    return get_lines(match, buf)
  end)
  return expanded_str
end

local function curl_json(url, data, callback)
  local stdout = vim.uv.new_pipe()
  local stderr = vim.uv.new_pipe()
  local handle, pid = vim.uv.spawn("curl", {
    args = {
      "-s",
      "--no-buffer",
      "-X",
      "POST",
      "-H",
      "Content-Type: application/json",
      "-d",
      vim.json.encode(data),
      url,
    },
    env = { "PATH=" .. os.getenv("PATH") },
    stdio = { nil, stdout, stderr },
  }, function(code, _)
    if code ~= 0 then
      callback("Request Failed", true)
    end
  end)

  if not handle or not stdout then
    callback("[Error] Failed to start Ollama request", true)
    return
  end
  local curr_chunk = ""

  vim.uv.read_start(stdout, function(err, chunk)
    if err then
      callback("[Error] Stream read failed", true)
      return
    end
    if not chunk then
      return
    end
    curr_chunk = curr_chunk .. chunk
    local last_char = string.sub(chunk, -1)
    -- if we don't have a full line, wait for more data
    if last_char ~= "\n" then
      return
    end

    for line in curr_chunk:gmatch("[^\r\n]+") do
      local data = vim.json.decode(line)
      if data then
        callback(data, false)
      end
    end
    curr_chunk = ""
  end)
  return handle
end

local function ollama_request(prompt, context, model, callback)
  if not context then
    prompt = table.concat({
      "System: You are an AI answering users questions. The user is deeeply technical.",
      "They are most often asking about programming.",
      "You are expected to provide detailed, consice and accurate answers.",
      "Where it makes sense stick to code.",
      "User: ",
    }, "\n") .. prompt
  else
    prompt = "User: " .. prompt
  end
  prompt = prompt .. "\nAI:"

  local body = { model = model, prompt = prompt, stream = true, context = context }
  return curl_json("http://localhost:11434/api/generate", body, function(response, is_error)
    if is_error then
      callback({
        response = "[Error] Ollama request failed",
        done = true,
      }, true)
    else
      callback(response, false)
    end
  end)
end

-- Function to send a string to Ollama and stream to a buffer
local function stream_ollama(prompt, state)
  local buf_id = state.chat_buf
  local win_id = state.chat_win
  local think_lines = {}
  local thinking_finished = false
  local think_i = 1
  local max_ticks = 6
  local rate = 10
  return ollama_request(prompt, state.context, state.model, function(response, is_error)
    local i_ = response.response
    if response.done then
      i_ = i_ .. "\n\n\n"
    end
    if i_ == "</think>" then
      thinking_finished = true
      -- print(vim.inspect(think_lines))
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf_id, -2, -1, false, { "", "" })
      end)
      return
    end
    if not thinking_finished then
      table.insert(think_lines, i_)
      local lines = {
        "Thinking ",
      }
      for _ = 0, math.floor(think_i / rate) do
        lines[1] = lines[1] .. "."
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf_id) then
          return
        end
        vim.api.nvim_buf_set_lines(buf_id, -2, -1, false, lines)
      end)
      think_i = (think_i + 1) % (max_ticks * rate)
      return
    end
    if response.context then
      print("Context updated")
      state.context = response.context
    end
    local lines = {}
    for line in i_:gmatch("[^\n]*") do
      table.insert(lines, line)
    end
    -- remove last empty line
    table.remove(lines, #lines)
    if i_ == "\n" then
      lines = { "", "" }
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf_id) then
        return
      end
      lines[1] = (vim.api.nvim_buf_get_lines(buf_id, -2, -1, false)[1] or "") .. (lines[1] or "")
      vim.api.nvim_buf_set_lines(buf_id, -2, -1, false, lines)
      if #lines <= 1 then
        return
      end
      local last_line = vim.api.nvim_buf_line_count(buf_id)
      vim.api.nvim_win_set_cursor(win_id, { last_line, 0 })
    end)
    if is_error then
      print(response)
    end
  end)
end

local Models = {
  "deepseek-r1:1.5b",
  "deepseek-r1:14b",
  "deepseek-r1:32b",
}

local State = {
  context = {},
  model = "deepseek-r1:32b",
  curr_buf = nil,
  chat_lines = { "", "", "... Waiting for first message:" },
  req_handle = nil,
  chat_win = nil,
  chat_buf = nil,
  input_win = nil,
  input_buf = nil,
  selected_range = nil,
}

local function close()
  if State.req_handle then
    State.req_handle:close()
    State.req_handle = nil
  end
  -- close buffers and window
  State.chat_lines = vim.api.nvim_buf_get_lines(State.chat_buf, 0, -1, false)
  vim.api.nvim_buf_delete(State.chat_buf, { force = true })
  vim.api.nvim_buf_delete(State.input_buf, { force = true })
  State.chat_buf = nil
end

local function open()
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  State.curr_buf = vim.api.nvim_get_current_buf()
  State.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(State.chat_buf, 0, -1, false, State.chat_lines)
  State.chat_win = vim.api.nvim_open_win(State.chat_buf, false, {
    relative = "editor",
    width = width,
    height = height - 5,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_set_option_value("filetype", "markdown", {
    buf = State.chat_buf,
  })

  vim.api.nvim_set_option_value("wrap", true, {
    win = State.chat_win,
  })

  State.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(State.input_buf, 0, -1, false, { "" })
  State.input_win = vim.api.nvim_open_win(State.input_buf, true, {
    relative = "editor",
    width = width,
    height = 3,
    row = row + height - 3,
    col = col,
    style = "minimal",
    border = "rounded",
  })
end

vim.api.nvim_set_hl(0, "ChatStatusLine", {
  fg = "#000000",
  bg = "#e5e5e5",
})

local function update_status_line()
  local is_input = vim.api.nvim_get_current_buf() == State.input_buf
  local status = string.format("Model: %s | Active Buffer: %s", State.model, is_input and "Input" or "Chat")

  -- Update the text in the chat buffer
  vim.api.nvim_buf_set_lines(State.chat_buf, 0, 1, false, { status })

  -- Apply custom highlight to the first line
  local line_len = #status
  vim.api.nvim_buf_add_highlight(State.chat_buf, -1, "ChatStatusLine", 0, 0, line_len)
end
-- Function to handle Enter key
local function on_enter()
  if State.req_handle then
    State.req_handle:close()
    State.req_handle = nil
  end
  local input_lines = vim.api.nvim_buf_get_lines(State.input_buf, 0, -1, false)
  local has_data = #input_lines > 0 and input_lines[1] ~= ""
  if not has_data then
    return
  end
  local model = nil
  if input_lines[1]:match("^:ctx") then
    input_lines = {
      "This is a context message. It is not a question.",
      "Repond only with 'OK!' for now. I'll ask questions later.",
      "Below is the code file I'm working on.",
      "Remember this as context.",
      "Respond only with 'OK!'",
      "<code>",
      "expand:%",
      "</code>",
      "Remeber this, but respond only with 'OK!'",
      "For this message I only need 'OK!' as confirmation.",
      "Later I'll ask questions, however respond here only with 'OK!'",
    }
    model = State.model
    State.model = "deepseek-r1:1.5b"
  end
  -- if the first line starts with  :model graph the rest of the test and search for a match in "Models"
  if input_lines[1]:match("^:model") then
    local model_ = input_lines[1]:match(":model%s+(%S+)")
    if not model_ then
      print("No model specified")
      return
    end
    local found = false
    -- if the text is in the model name string then set the model
    for _, m in ipairs(Models) do
      if m:find(model_) then
        State.model = m
        found = true
        break
      end
    end
    if not found then
      print("Model not found")
      return
    end
    update_status_line()
    vim.api.nvim_buf_set_lines(State.chat_buf, -1, -1, false, { "Set Model: " .. State.model })
    -- if  the number of non empty lines is 1 then clear the input
    local non_empty_lines = 0
    for _, line in ipairs(input_lines) do
      if line ~= "" then
        non_empty_lines = non_empty_lines + 1
      end
    end
    if non_empty_lines == 1 then
      vim.api.nvim_buf_set_lines(State.input_buf, 0, -1, false, { "" }) -- Clear input
      return
    end

    input_lines = vim.list_slice(input_lines, 2, #input_lines)
  end
  local print_lines = vim.tbl_map(function(line)
    return "> " .. line
  end, input_lines)
  local prompt = table.concat(input_lines, " ")
  vim.api.nvim_buf_set_lines(State.chat_buf, -1, -1, false, { " ", "### You", "" })
  vim.api.nvim_buf_set_lines(State.chat_buf, -1, -1, false, print_lines)
  vim.api.nvim_buf_set_lines(State.chat_buf, -1, -1, false, { "", "### Bot", "", "" })
  -- focus to the bottom
  local last_line = vim.api.nvim_buf_line_count(State.chat_buf)
  vim.api.nvim_win_set_cursor(State.chat_win, { last_line, 0 })
  vim.api.nvim_buf_set_lines(State.input_buf, 0, -1, false, { "" }) -- Clear input

  if State.selected_range and not State.selected_range.sent then
    local selected_text = table.concat(
      vim.api.nvim_buf_get_lines(
        State.selected_range.buf,
        State.selected_range.lstart,
        State.selected_range.lend,
        false
      ),
      "\n"
    )
    State.selected_range.sent = true
    prompt = selected_text .. "\n" .. prompt
  end
  State.req_handle = stream_ollama(expand_pattern_in_string(prompt, State.curr_buf), State)
  State.model = model or State.model
end

local function cycle_buffers()
  local current_win = vim.api.nvim_get_current_win()
  if current_win == State.input_win then
    vim.api.nvim_set_current_win(State.chat_win)
    update_status_line()
    return
  end
  vim.api.nvim_set_current_win(State.input_win)
  update_status_line()
end

local function clear_state()
  State.context = {}
  State.chat_lines = { "", "", "... Waiting for first message:" }
  vim.api.nvim_buf_set_lines(State.chat_buf, 0, -1, false, State.chat_lines)
  update_status_line()
  State.req_handle = nil
end

local function open_floating_window(opts)
  if State.chat_buf then
    close()
    return
  end
  if opts.range then
    vim.cmd([[execute "normal! \<ESC>"]])
    local lstart2 = vim.fn.getpos("'<")[2]
    local lend2 = vim.fn.getpos("'>")[2]
    State.selected_range = {
      buf = vim.api.nvim_get_current_buf(),
      lstart = lstart2,
      lend = lend2,
    }
  else
    State.selected_range = nil
  end
  open()
  vim.cmd("startinsert")
  update_status_line()

  local buffers = { State.input_buf, State.chat_buf }
  -- Ctr-n to clear state
  keymap_in_bufs(buffers, { "i", "n" }, "<C-n>", "", {
    noremap = true,
    silent = true,
    callback = clear_state,
  })
  keymap_in_bufs(buffers, { "i", "n" }, "<Tab>", "", {
    noremap = true,
    silent = true,
    callback = cycle_buffers,
  })
  keymap_in_bufs(buffers, { "i", "n" }, "<Esc>", "", {
    noremap = true,
    silent = true,
    callback = cycle_buffers,
  })
  keymap_in_bufs(buffers, { "n" }, "q", "", {
    noremap = true,
    silent = true,
    callback = close,
  })
  keymap_in_bufs({ State.input_buf }, { "i", "n" }, "<CR>", "", {
    noremap = true,
    silent = true,
    callback = on_enter,
  })
end

vim.api.nvim_create_user_command("Cocoder", open_floating_window, { range = true, nargs = "*" })
vim.keymap.set("n", "<leader>gp", ":Cocoder<CR>", { desc = "Open Ollama chat window", silent = true })
vim.keymap.set("v", "<leader>gp", ":Cocoder<CR>", { desc = "Open Ollama chat window", silent = true })
