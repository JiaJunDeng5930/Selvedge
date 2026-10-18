import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/association-map.bend as Finite
import ../INPUT.bend as U
import ./MODEL.bend as Model

law offline_upload_retry_preserves_state:
  @+state:Model.State -> @+found:Maybe<&2, Model.Transfer> -> @ticket:Nat ->
  @offline:{Model.connected(Model.access(state)) == False{} : Bool} ->
  {Model.retry(found, ticket, state) == Model.Decision{state, Nil{}} : Model.Decision}

law production_upload_retry_dispatch:
  @+state:Model.State -> @+ticket:Nat ->
  {Model.step(Model.RetryUpload{ticket}, state) ==
    Model.retry(Finite.find(~Model.Transfer, Model.transfers(state), ticket), ticket, state) : Model.Decision}

law connected_failed_upload_retries:
  @+ticket:Nat -> @+editor:U.Editor -> @+file:Model.SelectedFile -> @reason:String ->
  @+access:Model.Access -> @settings:Bool -> @appearance:Model.Appearance ->
  @+next:Nat -> @+transfers:+List<Finite.Entry(Model.Transfer)> -> @preview:Model.Preview -> @picker:Model.DirectoryPicker ->
  @connected:{Model.connected(access) == True{} : Bool} ->
  @found:{Finite.find(~Model.Transfer, transfers, ticket) == Some{Model.UploadFailed{editor, file, reason}} : Maybe<&2, Model.Transfer>} ->
  {Model.step(Model.RetryUpload{ticket}, Model.State{access, settings, appearance, next, transfers, preview, picker}) ==
    Model.Decision{Model.State{access, settings, appearance, (next + 1n : Nat),
      (next, Model.Uploading{editor, file}) <> Finite.remove(~Model.Transfer, transfers, ticket), preview, picker},
      [Model.Upload{next, file}]} : Model.Decision}

law admitted_upload_retry_replaces_atomically:
  @ticket:Nat -> @+editor:U.Editor -> @+file:Model.SelectedFile ->
  @access:Model.Access -> @settings:Bool -> @appearance:Model.Appearance ->
  @+next:Nat -> @transfers:+List<Finite.Entry(Model.Transfer)> -> @preview:Model.Preview -> @picker:Model.DirectoryPicker ->
  @evidence:{Model.retry_connected(Model.UploadRetry{ticket, editor, file,
    Model.State{access, settings, appearance, next, transfers, preview, picker}}) == True{} : Bool} ->
  {Model.retry_upload(Categories.Membership{Model.UploadRetry{ticket, editor, file,
      Model.State{access, settings, appearance, next, transfers, preview, picker}}, evidence}) ==
    Model.Decision{Model.State{access, settings, appearance, (next + 1n : Nat),
      (next, Model.Uploading{editor, file}) <> Finite.remove(~Model.Transfer, transfers, ticket), preview, picker},
      [Model.Upload{next, file}]} : Model.Decision}

law stale_disconnect_preserves_state:
  @+state:Model.State -> @+ticket:Nat -> @reason:String ->
  @stale:{Model.live_connection(Model.access(state), ticket) == False{} : Bool} ->
  {Model.step(Model.Disconnected{ticket, reason}, state) == Model.Decision{state, Nil{}} : Model.Decision}

law lost_connection_schedules_owned_recovery:
  @+access:Model.Access -> @+ticket:Nat -> @+reason:String -> @settings:Bool -> @appearance:Model.Appearance ->
  @next:Nat -> @transfers:+List<Finite.Entry(Model.Transfer)> -> @preview:Model.Preview -> @picker:Model.DirectoryPicker ->
  @owned:{Model.live_connection(access, ticket) == True{} : Bool} ->
  {Model.step(Model.Disconnected{ticket, reason},
      Model.State{access, settings, appearance, next, transfers, preview, picker}) ==
    Model.Decision{Model.State{Model.ConnectionLost{ticket, reason}, settings, appearance, next,
      Model.lose_transfers(transfers, reason), Model.NoPreview{}, picker},
      [Model.SessionEnded{}, Model.ScheduleReconnect{ticket, 1000n}]} : Model.Decision}

law stale_reconnect_preserves_state:
  @+state:Model.State -> @+ticket:Nat ->
  @stale:{Model.waiting_reconnect(Model.access(state), ticket) == False{} : Bool} ->
  {Model.step(Model.RetryConnection{ticket}, state) == Model.Decision{state, Nil{}} : Model.Decision}

law recovery_starts_fresh_attempt:
  @+access:Model.Access -> @+ticket:Nat -> @settings:Bool -> @appearance:Model.Appearance ->
  @+next:Nat -> @transfers:+List<Finite.Entry(Model.Transfer)> -> @preview:Model.Preview -> @picker:Model.DirectoryPicker ->
  @owned:{Model.waiting_reconnect(access, ticket) == True{} : Bool} ->
  {Model.step(Model.RetryConnection{ticket}, Model.State{access, settings, appearance, next, transfers, preview, picker}) ==
    Model.Decision{Model.State{Model.Connecting{next}, settings, appearance, (next + 1n : Nat),
      Model.lose_transfers(transfers, "Connection replaced"), Model.NoPreview{}, picker},
      [Model.SessionEnded{}, Model.Authenticate{next}]} : Model.Decision}

law appearance_restore_is_observation:
  @access:Model.Access -> @settings:Bool -> @old:Model.Appearance -> @next:Nat ->
  @transfers:+List<Finite.Entry(Model.Transfer)> -> @preview:Model.Preview -> @picker:Model.DirectoryPicker -> @stored:Maybe<&2, String> ->
  {Model.step(Model.AppearanceRestored{stored}, Model.State{access, settings, old, next, transfers, preview, picker}) ==
    Model.Decision{Model.State{access, settings, Model.restored_appearance(stored), next, transfers, preview, picker}, Nil{}} : Model.Decision}

law stored_dark_appearance: {Model.restored_appearance(Some{"DarkAppearance"}) == Model.DarkAppearance{} : Model.Appearance}
law stored_light_appearance: {Model.restored_appearance(Some{"LightAppearance"}) == Model.LightAppearance{} : Model.Appearance}
law absent_appearance_uses_system: {Model.restored_appearance(None{}) == Model.SystemAppearance{} : Model.Appearance}
