import Base
import ../../bendlib/json.bend as J
import ./BACKENDS.bend as B

def B.complete_correspondence():
  operation => source => {==}
def B.response_family_protocol():
  identity => endpoint => credential => independent => auth => transport => stream_kind => {==}
def B.response_family_identity():
  identity => endpoint => credential => independent => auth => transport => stream_kind => {==}
def B.tool_authority_projection():
  effect => profile => input => {==}
def B.callable_identity():
  name => {==}
def B.call_identity():
  item => result => {==}
def B.independent_board_history():
  effect => {==}
def B.independent_approval_tools():
  effect => {==}
def B.independent_board_callable():
  effect => {==}
def B.namespace_binding():
  {==}
def B.echoed_tool_isolation():
  {==}
def B.independent_board_wire_tools():
  body => effect => {==}
def B.independent_approval_wire_tools():
  body => effect => {==}
def B.compaction_wire_tools():
  body => effect => {==}

def B.retry_notice_attempt():
  source => milliseconds => {==}
def B.retry_notice_status():
  source => milliseconds => {==}
def B.retry_budget_requires_cancel():
  source => {==}
def B.retry_connection_preserves_cause():
  source => {==}

def B.profile_catalog_key():
  key => profile => {==}
def B.profile_catalog_provider():
  key => profile => {==}
def B.profile_catalog_model():
  key => profile => {==}
def B.profile_catalog_default():
  profile => first => rest => {==}

def B.accepted_prepare_history():
  effect => {==}
def B.model_independent_history():
  effect => {==}
def B.compaction_independent_history():
  effect => {==}

def B.tool_receipt_input_success():
  message => profile => {==}
def B.tool_receipt_input_data():
  message => profile => {==}

def B.after_record_input_success():
  message => profile => {==}
def B.after_record_input_data():
  message => profile => {==}

def B.approval_record_input_success():
  message => profile => {==}
def B.approval_record_input_data():
  message => profile => {==}


def B.context_change_input_encoding():
  message => profile => {==}
def B.context_amendment_patch_encoding():
  key => base_revision => revision => patch => {==}
def B.context_removal_encoding():
  key => base_revision => {==}

def B.side_conversation_input_encoding():
  message => profile => {==}

def B.side_return_cursor_not_model_input():
  message => profile => {==}


def B.board_text_output_mode_plain():
  effect => {==}

def B.approval_output_mode_plain():
  effect => {==}
