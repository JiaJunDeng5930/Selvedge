PRAGMA foreign_keys = ON;

CREATE TABLE schema_metadata (
    schema_key TEXT PRIMARY KEY CHECK (length(schema_key) > 0),
    schema_value TEXT NOT NULL CHECK (length(schema_value) > 0)
);

INSERT INTO schema_metadata (schema_key, schema_value)
VALUES ('selvedge_schema_version', 'router-mediated-redesign-v4');

CREATE TABLE tools (
    tool_name TEXT PRIMARY KEY CHECK (length(tool_name) > 0),
    description_text TEXT NOT NULL CHECK (length(description_text) > 0)
);

CREATE TABLE tool_parameters (
    tool_name TEXT NOT NULL,
    parameter_name TEXT NOT NULL CHECK (length(parameter_name) > 0),
    parameter_type TEXT NOT NULL CHECK (parameter_type IN ('string', 'integer', 'number', 'boolean')),
    description_text TEXT NOT NULL CHECK (length(description_text) > 0),
    is_required INTEGER NOT NULL CHECK (is_required IN (0, 1)),
    PRIMARY KEY (tool_name, parameter_name),
    UNIQUE (tool_name, parameter_name, parameter_type),
    FOREIGN KEY (tool_name) REFERENCES tools(tool_name) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX idx_tool_parameters_tool_required
    ON tool_parameters(tool_name, is_required, parameter_name);

CREATE TABLE history_nodes (
    node_id INTEGER PRIMARY KEY,
    parent_node_id INTEGER,
    content_kind TEXT NOT NULL CHECK (content_kind IN ('message', 'reasoning', 'function_call', 'function_output')),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    UNIQUE (node_id, content_kind),
    UNIQUE (node_id, parent_node_id),
    FOREIGN KEY (parent_node_id) REFERENCES history_nodes(node_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CHECK (parent_node_id IS NULL OR parent_node_id <> node_id)
);

CREATE INDEX idx_history_nodes_parent
    ON history_nodes(parent_node_id, node_id);

CREATE TABLE history_message_nodes (
    node_id INTEGER PRIMARY KEY,
    node_content_kind TEXT NOT NULL DEFAULT 'message' CHECK (node_content_kind = 'message'),
    message_role TEXT NOT NULL CHECK (message_role IN ('system', 'developer', 'user', 'assistant')),
    message_text TEXT NOT NULL,
    FOREIGN KEY (node_id, node_content_kind) REFERENCES history_nodes(node_id, content_kind) ON UPDATE RESTRICT ON DELETE CASCADE
);

CREATE TABLE history_reasoning_nodes (
    node_id INTEGER PRIMARY KEY,
    node_content_kind TEXT NOT NULL DEFAULT 'reasoning' CHECK (node_content_kind = 'reasoning'),
    reasoning_text TEXT NOT NULL,
    FOREIGN KEY (node_id, node_content_kind) REFERENCES history_nodes(node_id, content_kind) ON UPDATE RESTRICT ON DELETE CASCADE
);

CREATE TABLE history_function_call_nodes (
    node_id INTEGER PRIMARY KEY,
    node_content_kind TEXT NOT NULL DEFAULT 'function_call' CHECK (node_content_kind = 'function_call'),
    function_call_id TEXT NOT NULL CHECK (length(function_call_id) > 0),
    tool_name TEXT NOT NULL CHECK (length(tool_name) > 0),
    FOREIGN KEY (node_id, node_content_kind) REFERENCES history_nodes(node_id, content_kind) ON UPDATE RESTRICT ON DELETE CASCADE,
    FOREIGN KEY (tool_name) REFERENCES tools(tool_name) ON UPDATE CASCADE ON DELETE RESTRICT,
    UNIQUE (node_id, tool_name),
    UNIQUE (node_id, function_call_id, tool_name)
);

CREATE INDEX idx_history_function_call_id
    ON history_function_call_nodes(function_call_id);

CREATE INDEX idx_history_function_call_tool
    ON history_function_call_nodes(tool_name, node_id);

CREATE TABLE history_function_call_arguments (
    function_call_node_id INTEGER NOT NULL,
    tool_name TEXT NOT NULL CHECK (length(tool_name) > 0),
    argument_name TEXT NOT NULL CHECK (length(argument_name) > 0),
    value_type TEXT NOT NULL CHECK (value_type IN ('string', 'integer', 'number', 'boolean')),
    string_value TEXT,
    integer_value INTEGER,
    number_value REAL,
    boolean_value INTEGER CHECK (boolean_value IN (0, 1)),
    PRIMARY KEY (function_call_node_id, argument_name),
    FOREIGN KEY (function_call_node_id, tool_name) REFERENCES history_function_call_nodes(node_id, tool_name) ON UPDATE RESTRICT ON DELETE CASCADE,
    FOREIGN KEY (tool_name, argument_name, value_type) REFERENCES tool_parameters(tool_name, parameter_name, parameter_type) ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (
        (value_type = 'string' AND string_value IS NOT NULL AND integer_value IS NULL AND number_value IS NULL AND boolean_value IS NULL)
        OR (value_type = 'integer' AND string_value IS NULL AND integer_value IS NOT NULL AND number_value IS NULL AND boolean_value IS NULL)
        OR (value_type = 'number' AND string_value IS NULL AND integer_value IS NULL AND number_value IS NOT NULL AND boolean_value IS NULL)
        OR (value_type = 'boolean' AND string_value IS NULL AND integer_value IS NULL AND number_value IS NULL AND boolean_value IS NOT NULL)
    )
);

CREATE INDEX idx_history_function_call_args_call_tool
    ON history_function_call_arguments(function_call_node_id, tool_name);

CREATE INDEX idx_history_function_call_args_parameter
    ON history_function_call_arguments(tool_name, argument_name, value_type);

CREATE TABLE history_function_output_nodes (
    node_id INTEGER PRIMARY KEY,
    node_content_kind TEXT NOT NULL DEFAULT 'function_output' CHECK (node_content_kind = 'function_output'),
    function_call_node_id INTEGER NOT NULL,
    function_call_id TEXT NOT NULL CHECK (length(function_call_id) > 0),
    tool_name TEXT NOT NULL CHECK (length(tool_name) > 0),
    output_text TEXT NOT NULL,
    is_error INTEGER NOT NULL CHECK (is_error IN (0, 1)),
    FOREIGN KEY (node_id, node_content_kind) REFERENCES history_nodes(node_id, content_kind) ON UPDATE RESTRICT ON DELETE CASCADE,
    FOREIGN KEY (function_call_node_id, function_call_id, tool_name) REFERENCES history_function_call_nodes(node_id, function_call_id, tool_name) ON UPDATE RESTRICT ON DELETE RESTRICT,
    UNIQUE (function_call_node_id)
);

CREATE INDEX idx_history_function_output_call
    ON history_function_output_nodes(function_call_node_id);

CREATE TABLE tasks (
    task_id TEXT PRIMARY KEY CHECK (length(task_id) > 0),
    task_status TEXT NOT NULL CHECK (task_status IN ('active', 'archived')),
    cursor_node_id INTEGER NOT NULL,
    model_profile_key TEXT NOT NULL CHECK (length(model_profile_key) > 0),
    reasoning_effort TEXT NOT NULL CHECK (reasoning_effort IN ('minimal', 'low', 'medium', 'high')),
    state_version INTEGER NOT NULL DEFAULT 0 CHECK (state_version >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
    UNIQUE (task_id, task_status),
    FOREIGN KEY (cursor_node_id) REFERENCES history_nodes(node_id) ON UPDATE RESTRICT ON DELETE RESTRICT
);

CREATE INDEX idx_tasks_status_updated
    ON tasks(task_status, updated_at DESC, task_id);

CREATE INDEX idx_tasks_cursor
    ON tasks(cursor_node_id, task_id);

CREATE TABLE task_tools (
    task_id TEXT NOT NULL,
    tool_name TEXT NOT NULL CHECK (length(tool_name) > 0),
    PRIMARY KEY (task_id, tool_name),
    FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON UPDATE RESTRICT ON DELETE CASCADE,
    FOREIGN KEY (tool_name) REFERENCES tools(tool_name) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX idx_task_tools_tool
    ON task_tools(tool_name, task_id);

CREATE TABLE task_parent_edges (
    parent_task_id TEXT NOT NULL,
    child_task_id TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    PRIMARY KEY (parent_task_id, child_task_id),
    UNIQUE (child_task_id),
    FOREIGN KEY (parent_task_id) REFERENCES tasks(task_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    FOREIGN KEY (child_task_id) REFERENCES tasks(task_id) ON UPDATE RESTRICT ON DELETE CASCADE,
    CHECK (parent_task_id <> child_task_id)
);

CREATE INDEX idx_task_parent_edges_parent_created
    ON task_parent_edges(parent_task_id, created_at, child_task_id);

CREATE TABLE queued_user_inputs (
    task_id TEXT NOT NULL,
    seq_no INTEGER NOT NULL CHECK (seq_no >= 1),
    task_status TEXT NOT NULL DEFAULT 'active' CHECK (task_status = 'active'),
    message_text TEXT NOT NULL CHECK (length(message_text) > 0),
    queued_at INTEGER NOT NULL CHECK (queued_at >= 0),
    PRIMARY KEY (task_id, seq_no),
    FOREIGN KEY (task_id, task_status) REFERENCES tasks(task_id, task_status) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_queued_user_inputs_task_order
    ON queued_user_inputs(task_id, seq_no);
